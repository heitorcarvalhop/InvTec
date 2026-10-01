-- =============================================================================
-- PROMPT 11.6.5 — PASSO 2: roteiro de testes SEQUENCIAIS (uma única
-- conexão) de `public.aplicar_decisao_comparacao_patrimonio`. Cobre as
-- seções 1 (autorização), 2A/2B/2C (idempotência sem concorrência real —
-- ver `11_6_5_03_concorrencia_sessaoA/B.sql` para 2D/2E), 3 (atomicidade),
-- 4 (ausência de numero_patrimonio) e 5 (revalidação/P0040/P0042).
--
-- PRÉ-REQUISITOS: `11_6_5_00_prerequisitos_somente_leitura.sql` já rodado
-- (RPC aplicada, fixtures gerais + adicionais carregadas). Rode
-- `00_check_target_not_producao.sh`/`.ps1` até "LIBERADO" antes de tudo.
--
-- CADA CENÁRIO é `begin; ... rollback;` — nada aqui fica gravado de
-- verdade, então o roteiro pode ser rodado várias vezes seguidas sem
-- limpeza entre execuções (exceto quando o próprio comentário do cenário
-- disser o contrário). ANOTE o resultado de cada `select ... as
-- resultado_esperado` — comparar com o que realmente aconteceu é a
-- homologação em si.
-- =============================================================================


-- =============================================================================
-- SEÇÃO 6 — MATRIZ DE AUTORIZAÇÃO (SQL controlado)
-- =============================================================================
-- Para cada sessão abaixo, troque o `email` no `set_config`/`request.jwt
-- .claims` e rode o MESMO bloco de chamada — anote o código de erro (ou
-- sucesso) de cada uma. `p_operacao_id` é NOVO em cada tentativa (mesmo
-- cenário reaproveitado por 8 perfis diferentes precisaria de 8 ids
-- distintos) — os literais abaixo já são distintos por perfil.

-- 6.1 ADMIN — esperado: SUCESSO (retorna jsonb com metadados_atualizados=true).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000001',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — sessão ADMIN'
);
select 'ADMIN: esperado SUCESSO' as resultado_esperado;
rollback;

-- 6.2 GESTOR — esperado: RECUSADO (42501) — `has_perfil('ADMIN')` exige
-- exatamente ADMIN, diferente de `registrar_movimentacao`
-- (`ADMIN,GESTOR,OPERADOR`) — confirme que esta RPC é mais restrita de
-- propósito (só ADMIN decide regularizações em massa).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.gestor@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.gestor@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000002',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — sessão GESTOR'
);
select 'GESTOR: esperado RECUSADO 42501' as resultado_esperado;
rollback;

-- 6.3 OPERADOR — esperado: RECUSADO (42501).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.operador@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.operador@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000003',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — sessão OPERADOR'
);
select 'OPERADOR: esperado RECUSADO 42501' as resultado_esperado;
rollback;

-- 6.4 CONSULTA — esperado: RECUSADO (42501).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.consulta@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.consulta@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000004',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — sessão CONSULTA'
);
select 'CONSULTA: esperado RECUSADO 42501' as resultado_esperado;
rollback;

-- 6.5 Autenticado SEM perfil ativo (ex.: zzhomolog.semperfil@invtec.test,
-- ativo=false) — esperado: RECUSADO (42501) — `has_perfil` exige `ativo is
-- true`.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.semperfil@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.semperfil@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000005',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — sessão sem perfil ativo'
);
select 'SEM PERFIL ATIVO: esperado RECUSADO 42501' as resultado_esperado;
rollback;

-- 6.6 Chamada NÃO autenticada (role anon) — esperado: RECUSADO por
-- permissão de banco (a função nem tem GRANT para `anon` — erro de
-- privilégio antes mesmo de entrar na função, não um 42501 aplicativo).
begin;
set local role anon;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000006',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := now(),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — sessão anônima'
);
select 'ANÔNIMO: esperado RECUSADO (permission denied for function)' as resultado_esperado;
rollback;

-- 6.7 Leitura indevida de operação de OUTRO usuário (RLS de
-- patrimonio_comparacao_execucoes) — grava uma operação como ADMIN A,
-- tenta ler como GESTOR (perfil não-ADMIN, confirma o caso mais simples:
-- quem não é ADMIN não vê NADA da tabela). Para confirmar também "outro
-- ADMIN vê a linha mas o CLIENTE recusa por identidade", crie um segundo
-- usuário ADMIN de teste e repita com ele — a recusa por identidade em si
-- é um teste de aplicação, não de SQL puro (ver
-- `comparacao_execucao_test.dart`, "seção 1 — uma sessão diferente nunca
-- recebe o resultado...").
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '11111111-1111-4111-8111-100000000007',
  p_lote_id := '11111111-1111-4111-8111-100000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — gravado por admin A'
);
-- ainda na mesma transação: troque para GESTOR e tente ler.
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.gestor@invtec.test'), true);
set local role authenticated;
select count(*) as linhas_visiveis_para_nao_admin from public.patrimonio_comparacao_execucoes
where operacao_id = '11111111-1111-4111-8111-100000000007';
select 'esperado: 0 linhas visíveis para quem não é ADMIN' as resultado_esperado;
rollback;


