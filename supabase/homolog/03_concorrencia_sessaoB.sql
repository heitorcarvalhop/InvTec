-- =============================================================================
-- PROMPT 11.3.4, seção 6 — SESSÃO B (parceira de
-- `03_concorrencia_sessaoA.sql` — leia o cabeçalho daquele arquivo
-- primeiro; os dois precisam estar abertos em abas/conexões SEPARADAS ao
-- mesmo tempo, contra o projeto de HOMOLOGAÇÃO).
--
-- Cada bloco abaixo só deve ser rodado QUANDO a sessão A instruir (durante
-- o `pg_sleep` dela). O comportamento esperado, em TODOS os 5 cenários: a
-- consulta abaixo fica "pendurada" (sem retornar nada, cursor de
-- carregamento ativo) até a sessão A commitar — SÓ ENTÃO ela retorna
-- (com sucesso ou com o erro esperado, indicado em cada cenário). Se
-- retornar IMEDIATAMENTE, a trava não funcionou — reporte como falha. Se
-- qualquer uma das duas sessões travar com "deadlock detected", também é
-- falha real (a ordem de locks documento->item deveria evitar isso).
-- =============================================================================

select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;

-- =============================================================================
-- PASSO B1 — rodar DURANTE o pg_sleep de A1 (mesmo SEI, sem processo)
-- =============================================================================
select clock_timestamp() as inicio_B1;
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA',
  p_nome_arquivo := 'zz_conc1_B.pdf',
  p_hash_sha256 := 'zz-conc1-b',
  p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'))),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-1'
);
select clock_timestamp() as fim_B1;
-- ESPERADO: este SELECT some por ~15s (até A commitar), depois lança
-- ERROR P0020 (documento duplicado ativo). Se retornou rápido demais (sem
-- esperar) OU se criou um segundo documento sem erro, é FALHA.

-- =============================================================================
-- PASSO B2 — rodar DURANTE o pg_sleep de A2 (mesmo SEI de A2, AGORA com
-- processo informado — o par assimétrico da seção 3 do PROMPT 11.3.3)
-- =============================================================================
select clock_timestamp() as inicio_B2;
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA',
  p_nome_arquivo := 'zz_conc2_B.pdf',
  p_hash_sha256 := 'zz-conc2-b',
  p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'))),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-2',
  p_numero_processo := 'ZZHOMOLOG-PROC-CONC-2'
);
select clock_timestamp() as fim_B2;
-- ESPERADO: também some por ~15s e falha com P0020, mesmo com processo
-- diferente do lado de A. Se retornar rápido (chave de trava não cobrindo
-- este par) ou não falhar, é exatamente o bug que o PROMPT 11.3.3 corrigiu
-- voltando a acontecer.

-- =============================================================================
-- PASSO B3 — rodar DURANTE o pg_sleep de A3b (mesma versão lida: 1)
-- =============================================================================
select clock_timestamp() as inicio_B3;
select public.editar_documento_sei_pendente(
  p_documento_id := (select id from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-CONC-3'),
  p_versao_esperada := 1,
  p_motivo := 'ZZ_HOMOLOG edição concorrente — sessão B'
);
select clock_timestamp() as fim_B3;
-- ESPERADO: some por ~15s (travado pelo `for update` de A no documento),
-- depois falha com P0010 (versão desatualizada: A já a levou para 2).

-- =============================================================================
-- PASSO B4 — rodar DURANTE o pg_sleep de A4b (cancelar o item de linha 2
-- anotado no PASSO A4a)
-- =============================================================================
select clock_timestamp() as inicio_B4;
select public.cancelar_item_sei_pendente(
  p_item_id := (
    select i.id from public.documentos_sei_itens i
    join public.documentos_sei d on d.id = i.documento_id
    where d.numero_documento_sei = 'ZZHOMOLOG-CONC-4' and i.linha = 2
  ),
  p_motivo := 'ZZ_HOMOLOG cancelamento concorrente com edição — sessão B'
);
select clock_timestamp() as fim_B4;
-- ESPERADO: some por ~15s (travado pelo documento, que A já travou
-- primeiro em editar_documento_sei_pendente), depois SUCEDE normalmente
-- (o item fica CANCELADO) — a edição de A não impede cancelar um item
-- distinto. NENHUMA das duas sessões deve travar com deadlock.

-- =============================================================================
-- PASSO B5 — rodar DURANTE o pg_sleep de A5b (cancelar o item de linha 1
-- anotado no PASSO A5a, individualmente)
-- =============================================================================
select clock_timestamp() as inicio_B5;
select public.cancelar_item_sei_pendente(
  p_item_id := (
    select i.id from public.documentos_sei_itens i
    join public.documentos_sei d on d.id = i.documento_id
    where d.numero_documento_sei = 'ZZHOMOLOG-CONC-5' and i.linha = 1
  ),
  p_motivo := 'ZZ_HOMOLOG cancelamento individual concorrente com cancelamento total — sessão B'
);
select clock_timestamp() as fim_B5;
-- ESPERADO: some por ~15s, depois FALHA (o item já foi cancelado por A ao
-- cancelar todos os pendentes — "não está PENDENTE").

reset role;
select 'FIM DA SESSÃO B — confira cada "fim_BN" contra o "resultado_esperado" impresso na sessão A' as fim;
