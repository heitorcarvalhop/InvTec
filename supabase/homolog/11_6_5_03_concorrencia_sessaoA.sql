-- =============================================================================
-- PROMPT 11.6.5, seção 2D/2E — TESTES DE CONCORRÊNCIA REAL (duas conexões
-- independentes) de `public.aplicar_decisao_comparacao_patrimonio`. Uma
-- sequência de chamadas na MESMA conexão (script 02) NUNCA prova ausência
-- de corrida — por isso estes testes exigem DUAS ABAS separadas do SQL
-- Editor (ou duas conexões `psql`) abertas ao MESMO TEMPO contra o projeto
-- de HOMOLOGAÇÃO.
--
-- Esta é a SESSÃO A. A parceira é `11_6_5_03_concorrencia_sessaoB.sql`
-- (SESSÃO B) — abra as duas abas ANTES de começar. Rode um CENÁRIO de cada
-- vez (não pule à frente): cole o bloco do Cenário N aqui em A, e SÓ DEPOIS
-- que a instrução mandar, cole o bloco correspondente do Cenário N em B —
-- cada cenário de A abre uma transação e usa `pg_sleep` para mantê-la
-- aberta por uma janela de tempo; enquanto ela estiver aberta, a consulta
-- equivalente em B deve ficar "pendurada" (sem retornar) — isso É a prova
-- visual de que a trava está funcionando.
--
-- PRÉ-REQUISITOS: mesmos de `11_6_5_02_roteiro_testes_sequenciais.sql`
-- (RPC aplicada, fixtures gerais + adicionais carregadas). Rode
-- `00_check_target_not_producao.sh`/`.ps1` até "LIBERADO" ANTES de abrir a
-- segunda aba.
-- =============================================================================

-- =============================================================================
-- CENÁRIO 1 (seção 2D) — DUAS chamadas simultâneas com o MESMO operacao_id
-- (prova da correção desta etapa: antes só havia um SELECT sem lock antes
-- do INSERT — duas chamadas concorrentes quebrariam com violação de chave
-- primária DEPOIS de já terem escrito de verdade).
-- =============================================================================
-- PASSO A1: rode isto agora.
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;

begin;
select clock_timestamp() as inicio_A1;
-- `pg_sleep` DENTRO da própria função não é possível (ela não tem esse
-- parâmetro) — o sleep aqui acontece ENTRE a trava advisory (já adquirida
-- no início da função, antes de qualquer sleep nosso) e o commit, usando
-- uma chamada auxiliar ANTES da RPC real para seguramos a mesma trava
-- advisory manualmente e observarmos B esperar por ela.
select pg_advisory_xact_lock(hashtextextended('comparacao_patrimonio:66666666-6666-4666-8666-600000000001', 0));
-- SEGURE: a transação de A fica aberta por 15s a partir daqui, com a
-- MESMA trava advisory que a RPC usaria para este operacao_id. VÁ AGORA
-- para a aba B e rode o "PASSO B1" de `11_6_5_03_concorrencia_sessaoB.sql`
-- ENQUANTO este pg_sleep ainda está rodando — B deve ficar PARADA (nunca
-- retornar) até este commit.
select pg_sleep(15);
-- só agora chama a RPC de verdade, ainda dentro da MESMA transação (então
-- ainda segura a trava) — simula "A é quem realmente executa primeiro".
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '66666666-6666-4666-8666-600000000001',
  p_lote_id := '66666666-6666-4666-8666-600000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_observacao := 'ZZ_HOMOLOG 11.6.5 — 2D sessão A'
);
commit;
select 'A1 commitou — B deveria ter ficado parada até aqui e então recebido o MESMO resultado (ja_executado=true), sem erro de chave duplicada' as resultado_esperado;
reset role;


-- =============================================================================
-- CENÁRIO 2 (seção 2E) — DUAS operações com operacao_id DIFERENTES,
-- mirando o MESMO patrimônio, a partir do MESMO snapshot (versao_esperada)
-- — a primeira a chegar deve concluir; a segunda deve detectar conflito de
-- versão (P0040), nunca aplicar por cima.
-- =============================================================================
-- PASSO A2a: rode isto PRIMEIRO para capturar o snapshot (ANOTE o valor de
-- `versao_compartilhada` — B precisa do MESMO valor).
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;
select atualizado_em as versao_compartilhada from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';

-- PASSO A2b: com o valor anotado (cole-o no lugar do literal abaixo),
-- rode isto.
begin;
select clock_timestamp() as inicio_A2;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '77777777-7777-4777-8777-700000000001',
  p_lote_id := '77777777-7777-4777-8777-700000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := '2000-01-01T00:00:00Z', -- <<< COLE aqui versao_compartilhada
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 2E sessão A (deve vencer)'
);
-- SEGURE: vá para B e rode "PASSO B2" (MESMO versao_esperada, operacao_id
-- DIFERENTE) enquanto este pg_sleep roda — diferente do Cenário 1, aqui B
-- NÃO deveria ficar parada por uma trava advisory (ids diferentes), mas
-- DEVE ficar parada pela trava `for update` do patrimônio (a RPC trava a
-- LINHA do patrimônio, não só o operacao_id).
select pg_sleep(15);
commit;
select 'A2 commitou — B deveria ter ficado parada até aqui e então falhado com P0040 (versão desatualizada por causa de A)' as resultado_esperado;
reset role;
