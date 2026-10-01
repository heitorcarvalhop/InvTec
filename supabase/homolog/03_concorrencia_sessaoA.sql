-- =============================================================================
-- PROMPT 11.3.4, seção 6 — TESTES DE CONCORRÊNCIA REAL (duas conexões
-- independentes). Uma sequência de chamadas na MESMA conexão NUNCA prova
-- ausência de corrida — por isso estes testes exigem DUAS ABAS separadas
-- do SQL Editor (ou duas conexões `psql`) abertas ao MESMO TEMPO contra o
-- projeto de HOMOLOGAÇÃO.
--
-- Esta é a SESSÃO A. A parceira é `03_concorrencia_sessaoB.sql` (SESSÃO
-- B) — abra as duas abas ANTES de começar. Rode um CENÁRIO de cada vez
-- (não pule à frente): cole o bloco do Cenário N aqui em A, e SÓ DEPOIS
-- que a instrução mandar, cole o bloco correspondente do Cenário N em B —
-- cada cenário de A abre uma transação e usa `pg_sleep` para mantê-la
-- aberta por uma janela de tempo; enquanto ela estiver aberta, a consulta
-- equivalente em B deve ficar "pendurada" (sem retornar) — isso É a prova
-- visual de que a trava está funcionando. Se a consulta de B retornar
-- IMEDIATAMENTE em vez de esperar, a trava NÃO está funcionando — reporte
-- isso como falha.
--
-- Pré-requisitos: mesmos de `02_roteiro_testes_sequenciais.sql` (fixtures
-- aplicadas). Cada cenário usa um número de documento SEI fictício
-- próprio (ZZHOMOLOG-CONC-N) para não interferir com os outros.
--
-- PROMPT 11.3.4.1 — antes de abrir as DUAS abas: rode
-- `00_check_target_not_producao.sh env/homologacao.env` (ou o `.ps1`
-- equivalente) até imprimir "LIBERADO", confirme visualmente o ref do
-- Dashboard, e SÓ ENTÃO abra a segunda aba (B) navegando a partir da
-- mesma aba já confirmada — nunca abrindo uma aba nova "de memória"
-- (o script de guarda não protege uma aba que ele nunca viu).
-- =============================================================================

-- =============================================================================
-- CENÁRIO 1 — duas criações simultâneas do MESMO documento (mesmo SEI,
-- ambas sem processo)
-- =============================================================================
-- PASSO A1: rode isto agora.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;

select clock_timestamp() as inicio_A1;
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA',
  p_nome_arquivo := 'zz_conc1_A.pdf',
  p_hash_sha256 := 'zz-conc1-a',
  p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'))),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-1'
);
-- SEGURE: a transação de A fica aberta por 15s a partir daqui. VÁ AGORA
-- para a aba B e rode o "PASSO B1" de `03_concorrencia_sessaoB.sql`
-- ENQUANTO este pg_sleep ainda está rodando.
select pg_sleep(15);
commit;
select 'A1 commitou — confira se B ficou parada até este ponto e falhou com P0020 depois' as resultado_esperado;

-- =============================================================================
-- CENÁRIO 2 — criação SEM processo (A) simultânea com criação COM
-- processo (B), mesmo SEI (PROMPT 11.3.3, seção 3 — assimetria corrigida)
-- =============================================================================
-- PASSO A2: rode isto agora.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;

select clock_timestamp() as inicio_A2;
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA',
  p_nome_arquivo := 'zz_conc2_A.pdf',
  p_hash_sha256 := 'zz-conc2-a',
  p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'))),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-2',
  p_numero_processo := null
);
-- SEGURE: vá para B agora e rode o "PASSO B2" (que usa o MESMO SEI, mas
-- COM processo informado) enquanto este pg_sleep roda.
select pg_sleep(15);
commit;
select 'A2 commitou — B deveria ter ficado parada e falhado com P0020 (mesmo com processo diferente/ausente)' as resultado_esperado;

-- =============================================================================
-- CENÁRIO 3 — duas edições concorrentes com a MESMA versão lida
-- =============================================================================
-- PASSO A3a: rode isto PRIMEIRO para criar o documento-base (fora de
-- qualquer transação longa) e anote/confira o id impresso.
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz_conc3.pdf', p_hash_sha256 := 'zz-conc3',
  p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'))),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-3'
);
-- Ambas as sessões (A e B) devem ler a MESMA versão (1) ANTES de A3b —
-- rode este SELECT nas DUAS abas agora e confirme que a versão é 1 nas duas:
select id, versao from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-CONC-3';

