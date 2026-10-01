-- =============================================================================
-- editar_documento_sei_pendente: bloquear edição de documento
-- ENCERRADO (nenhum item PENDENTE)
-- =============================================================================
-- REGRA: um Documento SEI só pode ser editado enquanto (a) tiver ao menos um
-- item PENDENTE e (b) não tiver item CONCLUIDO. (b) já existia; (a) é nova:
-- todos os itens CANCELADOS, todos CONCLUIDOS ou qualquer combinação sem
-- PENDENTE = documento encerrado operacionalmente. A UI Flutter já esconde o
-- botão "Editar documento" nesse caso; esta migration coloca a mesma proteção
-- no banco (a UI sozinha nunca é garantia).
--
-- Reaplica a função inteira (CREATE OR REPLACE mantém dono e ACL — revoke/
-- grant da migration anterior continuam valendo).
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
  -- serializadas — a segunda espera a primeira terminar e então vê a
  -- versão já incrementada, falhando na checagem abaixo.
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

  -- REGRA DEFINITIVA: bloqueado para sempre após a primeira conclusão,
  -- independentemente da versão informada estar correta.
  --
  -- Não grava um evento 'TENTATIVA_BLOQUEADA' aqui: `raise exception`
  -- desfaz TODA a transação corrente, então um INSERT de auditoria antes
  -- dele nunca seria commitado. A tentativa bloqueada é reportada ao
  -- cliente só pelo próprio erro (que o Flutter traduz em
  -- `SeiDocumentoBloqueadoParaEdicaoException`). 'TENTATIVA_BLOQUEADA'
  -- permanece um tipo válido em `documentos_sei_eventos_tipo_valido` para
  -- uma eventual estratégia futura fora desta transação.
  select count(*) into v_qtd_concluidos
  from public.documentos_sei_itens
  where documento_id = p_documento_id and status = 'CONCLUIDO';

  if v_qtd_concluidos > 0 then
    raise exception 'Documento % está bloqueado para edição: já tem item concluído', p_documento_id
      using errcode = '42501';
  end if;

  -- Documento ENCERRADO (nenhum item PENDENTE: todos cancelados e/ou
  -- concluídos) também não pode mais ser editado. Roda DEPOIS do lock do
  -- documento acima — como todas as funções de escrita SEI travam o
  -- documento ANTES dos itens, nenhum cancelamento/conclusão concorrente
  -- muda o conjunto de itens PENDENTES entre esta leitura e o fim da função.
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

  -- Validação PRÉVIA, ANTES de qualquer escrita: cada item_id precisa
  -- existir, pertencer a ESTE documento, estar PENDENTE, e não pode se
  -- repetir no payload — senão um UPDATE filtrado por WHERE simplesmente
  -- não bateria em nenhuma linha e a função gravaria um evento 'EDICAO'
  -- como se a correção tivesse sido aplicada (falha silenciosa). Qualquer
  -- violação rejeita a operação INTEIRA (mesma transação, nada fica
  -- parcialmente aplicado). `for update` trava cada item validado (na
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

  -- Retrato "antes" dos itens que serão tocados — capturado ANTES do loop
  -- de correção, para o evento de auditoria registrar o antes/depois real
  -- (não só dos campos do documento).
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
      -- Também editáveis enquanto o documento não tiver item concluído:
      -- destino resolvido, localização e responsável de destino (decisão +
      -- valor sempre juntos, para nunca violar as constraints de coerência).
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