-- =============================================================================
-- SEÇÃO 2 — IDEMPOTÊNCIA (A/B/C — sem concorrência real; 2D/2E ficam nos
-- scripts de concorrência)
-- =============================================================================
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;

-- 2A — execução normal.
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '22222222-2222-4222-8222-200000000001',
  p_lote_id := '22222222-2222-4222-8222-200000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 2A execução normal'
) as resultado_2a;

-- 2B — MESMO operacao_id, MESMOS parâmetros (idênticos byte-a-byte) —
-- esperado: devolve o MESMO resultado com "ja_executado": true, NENHUMA
-- nova movimentação/UPDATE (confira com o BLOCO de verificação abaixo).
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '22222222-2222-4222-8222-200000000001',
  p_lote_id := '22222222-2222-4222-8222-200000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 2A execução normal'
) as resultado_2b_deve_ter_ja_executado_true;

-- Verificação: só 1 linha nesta operacao_id (nunca duplicada).
select count(*) as deve_ser_1 from public.patrimonio_comparacao_execucoes
where operacao_id = '22222222-2222-4222-8222-200000000001';

-- 2C — MESMO operacao_id, um parâmetro DIFERENTE (descrição) — esperado:
-- erro P0041, e a linha de 2A/2B continua intocada (confira de novo o
-- count acima depois deste erro).
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '22222222-2222-4222-8222-200000000001',
  p_lote_id := '22222222-2222-4222-8222-200000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 2C descrição DIFERENTE'
);
select 'esperado: erro P0041' as resultado_2c;

rollback;


-- =============================================================================
-- SEÇÃO 3 — ATOMICIDADE POR PATRIMÔNIO
-- =============================================================================

-- 3.1 — metadados isoladamente.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000001',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000003'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000003'),
  p_marca := 'ZZ_HOMOLOG_MARCA'
);
select numero_patrimonio, marca, setor_atual_id, localizacao_atual_id
from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000003';
select 'esperado: marca alterada, setor/localização intocados' as resultado_3_1;
rollback;

-- 3.2 — localização isoladamente (mesmo setor).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000002',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.2 localização isolada',
  p_nova_localizacao_id := (select id from public.localizacoes where sigla = 'ZZHG-01')
  -- mesma localização do setor atual (GETEC) — troque para uma localização
  -- REALMENTE diferente dentro do mesmo setor se quiser um teste mais
  -- estrito; o objetivo aqui é confirmar que SÓ localização muda.
);
select numero_patrimonio, setor_atual_id, localizacao_atual_id
from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
rollback;

-- 3.3 — setor isoladamente (sem nova localização) — a localização do setor
-- ANTIGO deve ser LIMPA automaticamente (regra já homologada de
-- registrar_movimentacao/AJUSTE_INVENTARIO — nunca um "bug" desta RPC).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select localizacao_atual_id as localizacao_antes from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000003',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.3 troca de setor isolada',
  p_novo_setor_id := (select id from public.setores where sigla = 'ZZH1165D')
);
select numero_patrimonio, setor_atual_id, localizacao_atual_id
from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
select 'esperado: setor = ZZH1165D, localizacao_atual_id = NULL (limpa)' as resultado_3_3;
rollback;

-- 3.4 — metadados + localização juntos.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000004',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 3.4 descrição nova',
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.4 setor+metadado juntos',
  p_novo_setor_id := (select id from public.setores where sigla = 'ZZH1165D')
);
select numero_patrimonio, descricao, setor_atual_id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
rollback;

-- 3.5 — falha na movimentação DEPOIS do UPDATE de metadados (destino
-- inexistente) — esperado: erro, e a descrição NUNCA aparece alterada
-- (confira numa consulta NOVA, fora desta transação, depois do rollback).
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select descricao as descricao_antes from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000005',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_descricao := 'ZZ_HOMOLOG 11.6.5 — 3.5 NUNCA deveria persistir',
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.5 destino inválido',
  p_novo_setor_id := '00000000-0000-4000-8000-000000000000' -- setor inexistente de propósito
);
rollback;
select descricao from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01';
select 'esperado: igual a descricao_antes — NUNCA "3.5 NUNCA deveria persistir"' as resultado_3_5;

