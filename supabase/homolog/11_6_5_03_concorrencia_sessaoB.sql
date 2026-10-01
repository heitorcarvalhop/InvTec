-- =============================================================================
-- PROMPT 11.6.5, seção 2D/2E — SESSÃO B. A parceira é
-- `11_6_5_03_concorrencia_sessaoA.sql` (SESSÃO A) — leia o cabeçalho dela
-- primeiro. NUNCA rode um bloco daqui antes da instrução correspondente em
-- A ter mandado.
-- =============================================================================

-- =============================================================================
-- CENÁRIO 1 (seção 2D) — PASSO B1: rode isto ENQUANTO o pg_sleep(15) de A1
-- ainda está rodando (você tem ~15s depois de colar o PASSO A1).
-- =============================================================================
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;

select clock_timestamp() as inicio_B1;
-- MESMO operacao_id de A1, parâmetros IDÊNTICOS — se a trava estiver
-- funcionando, esta chamada FICA PARADA (sem retornar) até A1 commitar. Se
-- retornar IMEDIATAMENTE, a trava NÃO está funcionando — reporte como
-- falha. Depois que A1 commitar, esperado: devolve o MESMO resultado
-- ("ja_executado": true), SEM erro de chave duplicada, SEM nova
-- movimentação/UPDATE.
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '66666666-6666-4666-8666-600000000001',
  p_lote_id := '66666666-6666-4666-8666-600000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_observacao := 'ZZ_HOMOLOG 11.6.5 — 2D sessão A' -- MESMO texto de A (parâmetros idênticos)
);
select clock_timestamp() as fim_B1;
select 'B1: esperado ficar parada ~15s, depois devolver ja_executado=true' as resultado_esperado;

-- Verificação: só 1 linha para este operacao_id (nunca duplicada por A+B).
select count(*) as deve_ser_1 from public.patrimonio_comparacao_execucoes
where operacao_id = '66666666-6666-4666-8666-600000000001';

reset role;


-- =============================================================================
-- CENÁRIO 2 (seção 2E) — PASSO B2: rode isto ENQUANTO o pg_sleep(15) de A2b
-- ainda está rodando. Use o MESMO valor de `versao_compartilhada` anotado
-- no PASSO A2a (cole no lugar do literal abaixo) — um operacao_id
-- DIFERENTE do de A.
-- =============================================================================
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;

select clock_timestamp() as inicio_B2;
-- Esperado: fica PARADA até A2b commitar (trava `for update` da linha do
-- patrimônio, não da trava advisory — operacao_id é diferente do de A) e
-- ENTÃO falha com P0040 (a versão mudou por causa de A) — NUNCA aplica por
-- cima do que A gravou.
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '77777777-7777-4777-8777-700000000002',
  p_lote_id := '77777777-7777-4777-8777-700000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := '2000-01-01T00:00:00Z', -- <<< COLE aqui o MESMO versao_compartilhada de A2a
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 2E sessão B (NUNCA deveria aplicar)'
);
select clock_timestamp() as fim_B2;
select 'B2: esperado ficar parada, depois falhar com P0040' as resultado_esperado;

-- Verificação FORA de qualquer transação aberta por este script — confirme
-- que a descrição final é a de A ("2E sessão A (deve vencer)"), nunca a de
-- B.
select descricao from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
select 'esperado: descrição de A, NUNCA "2E sessão B (NUNCA deveria aplicar)"' as resultado_esperado;

reset role;

-- =============================================================================
-- LIMPEZA DESTE PAR DE SCRIPTS — as duas chamadas acima COMMITARAM de
-- verdade (não há rollback aqui — testar concorrência real com `pg_sleep`
-- exige transações completas, não savepoints). Rode
-- `99_limpeza_homologacao.sql` depois de terminar os dois cenários para
-- voltar ZZHOMOLOG-000001/ZZHOMOLOG-11.6.5-01 ao estado das fixtures (ou
-- rode `11_6_5_01_fixtures_adicionais.sql`/`01_fixtures_homologacao.sql`
-- de novo, que são idempotentes só para o que falta).
-- =============================================================================