-- PASSO A3b: com a versão confirmada como 1 nas duas abas, rode isto em A.
begin;
select clock_timestamp() as inicio_A3;
select public.editar_documento_sei_pendente(
  p_documento_id := (select id from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-CONC-3'),
  p_versao_esperada := 1,
  p_motivo := 'ZZ_HOMOLOG edição concorrente — sessão A'
);
-- SEGURE: vá para B e rode "PASSO B3" (mesma versao_esperada=1) enquanto
-- este pg_sleep roda — B deve FICAR PARADA (o documento está travado por
-- `for update`), nunca "correr na frente".
select pg_sleep(15);
commit;
select 'A3 commitou (versão 1->2) — B deveria ter ficado parada e então falhar com P0010 (versão desatualizada)' as resultado_esperado;

-- =============================================================================
-- CENÁRIO 4 — edição concorrente com cancelamento de item do MESMO
-- documento (prova de que a ordem de locks documento->item evita deadlock)
-- =============================================================================
-- PASSO A4a: cria o documento-base com 2 itens.
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz_conc4.pdf', p_hash_sha256 := 'zz-conc4',
  p_itens := jsonb_build_array(
    jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000003')),
    jsonb_build_object('linha', 2, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000004'))
  ),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-4'
);
-- Anote o id do SEGUNDO item (linha=2) — B vai precisar dele:
select i.id as item_linha_2_para_sessao_B, i.linha
from public.documentos_sei_itens i
join public.documentos_sei d on d.id = i.documento_id
where d.numero_documento_sei = 'ZZHOMOLOG-CONC-4' and i.linha = 2;

-- PASSO A4b: rode isto — edita o documento (trava o documento inteiro
-- primeiro, como TODAS as funções de escrita desta migration fazem).
begin;
select clock_timestamp() as inicio_A4;
select public.editar_documento_sei_pendente(
  p_documento_id := (select id from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-CONC-4'),
  p_versao_esperada := 1,
  p_motivo := 'ZZ_HOMOLOG edição concorrente com cancelamento — sessão A'
);
-- SEGURE: vá para B e rode "PASSO B4" (cancelar o item de linha 2, id
-- anotado acima) enquanto este pg_sleep roda. B deve FICAR PARADA (nunca
-- retornar antes de A commitar) — se B retornar imediatamente OU se
-- qualquer uma travar com "deadlock detected", é uma FALHA real.
select pg_sleep(15);
commit;
select 'A4 commitou — B deveria ter ficado parada (nunca deadlock) e então ter cancelado o item normalmente' as resultado_esperado;

-- =============================================================================
-- CENÁRIO 5 — cancelamento individual concorrente com cancelamento do
-- restante do documento
-- =============================================================================
-- PASSO A5a: cria o documento-base com 2 itens.
select public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz_conc5.pdf', p_hash_sha256 := 'zz-conc5',
  p_itens := jsonb_build_array(
    jsonb_build_object('linha', 1, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000005')),
    jsonb_build_object('linha', 2, 'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'))
  ),
  p_numero_documento_sei := 'ZZHOMOLOG-CONC-5'
);
select i.id as item_linha_1_para_sessao_B, i.linha
from public.documentos_sei_itens i
join public.documentos_sei d on d.id = i.documento_id
where d.numero_documento_sei = 'ZZHOMOLOG-CONC-5' and i.linha = 1;

-- PASSO A5b: rode isto — cancela TODOS os pendentes do documento.
begin;
select clock_timestamp() as inicio_A5;
select * from public.cancelar_pendentes_documento_sei(
  p_documento_id := (select id from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-CONC-5'),
  p_motivo := 'ZZ_HOMOLOG cancelamento total concorrente — sessão A'
);
-- SEGURE: vá para B e rode "PASSO B5" (cancelar o item de linha 1
-- individualmente) enquanto este pg_sleep roda. B deve ficar parada até A
-- commitar, e então falhar (o item já não estará mais PENDENTE).
select pg_sleep(15);
commit;
select 'A5 commitou — B deveria ter ficado parada e então falhado (item já CANCELADO por A)' as resultado_esperado;

reset role;
select 'FIM DA SESSÃO A — confira as 5 linhas "resultado_esperado" contra o que realmente aconteceu na aba B' as fim;
