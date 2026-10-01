-- =============================================================================
-- PROMPT 11.4.2 (parte B) — public.concluir_item_documento_sei
-- Concluir a ENTREGA de UM item de Documento SEI, de forma atômica.
-- =============================================================================
-- STATUS: PREPARADA PARA REVISÃO — NÃO APLICADA. Nada foi executado no
-- Supabase. Nenhum patrimônio real foi movimentado; nenhum item foi concluído.
--
-- ORDEM DE APLICAÇÃO: depois de 20260925130000 (que mantém `patrimonio_id`
-- coerente na edição). Sem ela, um item corrigido continuaria vinculado ao
-- patrimônio antigo — esta função barra isso na conclusão (P0031), mas a edição
-- é quem evita a incoerência na origem.
--
-- REGRA CENTRAL: salvar/importar um Documento SEI NÃO movimenta patrimônio. A
-- movimentação só nasce quando a GETEC confirma a entrega de UM item. Nesta
-- função, TUDO abaixo acontece na MESMA transação (qualquer exceção desfaz
-- tudo — inclusive a movimentação criada por `registrar_movimentacao`):
--   movimentação criada -> patrimônio atualizado -> item CONCLUIDO com
--   `movimentacao_id` -> versão do documento +1 -> evento ITEM_CONCLUIDO.
--
-- V1 (decisões aprovadas):
--   * só TRANSFERENCIA; data da movimentação = momento da confirmação (a
--     função passa `p_data_movimentacao => null`; não há data manual);
--   * ADMIN, GESTOR e OPERADOR podem concluir;
--   * `p_versao_esperada` obrigatório (o cliente confirmou o que viu; se o
--     documento mudou entretanto, a conclusão é recusada);
--   * chama `public.registrar_movimentacao` (11 parâmetros, vigente desde
--     20260914140000) internamente — NÃO duplica suas regras e NÃO a altera;
--   * localização/responsável de destino sempre EXPLÍCITOS: em TRANSFERENCIA,
--     `registrar_movimentacao` grava exatamente o que recebe (nulo LIMPA, não
--     preserva) e responsável nulo faz o patrimônio ficar DISPONIVEL. Por isso
--     CONFIRMADO_SEM_INFORMACAO só é aceito quando o cliente confirma a
--     limpeza (`p_confirmar_limpeza_destino`) — se realmente houver algo a
--     limpar;
--   * não há coluna nova em `documentos_sei_eventos`: `movimentacao_id` vai em
--     `dados_depois` do evento e, de forma definitiva, em
--     `documentos_sei_itens.movimentacao_id`.
--
-- ORDEM DE LOCKS: DOCUMENTO -> ITEM -> PATRIMÔNIO -> (dentro de
-- `registrar_movimentacao`: o mesmo patrimônio de novo, que já é nosso;
-- SETOR de destino e LOCALIZAÇÃO com FOR SHARE). Nenhuma outra função trava
-- PATRIMÔNIO antes de DOCUMENTO/ITEM, então não há ciclo possível.
--
-- IDEMPOTÊNCIA: o item é travado depois do documento; se já estiver
-- CONCLUIDO com `movimentacao_id`, a função devolve o estado existente com
-- `ja_concluido = true` SEM escrever nada e SEM checar a versão (é isso que faz
-- o clique duplo / a repetição após timeout devolverem sucesso em vez de
-- conflito de versão). Garantias estruturais que não dependem desta função:
-- `documentos_sei_itens_movimentacao_unica` (índice único) e
-- `documentos_sei_itens_status_coerente` (CONCLUIDO exige movimentacao_id).
--
-- MOVIMENTAÇÃO POSTERIOR (passo 16): bloqueia se existir movimentação do MESMO
-- patrimônio com `criado_em` OU `data_movimentacao` posterior a
-- `documentos_sei_itens.criado_em`. Não é ordenação absoluta por commit
-- PostgreSQL quando uma movimentação é retrodatada manualmente — ver o
-- comentário no passo 16.
--
-- ERROS (SQLSTATE):
--   42501  sem permissão
--   P0001  parâmetro/regra geral (tipo não suportado, item não pertence ao
--          documento, item CANCELADO, destino/decisão pendente, movimentação
--          interna sem localização definida...)
--   P0002  documento / item / patrimônio não encontrado
--   P0010  conflito de versão (mesmo código de editar_documento_sei_pendente)
--   P0030  estado inconsistente do item (CONCLUIDO sem movimentação, com
--          movimentação inexistente ou de OUTRO patrimônio; PENDENTE com
--          movimentação) — exige revisão manual
--   P0031  vínculo do patrimônio incoerente (sem vínculo, ou o número efetivo
--          pertence a outro UUID que o `patrimonio_id` do item)
--   P0032  estado do patrimônio diverge do esperado (origem, status)
--   P0033  patrimônio movimentado DEPOIS da criação do item (criado_em OU
--          data_movimentacao posterior)
--   P0034  já existe movimentação do mesmo patrimônio com o mesmo documento
--   P0035  a conclusão limparia localização/responsável atuais e a limpeza
--          não foi confirmada
--   (erros de `registrar_movimentacao` — data, destino inativo, localização
--    inativa etc. — sobem com o próprio código e desfazem tudo.)
--
-- PERMISSÕES: REVOKE de tudo + GRANT EXECUTE só para `authenticated`, como as
-- demais funções de escrita SEI. NÃO TOCA: registrar_movimentacao,
-- editar/cancelar/criar_documento_sei, tabelas, dados existentes, Despacho 577.
--
-- DEPOIS DE APLICAR (só leitura):
--   select p.prosecdef, p.proconfig, pg_get_function_identity_arguments(p.oid),
--          has_function_privilege('anon', p.oid, 'execute') as anon_executa
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.proname = 'concluir_item_documento_sei';
-- =============================================================================

