-- =============================================================================
-- PROMPT 11.3.13 — editar_documento_sei_pendente: bloquear edição de documento
-- ENCERRADO (nenhum item PENDENTE)
-- =============================================================================
-- STATUS: PREPARADA PARA REVISÃO — NÃO APLICADA. Nada foi executado no
-- Supabase. Revise antes de aplicar.
--
-- REGRA: um Documento SEI só pode ser editado enquanto (a) tiver ao menos um
-- item PENDENTE e (b) não tiver item CONCLUIDO. (b) já existia; (a) é nova:
-- todos os itens CANCELADOS, todos CONCLUIDOS ou qualquer combinação sem
-- PENDENTE = documento encerrado operacionalmente. A UI Flutter já esconde o
-- botão "Editar documento" nesse caso; esta migration coloca a mesma proteção
-- no banco (a UI sozinha nunca é garantia).
--
-- O QUE MUDA: SOMENTE o bloco `if not exists (...) then raise exception ...`
-- inserido logo após o bloqueio por item concluído. Todo o resto do corpo é
-- idêntico ao da migration 20260921170000_add_documentos_sei.sql (que NÃO é
-- editada). Mesmo nome, mesmos parâmetros, mesmo retorno
-- (`public.documentos_sei`), `language plpgsql`, `security definer`,
-- `set search_path = ''`.
--
-- PERMISSÕES: o comando CREATE OR REPLACE FUNCTION mantém dono e ACL. Os
-- revoke/grant da migration anterior (execute só para `authenticated`)
-- continuam valendo — por isso nenhum GRANT/REVOKE é repetido aqui.
--
-- NÃO TOCA: cancelar_pendentes_documento_sei, cancelar_item_sei_pendente,
-- criar_documento_sei_pendente, nenhum dado existente, nenhuma tabela.
--
-- ANTES DE APLICAR (só leitura): compare com a função implantada —
--   select pg_get_functiondef('public.editar_documento_sei_pendente(uuid,integer,text,jsonb,jsonb)'::regprocedure);
-- O corpo abaixo parte da definição do repositório; se a implantada divergir,
-- avise antes de aplicar.
--
-- DEPOIS DE APLICAR (só leitura):
--   select p.prosecdef, p.proconfig, pg_get_function_identity_arguments(p.oid),
--          p.prosrc like '%encerrado (nenhum item pendente)%' as tem_protecao
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'editar_documento_sei_pendente';
-- =============================================================================