-- 3.6 — setor incompatível com a localização informada (localização de um
-- setor diferente do novo setor) — esperado: erro, nada gravado.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000006',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01'),
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.6 setor x localização incompatíveis',
  p_novo_setor_id := (select id from public.setores where sigla = 'ZZH1165D'),
  p_nova_localizacao_id := (select id from public.localizacoes where sigla = 'ZZHG-01') -- pertence a ZZHGETEC, não a ZZH1165D
);
select 'esperado: erro (localização não pertence ao setor de destino)' as resultado_3_6;
rollback;

-- 3.7 — patrimônio BAIXADO: alteração de setor/localização é recusada.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000007',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02'),
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.7 baixado não pode mudar setor',
  p_novo_setor_id := (select id from public.setores where sigla = 'ZZH1165D')
);
select 'esperado: erro (patrimônio baixado não pode mudar de setor)' as resultado_3_7;
rollback;
-- metadados EM patrimônio baixado continuam permitidos (não passam por
-- registrar_movimentacao) — confirma que o bloqueio é só de setor/localização.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000008',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02'),
  p_observacao := 'ZZ_HOMOLOG 11.6.5 — 3.7b metadado em baixado, deve funcionar'
);
select 'esperado: SUCESSO (metadado isolado nunca é bloqueado por BAIXADO)' as resultado_3_7b;
rollback;

-- 3.8 — pendência SEI incompatível (P0042) — ZZHOMOLOG-000001 tem um item
-- SEI PENDENTE (fixture adicional, passo 3). Alterar setor/localização
-- deve ser recusado; metadado isolado continua liberado.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000009',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_justificativa := 'ZZ_HOMOLOG 11.6.5 — 3.8 pendência SEI deveria bloquear',
  p_novo_setor_id := (select id from public.setores where sigla = 'ZZH1165D')
);
select 'esperado: erro P0042' as resultado_3_8;
rollback;
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '33333333-3333-4333-8333-300000000010',
  p_lote_id := '33333333-3333-4333-8333-300000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001'),
  p_observacao := 'ZZ_HOMOLOG 11.6.5 — 3.8b metadado isolado, mesmo com pendência SEI'
);
select 'esperado: SUCESSO (pendência SEI só bloqueia setor/localização)' as resultado_3_8b;
rollback;


-- =============================================================================
-- SEÇÃO 4 — numero_patrimonio NUNCA é um parâmetro aceito
-- =============================================================================
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
-- Esta chamada DEVE falhar na hora de RESOLVER a função (erro do tipo
-- "function public.aplicar_decisao_comparacao_patrimonio(...) does not
-- exist" ou "unrecognized parameter") — nunca silenciosamente ignorada.
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '44444444-4444-4444-8444-400000000001',
  p_lote_id := '44444444-4444-4444-8444-400000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000004'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000004'),
  p_numero_patrimonio := 'ZZHOMOLOG-FORJADO'
);
select 'esperado: erro de PARÂMETRO INEXISTENTE (p_numero_patrimonio não existe mais)' as resultado_4;
rollback;


-- =============================================================================
-- SEÇÃO 5 — REVALIDAÇÃO (P0040) fora do cenário de concorrência real
-- =============================================================================
-- Rode o BLOCO A primeiro e ANOTE o valor de `versao_antiga` impresso.
-- Depois cole esse valor literal (entre aspas) no lugar de
-- `:versao_antiga_colada_manualmente` nas DUAS chamadas do BLOCO B, e rode
-- o BLOCO B. (Isto é deliberadamente manual: o SQL Editor web não suporta
-- `\gset`/variáveis `psql` — quem rodar via `psql -f` pode trocar por
-- `\gset` e `:'versao_antiga'` se preferir.)

-- BLOCO A — captura a versão ANTIGA.
select atualizado_em as versao_antiga from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000005';

-- BLOCO B — cole o valor anotado acima nas duas linhas marcadas.
begin;
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), true);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, true);
set local role authenticated;
-- altera o patrimônio por um caminho DIFERENTE (metadado isolado, já prova
-- que atualizado_em muda em QUALQUER UPDATE, não só nos de setor/localização).
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '55555555-5555-4555-8555-500000000001',
  p_lote_id := '55555555-5555-4555-8555-500000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000005'),
  p_versao_esperada := '2000-01-01T00:00:00Z' -- <<< COLE aqui o valor de versao_antiga
  ,p_modelo := 'ZZ_HOMOLOG 11.6.5 — modelo alterado (bump de versão)'
);
-- reenvia OUTRA decisão com a MESMA versão ANTIGA (agora desatualizada) —
-- esperado: erro P0040.
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := '55555555-5555-4555-8555-500000000002',
  p_lote_id := '55555555-5555-4555-8555-500000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000005'),
  p_versao_esperada := '2000-01-01T00:00:00Z' -- <<< COLE o MESMO valor de versao_antiga
  ,p_marca := 'ZZ_HOMOLOG 11.6.5 — NUNCA deveria aplicar'
);
select 'esperado: erro P0040 na segunda chamada' as resultado_5;
rollback;