create or replace function public.concluir_item_documento_sei(
  p_documento_id uuid,
  p_item_id uuid,
  p_versao_esperada integer,
  p_observacao text default null,
  p_confirmar_limpeza_destino boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_documento public.documentos_sei;
  v_item public.documentos_sei_itens;
  v_item_antes jsonb;
  v_patrimonio public.patrimonios;
  v_patrimonio_depois public.patrimonios;
  v_movimentacao public.movimentacoes;
  v_numero_efetivo text;
  v_outro_patrimonio uuid;
  v_numero_documento text;
  v_numero_chamado text;
  v_motivo text;
  v_observacao text := public.normalize_text(p_observacao);
  v_localizacao_destino uuid;
  v_responsavel_destino text;
  v_limpa_localizacao boolean;
  v_limpa_responsavel boolean;
begin
  -- 1. perfil e parâmetros ---------------------------------------------------
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para concluir item de documento SEI'
      using errcode = '42501';
  end if;

  if p_documento_id is null or p_item_id is null or p_versao_esperada is null then
    raise exception 'p_documento_id, p_item_id e p_versao_esperada são obrigatórios'
      using errcode = 'P0001';
  end if;

  -- 2. trava o DOCUMENTO primeiro (mesma ordem de editar/cancelar) ------------
  select * into v_documento
  from public.documentos_sei
  where id = p_documento_id
  for update;

  if not found then
    raise exception 'Documento SEI pendente % não encontrado', p_documento_id
      using errcode = 'P0002';
  end if;

  -- 4/5. trava o ITEM depois do documento; confere que pertence a ele. A
  -- busca já filtra por documento_id: nunca travamos um item de outro
  -- documento enquanto seguramos este.
  select * into v_item
  from public.documentos_sei_itens
  where id = p_item_id and documento_id = p_documento_id
  for update;

  if not found then
    if exists (select 1 from public.documentos_sei_itens where id = p_item_id) then
      raise exception 'Item % não pertence ao documento %', p_item_id, p_documento_id
        using errcode = 'P0001';
    end if;
    raise exception 'Item % não encontrado', p_item_id using errcode = 'P0002';
  end if;

  -- 6. IDEMPOTÊNCIA — item já concluído: devolve o estado existente, sem
  -- escrever nada. Fica ANTES da checagem de versão de propósito: quem repete
  -- a chamada (clique duplo, timeout) ainda envia a versão antiga, e um
  -- conflito de versão esconderia o fato de que a conclusão já aconteceu.
  if v_item.status = 'CONCLUIDO' then
    if v_item.movimentacao_id is null then
      raise exception 'Item % está CONCLUIDO sem movimentação vinculada — estado inconsistente, revisão manual necessária', p_item_id
        using errcode = 'P0030';
    end if;

    select * into v_movimentacao
    from public.movimentacoes
    where id = v_item.movimentacao_id;

    if not found then
      raise exception 'Movimentação % vinculada ao item % não encontrada — estado inconsistente', v_item.movimentacao_id, p_item_id
        using errcode = 'P0030';
    end if;

    -- O retry nunca pode devolver a movimentação de OUTRO patrimônio: ela precisa
    -- ser do patrimônio vinculado ao item (a trigger
    -- `validate_pendencia_movimentacao_patrimonio` já impede gravar o contrário,
    -- mas aqui conferimos de novo antes de expor o resultado).
    if v_item.patrimonio_id is null or v_movimentacao.patrimonio_id is distinct from v_item.patrimonio_id then
      raise exception 'Movimentação % não pertence ao patrimônio vinculado ao item % — estado inconsistente, revisão manual necessária', v_item.movimentacao_id, p_item_id
        using errcode = 'P0030';
    end if;

    return jsonb_build_object(
      'ja_concluido', true,
      'documento', to_jsonb(v_documento),
      'item', to_jsonb(v_item),
      'movimentacao', to_jsonb(v_movimentacao)
    );
  end if;

  -- 7. conclusão NOVA: PENDENTE e sem movimentação ----------------------------
  if v_item.status = 'PENDENTE' and v_item.movimentacao_id is not null then
    raise exception 'Item % está PENDENTE mas já tem movimentação vinculada — estado inconsistente, revisão manual necessária', p_item_id
      using errcode = 'P0030';
  end if;

  if v_item.status <> 'PENDENTE' then
    raise exception 'Item % não está PENDENTE (está %) — não pode ser concluído', p_item_id, v_item.status
      using errcode = 'P0001';
  end if;

  -- 3. versão (só para conclusão nova — ver comentário da idempotência) -------
  if v_documento.versao <> p_versao_esperada then
    raise exception 'Conflito de edição: versão % informada, versão atual % — releia o documento antes de tentar novamente',
      p_versao_esperada, v_documento.versao
      using errcode = 'P0010';
  end if;

  -- 8. V1: somente TRANSFERENCIA ----------------------------------------------
  if v_documento.tipo_operacao_pretendida <> 'TRANSFERENCIA' then
    raise exception 'A conclusão de entrega só suporta TRANSFERENCIA nesta versão (documento é %)', v_documento.tipo_operacao_pretendida
      using errcode = 'P0001';
  end if;

  -- 9/10. destino e decisões explícitas (PENDENTE nunca vira null sozinho) ----
  if v_item.destino_setor_id is null then
    raise exception 'Item % não tem setor de destino resolvido', p_item_id
      using errcode = 'P0001';
  end if;
  if v_item.decisao_localizacao = 'PENDENTE' then
    raise exception 'Item %: a decisão sobre a localização de destino ainda está PENDENTE', p_item_id
      using errcode = 'P0001';
  end if;
  if v_item.decisao_responsavel = 'PENDENTE' then
    raise exception 'Item %: a decisão sobre o responsável de destino ainda está PENDENTE', p_item_id
      using errcode = 'P0001';
  end if;

  -- 11. número efetivo, normalizado como `patrimonios.numero_patrimonio`
  -- (`upper(normalize_text(...))`, ver CHECK patrimonios_numero_patrimonio_normalizado).
  v_numero_efetivo := upper(public.normalize_text(
    coalesce(v_item.numero_patrimonio_corrigido, v_item.numero_patrimonio_original)
  ));
  if v_numero_efetivo is null then
    raise exception 'Item % não tem número de patrimônio', p_item_id
      using errcode = 'P0031';
  end if;
  if v_item.patrimonio_id is null then
    raise exception 'Item % não está vinculado a um patrimônio — corrija o número do patrimônio pela edição do documento', p_item_id
      using errcode = 'P0031';
  end if;

  -- 12/13. trava o PATRIMÔNIO vinculado e exige que o número efetivo do item
  -- ainda seja o dele. Travar pelo `patrimonio_id` (e não pelo número) evita
  -- segurar a linha de um patrimônio que nada tem a ver com o item; como
  -- `numero_patrimonio` é ÚNICO, "número efetivo = número deste patrimônio"
  -- equivale a "o UUID encontrado pelo número é o `patrimonio_id`". O número
  -- também pode ter sido editado no patrimônio depois da importação
  -- (`authenticated` tem UPDATE em numero_patrimonio) — daí reconferir aqui,
  -- já sob lock.
  select * into v_patrimonio
  from public.patrimonios
  where id = v_item.patrimonio_id
  for update;

  if not found then
    raise exception 'Patrimônio % não encontrado', v_item.patrimonio_id
      using errcode = 'P0002';
  end if;

  if v_patrimonio.numero_patrimonio is distinct from v_numero_efetivo then
    select id into v_outro_patrimonio
    from public.patrimonios
    where numero_patrimonio = v_numero_efetivo;

    if v_outro_patrimonio is null then
      raise exception 'Patrimônio % não encontrado no InvTec — o patrimônio vinculado ao item agora tem outro número', v_numero_efetivo
        using errcode = 'P0002';
    end if;

    raise exception 'Vínculo incoerente: o número efetivo do item (%) pertence a outro patrimônio que o vinculado (%) — revalide o item pela edição do documento', v_numero_efetivo, v_item.patrimonio_id
      using errcode = 'P0031';
  end if;

  -- 14/15. estado ATUAL do patrimônio contra o que o documento esperava ------
  if v_item.origem_setor_id is null then
    raise exception 'Item % não tem origem resolvida — não é possível confirmar o estado do patrimônio', p_item_id
      using errcode = 'P0032';
  end if;
  if v_patrimonio.setor_atual_id <> v_item.origem_setor_id then
    raise exception 'Origem divergente: o setor atual do patrimônio % não é o setor de origem do item — revisão humana necessária', v_numero_efetivo
      using errcode = 'P0032';
  end if;
  if v_patrimonio.status not in ('DISPONIVEL', 'EM_USO') then
    raise exception 'Patrimônio % está % — não pode ser transferido', v_numero_efetivo, v_patrimonio.status
      using errcode = 'P0032';
  end if;

  -- 16. QUALQUER movimentação posterior à criação do item bloqueia — basta UMA
  -- das duas condições:
  --   * `m.criado_em > item.criado_em`: registro criado depois. `criado_em` é
  --     `now()`, o INÍCIO da transação de quem registrou;
  --   * `m.data_movimentacao > item.criado_em`: horário efetivo depois.
  --     `registrar_movimentacao` grava `clock_timestamp()` (o momento da
  --     execução, mais tarde que o início da transação), então isto fecha a
  --     janela de uma movimentação cuja transação COMEÇOU antes do item mas
  --     executou depois dele.
  -- LIMITE CONHECIDO: isto NÃO é uma ordenação absoluta por commit do
  -- PostgreSQL. Uma movimentação RETRODATADA manualmente (data informada antes
  -- da criação do item) cuja transação também começou antes do item, mas só foi
  -- commitada depois, escapa das duas condições; nesse caso a defesa restante é
  -- a validação do estado atual abaixo/acima (setor atual = origem do item,
  -- status compatível, vínculo UUID/número coerente), que continua obrigatória.
  -- Como o patrimônio está travado, nenhuma outra movimentação surge entre esta
  -- leitura e o fim da função.
  if exists (
    select 1
    from public.movimentacoes m
    where m.patrimonio_id = v_patrimonio.id
      and (
        m.criado_em > v_item.criado_em
        or m.data_movimentacao > v_item.criado_em
      )
  ) then
    raise exception 'O patrimônio % foi movimentado depois da criação desta pendência — revisão humana necessária', v_numero_efetivo
      using errcode = 'P0033';
  end if;

  -- 17. movimentação prévia do mesmo patrimônio com o mesmo documento SEI ----
  v_numero_documento := coalesce(
    public.normalize_text(v_documento.numero_documento_sei),
    public.normalize_text(v_documento.numero_documento_formatado)
  );
  if v_numero_documento is not null and exists (
    select 1
    from public.movimentacoes m
    where m.patrimonio_id = v_patrimonio.id
      and public.normalize_text(m.numero_documento) = v_numero_documento
  ) then
    raise exception 'Já existe movimentação do patrimônio % com o documento % — revisão humana necessária', v_numero_efetivo, v_numero_documento
      using errcode = 'P0034';
  end if;

  -- 18. parâmetros EXPLÍCITOS de localização e responsável ---------------------
  -- Em TRANSFERENCIA, `registrar_movimentacao` grava exatamente o que recebe:
  -- localização nula LIMPA a atual; responsável nulo LIMPA o atual e o status
  -- passa a DISPONIVEL. Nunca deixamos isso acontecer por acidente: DEFINIDO
  -- envia o valor; CONFIRMADO_SEM_INFORMACAO envia null DE PROPÓSITO.
  if v_item.decisao_localizacao = 'DEFINIDO' then
    v_localizacao_destino := v_item.localizacao_destino_id;
  else
    v_localizacao_destino := null;
  end if;

  if v_item.decisao_responsavel = 'DEFINIDO' then
    v_responsavel_destino := v_item.responsavel_destino;
  else
    v_responsavel_destino := null;
  end if;

  -- Movimentação interna (mesmo setor): `registrar_movimentacao` exige uma
  -- localização de destino diferente da atual — logo CONFIRMADO_SEM_INFORMACAO
  -- para a localização não é aceito aqui (mensagem clara em vez do erro dela).
  if v_item.destino_setor_id = v_patrimonio.setor_atual_id then
    if v_item.decisao_localizacao <> 'DEFINIDO' or v_localizacao_destino is null then
      raise exception 'Movimentação interna (mesmo setor) exige localização de destino DEFINIDA — CONFIRMADO_SEM_INFORMACAO não é aceito'
        using errcode = 'P0001';
    end if;
    if v_localizacao_destino is not distinct from v_patrimonio.localizacao_atual_id then
      raise exception 'A localização de destino precisa ser diferente da localização atual do patrimônio'
        using errcode = 'P0001';
    end if;
  end if;

  -- 19. limpeza destrutiva exige confirmação explícita ------------------------
  v_limpa_localizacao := v_localizacao_destino is null and v_patrimonio.localizacao_atual_id is not null;
  v_limpa_responsavel := v_responsavel_destino is null and v_patrimonio.responsavel_atual is not null;

  if (v_limpa_localizacao or v_limpa_responsavel) and p_confirmar_limpeza_destino is not true then
    raise exception 'A conclusão limparia % — confirme explicitamente a limpeza (p_confirmar_limpeza_destino) para prosseguir',
      concat_ws(' e ',
        case when v_limpa_localizacao then 'a localização atual' end,
        case when v_limpa_responsavel then 'o responsável atual (o patrimônio ficará DISPONIVEL)' end
      )
      using errcode = 'P0035';
  end if;

  v_numero_chamado := coalesce(v_item.numero_chamado_corrigido, v_item.numero_chamado_original);
  v_motivo := case
    when public.normalize_text(v_documento.numero_documento_formatado) is not null
      then 'Despacho SEI ' || public.normalize_text(v_documento.numero_documento_formatado)
    when v_numero_documento is not null
      then 'Despacho SEI ' || v_numero_documento
    else null
  end;

  v_item_antes := to_jsonb(v_item);

  -- 20. registra a movimentação (mesma transação; se falhar, NADA foi escrito
  -- antes e nada fica depois — não há bloco EXCEPTION que engula o erro).
  select * into v_movimentacao
  from public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio.id,
    p_tipo => 'TRANSFERENCIA',
    p_destino_id => v_item.destino_setor_id,
    p_responsavel_destino => v_responsavel_destino,
    p_motivo => v_motivo,
    p_observacao => v_observacao,
    p_numero_documento => v_numero_documento,
    p_numero_chamado => v_numero_chamado,
    p_data_movimentacao => null,
    p_localizacao_destino_id => v_localizacao_destino,
    p_limpar_localizacao => false
  );

  -- 21. item CONCLUIDO + movimentacao_id. O check `status_coerente` e a
  -- trigger `validate_pendencia_movimentacao_patrimonio` conferem, no banco,
  -- que a movimentação pertence ao patrimônio do item.
  update public.documentos_sei_itens
  set status = 'CONCLUIDO',
      movimentacao_id = v_movimentacao.id
  where id = v_item.id
  returning * into v_item;

  -- 22. versão do documento
  update public.documentos_sei
  set versao = versao + 1,
      atualizado_em = now()
  where id = p_documento_id
  returning * into v_documento;

  select * into v_patrimonio_depois
  from public.patrimonios
  where id = v_patrimonio.id;

  -- 23. auditoria: quem, quando (criado_em), qual movimentação e o resultado
  -- patrimonial. `movimentacao_id` também fica em documentos_sei_itens.
  insert into public.documentos_sei_eventos (documento_id, item_id, tipo, descricao, dados_antes, dados_depois, autor_id)
  values (
    p_documento_id,
    v_item.id,
    'ITEM_CONCLUIDO',
    format('Entrega concluída: patrimônio %s transferido (movimentação %s)%s',
      v_numero_efetivo, v_movimentacao.id,
      case when v_observacao is not null then ' — ' || v_observacao else '' end),
    jsonb_build_object(
      'item', v_item_antes,
      'patrimonio', jsonb_build_object(
        'setor_atual_id', v_patrimonio.setor_atual_id,
        'localizacao_atual_id', v_patrimonio.localizacao_atual_id,
        'responsavel_atual', v_patrimonio.responsavel_atual,
        'status', v_patrimonio.status
      )
    ),
    jsonb_build_object(
      'movimentacao_id', v_movimentacao.id,
      'numero_patrimonio_efetivo', v_numero_efetivo,
      'limpeza_confirmada', (v_limpa_localizacao or v_limpa_responsavel),
      'item', jsonb_build_object(
        'status', v_item.status,
        'movimentacao_id', v_item.movimentacao_id
      ),
      'movimentacao', jsonb_build_object(
        'tipo', v_movimentacao.tipo,
        'origem_id', v_movimentacao.origem_id,
        'destino_id', v_movimentacao.destino_id,
        'localizacao_origem_id', v_movimentacao.localizacao_origem_id,
        'localizacao_destino_id', v_movimentacao.localizacao_destino_id,
        'responsavel_origem', v_movimentacao.responsavel_origem,
        'responsavel_destino', v_movimentacao.responsavel_destino,
        'data_movimentacao', v_movimentacao.data_movimentacao
      ),
      'patrimonio', jsonb_build_object(
        'setor_atual_id', v_patrimonio_depois.setor_atual_id,
        'localizacao_atual_id', v_patrimonio_depois.localizacao_atual_id,
        'responsavel_atual', v_patrimonio_depois.responsavel_atual,
        'status', v_patrimonio_depois.status
      )
    ),
    auth.uid()
  );

  -- 24. resultado
  return jsonb_build_object(
    'ja_concluido', false,
    'documento', to_jsonb(v_documento),
    'item', to_jsonb(v_item),
    'movimentacao', to_jsonb(v_movimentacao)
  );
end;
$$;

revoke all on function public.concluir_item_documento_sei from public, anon, authenticated;
grant execute on function public.concluir_item_documento_sei to authenticated;
