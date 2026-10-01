-- =============================================================================
-- public.concluir_itens_documento_sei_lote
-- Concluir a ENTREGA de VÁRIOS itens de um mesmo Documento SEI, de forma
-- atômica (tudo ou nada), reaproveitando `concluir_item_documento_sei` sem
-- alterá-la.
-- =============================================================================
-- Um único `documento_id` por chamada: trava o documento e os N itens,
-- valida o CONJUNTO inteiro e só então chama `concluir_item_documento_sei`
-- uma vez por item, dentro da MESMA transação. Uma exceção em qualquer item
-- desfaz TUDO: itens já concluídos por chamadas anteriores do mesmo laço, o
-- registro do lote (só inserido no fim) e a versão do documento.
--
-- A versão do documento avança uma vez POR ITEM concluído (não uma vez para
-- o lote inteiro) — a função de lote só encadeia o valor devolvido de uma
-- chamada para a próxima.
--
-- Idempotência real (não "todos concluídos = sucesso", que aceitaria itens
-- concluídos por OUTRAS operações como se fossem deste lote): `p_lote_id` é
-- gerado pelo cliente e registrado em `documentos_sei_lotes_conclusao` só
-- depois que TODOS os itens concluíram. Um retry com o MESMO `lote_id` E os
-- MESMOS parâmetros devolve o resultado já registrado, sem travar ou
-- escrever nada; com parâmetro diferente é recusado (P0037).
--
-- ORDEM DE LOCKS: advisory lock por `lote_id` (serializa chamadas
-- concorrentes com o MESMO `lote_id`, mesmo entre documentos diferentes) ->
-- DOCUMENTO -> ITENS (ordenados por `id`) -> dentro de cada chamada a
-- `concluir_item_documento_sei`: PATRIMÔNIO (itera por `patrimonio_id`
-- resolvido, não pela ordem recebida, para que os locks de patrimônio
-- saiam sempre na mesma ordem relativa entre execuções concorrentes).
--
-- ERROS (SQLSTATE) NOVOS DESTA FUNÇÃO:
--   P0036  um ou mais itens do lote não estão PENDENTE
--   P0037  o mesmo p_lote_id já foi usado com parâmetros diferentes
-- (os demais códigos são os de `concluir_item_documento_sei`, propagados
-- sem alteração.)
-- =============================================================================

-- =============================================================================
-- 1. TABELA DE CONTROLE — public.documentos_sei_lotes_conclusao
-- =============================================================================
-- Uma linha por lote CONCLUÍDO COM SUCESSO (nunca por tentativa: o INSERT só
-- acontece depois que todos os itens foram concluídos). Guarda os
-- parâmetros ORIGINAIS da chamada, não só o resultado, porque a identidade
-- real da operação exige comparar TODOS eles num retry, não só
-- `lote_id`+documento+itens.
create table public.documentos_sei_lotes_conclusao (
  -- gerado pelo cliente (Flutter), uma vez por decisão confirmada — nunca
  -- pelo banco (`gen_random_uuid()` aqui produziria uma chave nova a cada
  -- chamada, inútil para detectar retry).
  lote_id uuid primary key,
  documento_id uuid not null references public.documentos_sei (id) on delete restrict,
  -- conjunto CANÔNICO (distinto, ordenado) — a função nunca insere um
  -- array fora dessa forma; não há CHECK para isso porque um CHECK não
  -- pode conter subconsulta (`unnest`) — a garantia é por só existir UM
  -- caminho de escrita nesta tabela (a função abaixo).
  item_ids uuid[] not null,
  versao_esperada integer not null,
  observacao text,
  confirmar_limpeza_destino boolean not null,
  criado_por uuid not null references public.profiles (id) on delete restrict,
  criado_em timestamptz not null default now(),
  -- o MESMO jsonb devolvido ao cliente na primeira execução — reaproveitado
  -- verbatim (mais um `ja_executado: true`) num retry idêntico; nunca é
  -- reescrito depois de inserido (append-only, mesma filosofia de
  -- `documentos_sei_eventos`).
  resultado jsonb not null,
  constraint documentos_sei_lotes_conclusao_item_ids_nao_vazio check (cardinality(item_ids) > 0)
);