create or replace function public.editar_documento_sei_pendente(
  p_documento_id uuid,
  p_versao_esperada integer,
  p_motivo text,
  p_alteracoes jsonb default '{}'::jsonb,
  p_itens_alterados jsonb default '[]'::jsonb
)
returns public.documentos_sei
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_documento public.documentos_sei;
  v_item_edicao jsonb;
  v_qtd_concluidos integer;
  v_dados_antes jsonb;
  v_itens_antes jsonb;
  v_itens_depois jsonb;
  v_ids_itens_alterados uuid[];
  v_item_id uuid;
  v_item_check public.documentos_sei_itens;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para editar documento SEI pendente'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo é obrigatório para editar um documento SEI pendente'
      using errcode = 'P0001';
  end if;

  -- trava o documento: edições concorrentes sobre o mesmo documento são
  -- serializadas (seção 14) — a segunda espera a primeira terminar e então
  -- vê a versão já incrementada, falhando na checagem abaixo.
  select * into v_documento
  from public.documentos_sei
  where id = p_documento_id
  for update;

  if not found then
    raise exception 'Documento SEI pendente % não encontrado', p_documento_id
      using errcode = 'P0002';
  end if;

  if v_documento.versao <> p_versao_esperada then
    raise exception 'Conflito de edição: versão % informada, versão atual % — releia o documento antes de tentar novamente',
      p_versao_esperada, v_documento.versao
      using errcode = 'P0010';
  end if;

  -- Seção 8: REGRA DEFINITIVA — bloqueado para sempre após a primeira
  -- conclusão, independentemente da versão informada estar correta.
  --
  -- PROMPT 11.3.2, seção 3 — auditoria encontrou: a versão anterior gravava
  -- um evento 'TENTATIVA_BLOQUEADA' IMEDIATAMENTE ANTES do `raise
  -- exception` abaixo. Uma exceção desfaz TODA a transação corrente,
  -- inclusive esse INSERT — o evento nunca era commitado, então a função
  -- prometia uma trilha de auditoria que na prática nunca existia. Não é
  -- resolvido "engolindo" a exceção e retornando sucesso (inverteria a
  -- regra da seção 8) nem criando um serviço externo de auditoria (fora do
  -- escopo desta etapa) — a correção é simplesmente NÃO fingir que este
  -- evento persiste: a tentativa bloqueada é reportada ao cliente só pelo
  -- próprio erro (que o Flutter já traduz em
  -- `SeiDocumentoBloqueadoParaEdicaoException`), sem gravação alguma.
  -- 'TENTATIVA_BLOQUEADA' permanece um tipo válido em
  -- `documentos_sei_eventos_tipo_valido` para uma eventual estratégia
  -- futura (ex.: log em tabela própria fora da transação de negócio), mas
  -- NENHUMA função desta migration o produz hoje.
  select count(*) into v_qtd_concluidos
  from public.documentos_sei_itens
  where documento_id = p_documento_id and status = 'CONCLUIDO';

  if v_qtd_concluidos > 0 then
    raise exception 'Documento % está bloqueado para edição: já tem item concluído', p_documento_id
      using errcode = '42501';
  end if;

  -- PROMPT 11.3.13 — documento ENCERRADO (nenhum item PENDENTE: todos
  -- cancelados e/ou concluídos) também não pode mais ser editado. Antes, só a
  -- presença de item CONCLUÍDO bloqueava: num documento 100% cancelado ainda
  -- era possível alterar assunto, número do documento e processo.
  --
  -- Posição: DEPOIS do lock do documento (`for update`, acima) e da checagem
  -- de versão, e logo DEPOIS do bloqueio por item concluído (que continua com
  -- precedência e mensagem própria); ANTES de qualquer validação do payload,
  -- lock de item ou escrita. Como o documento já está travado e todas as
  -- funções de escrita SEI travam o documento ANTES dos itens, nenhum
  -- cancelamento/conclusão concorrente muda o conjunto de itens PENDENTES
  -- entre esta leitura e o fim da função. Só lê: não adiciona nenhum lock
  -- novo, então a ordem documento -> itens permanece a mesma.
  --
  -- A mensagem contém "bloqueado" e o errcode é 42501: o Flutter já traduz
  -- essa combinação em `SeiDocumentoBloqueadoParaEdicaoException`.
  if not exists (
    select 1
    from public.documentos_sei_itens
    where documento_id = p_documento_id
      and status = 'PENDENTE'
  ) then
    raise exception 'Documento % está bloqueado para edição: encerrado (nenhum item pendente)', p_documento_id
      using errcode = '42501';
  end if;

  if jsonb_typeof(p_alteracoes) <> 'object' then
    raise exception 'p_alteracoes precisa ser um objeto jsonb' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_itens_alterados) <> 'array' then
    raise exception 'p_itens_alterados precisa ser um array jsonb' using errcode = 'P0001';
  end if;

  -- PROMPT 11.3.2, seção 4 — auditoria encontrou: o loop de UPDATE mais
  -- abaixo filtrava por `id = ... and documento_id = ... and status =
  -- 'PENDENTE'` sem NUNCA conferir se o UPDATE realmente afetou alguma
  -- linha — um item_id inexistente, de outro documento, ou que já não
  -- estava mais PENDENTE simplesmente não batia com o WHERE, e a função
  -- retornava sucesso do mesmo jeito, gravando um evento 'EDICAO' como se
  -- toda correção solicitada tivesse sido aplicada (falha silenciosa).
  -- Corrigido com uma validação PRÉVIA, ANTES de qualquer escrita: cada
  -- item_id precisa existir, pertencer a ESTE documento, estar PENDENTE, e
  -- não pode se repetir no payload (tratado explicitamente como erro, não
  -- como "a última correção do mesmo id vence" — ambíguo demais para
  -- aceitar silenciosamente). Qualquer violação rejeita a operação
  -- INTEIRA: a exceção desfaz também a atualização dos campos do documento
  -- feita mais abaixo, já que tudo roda na mesma transação — nada fica
  -- parcialmente aplicado. `for update` aqui trava cada item validado (na
  -- mesma ordem documento→item já estabelecida) até o fim da função.
  v_ids_itens_alterados := array[]::uuid[];
  for v_item_edicao in select * from jsonb_array_elements(p_itens_alterados)
  loop
    if not (v_item_edicao ? 'item_id') or nullif(v_item_edicao ->> 'item_id', '') is null then
      raise exception 'Cada elemento de p_itens_alterados precisa de item_id' using errcode = 'P0001';
    end if;
    v_item_id := (v_item_edicao ->> 'item_id')::uuid;

    if v_item_id = any (v_ids_itens_alterados) then
      raise exception 'item_id % repetido em p_itens_alterados', v_item_id using errcode = 'P0001';
    end if;
    v_ids_itens_alterados := array_append(v_ids_itens_alterados, v_item_id);

    select * into v_item_check from public.documentos_sei_itens where id = v_item_id for update;
    if not found then
      raise exception 'Item % não encontrado', v_item_id using errcode = 'P0002';
    end if;
    if v_item_check.documento_id <> p_documento_id then
      raise exception 'Item % não pertence ao documento %', v_item_id, p_documento_id using errcode = 'P0001';
    end if;
    if v_item_check.status <> 'PENDENTE' then
      raise exception 'Item % não está PENDENTE (está %) — não pode ser editado', v_item_id, v_item_check.status
        using errcode = 'P0001';
    end if;
  end loop;

  v_dados_antes := jsonb_build_object(
    'numero_documento_sei', v_documento.numero_documento_sei,
    'numero_processo', v_documento.numero_processo,
    'numero_documento_formatado', v_documento.numero_documento_formatado,
    'assunto', v_documento.assunto
  );

  -- PROMPT 11.3.1, seção 7: retrato "antes" dos itens que serão tocados —
  -- capturado ANTES do loop de correção, para o evento de auditoria
  -- registrar o antes/depois real (não só dos campos do documento).
  select coalesce(jsonb_agg(to_jsonb(i.*)), '[]'::jsonb) into v_itens_antes
  from public.documentos_sei_itens i
  where i.documento_id = p_documento_id and i.id = any (coalesce(v_ids_itens_alterados, array[]::uuid[]));

  update public.documentos_sei set
    numero_documento_sei = case when p_alteracoes ? 'numero_documento_sei'
      then p_alteracoes ->> 'numero_documento_sei' else numero_documento_sei end,
    numero_processo = case when p_alteracoes ? 'numero_processo'
      then p_alteracoes ->> 'numero_processo' else numero_processo end,
    numero_documento_formatado = case when p_alteracoes ? 'numero_documento_formatado'
      then p_alteracoes ->> 'numero_documento_formatado' else numero_documento_formatado end,
    assunto = case when p_alteracoes ? 'assunto' then p_alteracoes ->> 'assunto' else assunto end,
    versao = versao + 1,
    atualizado_em = now()
  where id = p_documento_id
  returning * into v_documento;

  for v_item_edicao in select * from jsonb_array_elements(p_itens_alterados)
  loop
    update public.documentos_sei_itens set
      numero_patrimonio_corrigido = case when v_item_edicao ? 'numero_patrimonio_corrigido'
        then v_item_edicao ->> 'numero_patrimonio_corrigido' else numero_patrimonio_corrigido end,
      destino_texto_corrigido = case when v_item_edicao ? 'destino_texto_corrigido'
        then v_item_edicao ->> 'destino_texto_corrigido' else destino_texto_corrigido end,
      numero_chamado_corrigido = case when v_item_edicao ? 'numero_chamado_corrigido'
        then v_item_edicao ->> 'numero_chamado_corrigido' else numero_chamado_corrigido end,
      equipamento_texto_corrigido = case when v_item_edicao ? 'equipamento_texto_corrigido'
        then v_item_edicao ->> 'equipamento_texto_corrigido' else equipamento_texto_corrigido end,
      -- Seção 3 desta auditoria: agora também editáveis enquanto o
      -- documento não tiver item concluído — destino resolvido,
      -- localização e responsável de destino (decisão + valor sempre
      -- juntos, para nunca violar as constraints de coerência da seção 2).
      destino_setor_id = case when v_item_edicao ? 'destino_setor_id'
        then nullif(v_item_edicao ->> 'destino_setor_id', '')::uuid else destino_setor_id end,
      localizacao_destino_id = case when v_item_edicao ? 'localizacao_destino_id'
        then nullif(v_item_edicao ->> 'localizacao_destino_id', '')::uuid else localizacao_destino_id end,
      decisao_localizacao = case when v_item_edicao ? 'decisao_localizacao'
        then (v_item_edicao ->> 'decisao_localizacao')::public.documento_sei_decisao_campo else decisao_localizacao end,
      responsavel_destino = case when v_item_edicao ? 'responsavel_destino'
        then v_item_edicao ->> 'responsavel_destino' else responsavel_destino end,
      decisao_responsavel = case when v_item_edicao ? 'decisao_responsavel'
        then (v_item_edicao ->> 'decisao_responsavel')::public.documento_sei_decisao_campo else decisao_responsavel end,
      corrigido_por = auth.uid(),
      corrigido_em = now(),
      motivo_correcao = p_motivo
    where id = (v_item_edicao ->> 'item_id')::uuid
      and documento_id = p_documento_id
      and status = 'PENDENTE'; -- defesa extra: nunca corrige item concluído/cancelado
  end loop;

  select coalesce(jsonb_agg(to_jsonb(i.*)), '[]'::jsonb) into v_itens_depois
  from public.documentos_sei_itens i
  where i.documento_id = p_documento_id and i.id = any (coalesce(v_ids_itens_alterados, array[]::uuid[]));

  insert into public.documentos_sei_eventos (documento_id, tipo, descricao, dados_antes, dados_depois, autor_id)
  values (
    p_documento_id, 'EDICAO', p_motivo,
    jsonb_build_object('documento', v_dados_antes, 'itens', v_itens_antes),
    jsonb_build_object(
      'documento', jsonb_build_object(
        'numero_documento_sei', v_documento.numero_documento_sei,
        'numero_processo', v_documento.numero_processo,
        'numero_documento_formatado', v_documento.numero_documento_formatado,
        'assunto', v_documento.assunto
      ),
      'itens', v_itens_depois
    ),
    auth.uid()
  );

  return v_documento;
end;
$$;