create index documentos_sei_lotes_conclusao_documento_idx
  on public.documentos_sei_lotes_conclusao (documento_id);

alter table public.documentos_sei_lotes_conclusao enable row level security;

-- Mesmo público de leitura das outras tabelas SEI (seção 9 da migration
-- 20260921170000). Sem policy de INSERT/UPDATE/DELETE: só a função
-- SECURITY DEFINER escreve (roda como dono do banco, não sujeita a RLS).
create policy documentos_sei_lotes_conclusao_select on public.documentos_sei_lotes_conclusao
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

revoke all on table public.documentos_sei_lotes_conclusao from public, anon, authenticated;
grant select on public.documentos_sei_lotes_conclusao to authenticated;

-- =============================================================================
-- 2. RPC: public.concluir_itens_documento_sei_lote
-- =============================================================================
create or replace function public.concluir_itens_documento_sei_lote(
  p_documento_id uuid,
  p_item_ids uuid[],
  p_versao_esperada integer,
  p_lote_id uuid,
  p_observacao text default null,
  p_confirmar_limpeza_destino boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limite_itens constant integer := 200;
  -- MESMA normalização que `concluir_item_documento_sei`
  -- já aplica internamente (`v_observacao text := public.normalize_text(
  -- p_observacao);`, repassada a `registrar_movimentacao`): aparar
  -- espaço/tab/CR/LF nas pontas e transformar "" em `null`. `normalize_text`
  -- é `strict`, então `null` continua `null`. É este valor NORMALIZADO —
  -- nunca o texto cru de `p_observacao` — que fica gravado em
  -- `documentos_sei_lotes_conclusao.observacao` e que entra na comparação
  -- de retry (`is not distinct from`, mais abaixo): duas chamadas cujo
  -- texto bruto difere só em espaço nas pontas, ou "" vs. omitido, contam
  -- como a MESMA observação para fins de idempotência.
  v_observacao text := public.normalize_text(p_observacao);
  v_item_ids uuid[];
  v_lote public.documentos_sei_lotes_conclusao;
  v_documento public.documentos_sei;
  v_qtd_encontrados integer;
  v_qtd_nao_pendente integer;
  v_itens_nao_pendente text;
  v_item_id uuid;
  v_resultado_item jsonb;
  v_itens_resultado jsonb := '[]'::jsonb;
  v_versao_atual integer;
  v_resultado jsonb;
begin
  -- 1. perfil e parâmetros -----------------------------------------------
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para concluir itens de documento SEI em lote'
      using errcode = '42501';
  end if;

  if p_documento_id is null or p_item_ids is null or p_versao_esperada is null or p_lote_id is null then
    raise exception 'p_documento_id, p_item_ids, p_versao_esperada e p_lote_id são obrigatórios'
      using errcode = 'P0001';
  end if;

  -- `p_confirmar_limpeza_destino` tem default `false`,
  -- mas um cliente pode enviar `null` explicitamente (ex.: JSON `null`),
  -- que sobrescreve o default. `null` é ambíguo (nem confirma nem nega a
  -- limpeza) e, sem esta checagem, só seria percebido tarde: na comparação
  -- de retry (a coluna é NOT NULL — nunca igual a `null` — gerando um
  -- P0037 confuso em vez de um erro claro) ou no INSERT final (violação de
  -- NOT NULL, depois de já ter concluído itens de verdade). Rejeitado
  -- aqui, antes de qualquer trabalho.
  if p_confirmar_limpeza_destino is null then
    raise exception 'p_confirmar_limpeza_destino não pode ser nulo (use true ou false)'
      using errcode = 'P0001';
  end if;

  if cardinality(p_item_ids) = 0 then
    raise exception 'p_item_ids não pode ser vazio' using errcode = 'P0001';
  end if;

  if cardinality(p_item_ids) > v_limite_itens then
    raise exception 'O lote excede o limite de % itens (recebeu %)', v_limite_itens, cardinality(p_item_ids)
      using errcode = 'P0001';
  end if;

  if exists (select 1 from unnest(p_item_ids) as x(id) where x.id is null) then
    raise exception 'p_item_ids não pode conter um elemento nulo' using errcode = 'P0001';
  end if;

  -- 2. canonicaliza (distinto + ordenado) e recusa duplicata explícita -----
  -- nunca deduplica silenciosamente: um array com item repetido é rejeitado
  -- (P0001), não corrigido nos bastidores.
  select array_agg(x.id order by x.id) into v_item_ids from unnest(p_item_ids) as x(id);
  if cardinality(v_item_ids) <> (select count(distinct x.id) from unnest(p_item_ids) as x(id)) then
    raise exception 'p_item_ids não pode conter o mesmo item repetido' using errcode = 'P0001';
  end if;

  -- 3. serializa qualquer outra chamada concorrente com o MESMO lote_id,
  -- mesmo que aponte para outro documento — antes de tomar qualquer lock
  -- de linha, para nunca duas transações processarem o mesmo lote_id ao
  -- mesmo tempo (mesmo padrão de `criar_documento_sei_pendente`, seção 6
  -- da migration 20260921170000).
  perform pg_advisory_xact_lock(hashtextextended('lote_sei:' || p_lote_id::text, 0));

  -- 4/5/6. já existe um registro para este lote_id? -------------------------
  select * into v_lote from public.documentos_sei_lotes_conclusao where lote_id = p_lote_id;

  if found then
    if v_lote.documento_id = p_documento_id
       and v_lote.item_ids = v_item_ids
       and v_lote.versao_esperada = p_versao_esperada
       and v_lote.observacao is not distinct from v_observacao
       and v_lote.confirmar_limpeza_destino = p_confirmar_limpeza_destino
       and v_lote.criado_por = auth.uid()
    then
      -- RETRY IDÊNTICO: devolve o resultado já registrado. Nenhum lock em
      -- documento/item/patrimônio, nenhuma escrita, nenhuma movimentação
      -- nova, nenhum evento novo.
      return v_lote.resultado || jsonb_build_object('ja_executado', true);
    end if;

    raise exception
      'lote_id % já foi usado para uma operação com parâmetros diferentes '
      '(documento, itens, versão esperada, observação, confirmação de limpeza ou usuário)',
      p_lote_id
      using errcode = 'P0037';
  end if;

  -- 7. trava DOCUMENTO -> ITENS, nessa ordem --------------------------------
  select * into v_documento from public.documentos_sei where id = p_documento_id for update;
  if not found then
    raise exception 'Documento SEI pendente % não encontrado', p_documento_id using errcode = 'P0002';
  end if;

  -- trava os N itens em ordem determinística (por id) — `FOR UPDATE` com
  -- `ORDER BY` trava as linhas na ordem em que são lidas do nó de
  -- ordenação, então a ordem de travamento é sempre a mesma entre chamadas
  -- concorrentes que compartilhem algum item.
  perform 1
  from public.documentos_sei_itens
  where id = any (v_item_ids) and documento_id = p_documento_id
  order by id
  for update;

  select count(*) into v_qtd_encontrados
  from public.documentos_sei_itens
  where id = any (v_item_ids) and documento_id = p_documento_id;

  if v_qtd_encontrados <> cardinality(v_item_ids) then
    raise exception 'Um ou mais itens do lote não existem ou não pertencem ao documento %', p_documento_id
      using errcode = 'P0002';
  end if;

  -- 8. consistência do conjunto ANTES de concluir qualquer item ------------
  -- como o passo 4/5/6 já garantiu que isto não é um retry bem-sucedido
  -- deste lote_id, qualquer item que não esteja PENDENTE aqui só pode ser
  -- interferência de outra operação (conclusão individual, outro lote,
  -- cancelamento) — o lote inteiro é recusado, nunca conclui só o restante.
  select count(*) into v_qtd_nao_pendente
  from public.documentos_sei_itens
  where id = any (v_item_ids) and status <> 'PENDENTE';

  if v_qtd_nao_pendente > 0 then
    select string_agg(format('%s (%s)', id, status), ', ' order by id) into v_itens_nao_pendente
    from public.documentos_sei_itens
    where id = any (v_item_ids) and status <> 'PENDENTE';
    raise exception 'Um ou mais itens do lote não estão PENDENTE: %', v_itens_nao_pendente
      using errcode = 'P0036';
  end if;

  -- 9. mesmo patrimônio não pode aparecer duas vezes no lote ---------------
  if exists (
    select 1
    from public.documentos_sei_itens
    where id = any (v_item_ids) and patrimonio_id is not null
    group by patrimonio_id
    having count(*) > 1
  ) then
    raise exception 'Dois ou mais itens deste lote apontam para o mesmo patrimônio'
      using errcode = 'P0001';
  end if;

  -- 10. versão inicial do documento -----------------------------------------
  if v_documento.versao <> p_versao_esperada then
    raise exception 'Conflito de edição: versão % informada, versão atual % — releia o documento antes de tentar novamente',
      p_versao_esperada, v_documento.versao
      using errcode = 'P0010';
  end if;

  -- 11. chama a RPC individual, uma vez por item, encadeando a versão -------
  -- NENHUMA regra de negócio é duplicada aqui: cada chamada roda o corpo
  -- inteiro (já homologado) de `concluir_item_documento_sei` — travas de
  -- patrimônio, validações P0030-P0035, `registrar_movimentacao`, o
  -- UPDATE do item e o INSERT do evento ITEM_CONCLUIDO. Itera pelo
  -- `patrimonio_id` resolvido (não pela ordem recebida do cliente) para
  -- que os locks de patrimônio saiam sempre na mesma ordem relativa entre
  -- execuções concorrentes.
  v_versao_atual := p_versao_esperada;

  for v_item_id in
    select i.id
    from public.documentos_sei_itens i
    where i.id = any (v_item_ids)
    order by i.patrimonio_id, i.id
  loop
    select public.concluir_item_documento_sei(
      p_documento_id,
      v_item_id,
      v_versao_atual,
      p_observacao,
      p_confirmar_limpeza_destino
    ) into v_resultado_item;

    v_versao_atual := (v_resultado_item -> 'documento' ->> 'versao')::int;
    v_itens_resultado := v_itens_resultado || jsonb_build_object('item_id', v_item_id, 'resultado', v_resultado_item);
  end loop;

  -- 12. registra o lote — só chega aqui se TODOS os itens concluíram ---------
  -- (qualquer exceção dentro do laço aborta a transação inteira e este
  -- INSERT nunca roda: nenhum registro de tentativa fracassada sobra).
  select * into v_documento from public.documentos_sei where id = p_documento_id;

  v_resultado := jsonb_build_object(
    'ja_executado', false,
    'documento', to_jsonb(v_documento),
    'itens', v_itens_resultado
  );

  insert into public.documentos_sei_lotes_conclusao (
    lote_id, documento_id, item_ids, versao_esperada, observacao, confirmar_limpeza_destino, criado_por, resultado
  ) values (
    p_lote_id, p_documento_id, v_item_ids, p_versao_esperada, v_observacao, p_confirmar_limpeza_destino, auth.uid(), v_resultado
  );

  -- 13. retorno agregado -----------------------------------------------------
  return v_resultado;
end;
$$;

revoke all on function public.concluir_itens_documento_sei_lote from public, anon, authenticated;
grant execute on function public.concluir_itens_documento_sei_lote to authenticated;
