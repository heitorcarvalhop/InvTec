-- =============================================================================
-- PROMPT 11.6.6, seção 3.D — TESTE FUNCIONAL MÍNIMO, SOMENTE APÓS SUA
-- AUTORIZAÇÃO EXPLÍCITA (depois dos passos A, B e C). Roda a RPC real UMA
-- vez, contra um patrimônio 100% FICTÍCIO criado só para este teste, dentro
-- de uma ÚNICA transação com ROLLBACK no final — nada persiste. A identidade
-- usada (auth.uid()) é a de um ADMIN REAL já existente neste projeto — isso
-- não é um dado fictício, é só simular a sessão de um administrador de
-- verdade já autorizado; o que é fictício é o SETOR/LOCALIZAÇÃO/PATRIMÔNIO
-- criados abaixo (prefixo ZZTESTE-11.6.6), nunca um bem real.
-- =============================================================================

begin;

-- Sessão: um ADMIN ativo real deste projeto (set local — some no fim da
-- transação, nunca vaza para fora dela).
select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', (select id from public.profiles where perfil = 'ADMIN' and ativo = true limit 1),
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;

-- Confirme que encontrou um ADMIN ativo antes de prosseguir — se vier vazio,
-- PARE e rode `rollback;` (não há administrador ativo para simular a sessão).
select (select id from public.profiles where perfil = 'ADMIN' and ativo = true limit 1) as admin_usado;

-- Fixtures fictícias mínimas, só para este teste.
insert into public.setores (nome, sigla, descricao)
values ('ZZ_TESTE_11_6_6', 'ZZT1166', 'Setor fictício — teste funcional mínimo PROMPT 11.6.6 (reversível)');

insert into public.localizacoes (setor_id, nome, sigla)
select id, 'Sala fictícia teste 11.6.6', 'ZZT1166-01' from public.setores where sigla = 'ZZT1166';

insert into public.patrimonios (numero_patrimonio, tipo_id, setor_atual_id, localizacao_atual_id, status, criado_por, descricao)
select 'ZZTESTE-11.6.6-01', (select id from public.tipos_patrimonio limit 1), s.id, l.id, 'DISPONIVEL',
       (select id from public.profiles where perfil = 'ADMIN' and ativo = true limit 1),
       'Patrimônio fictício — teste funcional mínimo PROMPT 11.6.6'
from public.setores s
join public.localizacoes l on l.setor_id = s.id
where s.sigla = 'ZZT1166';

-- Snapshot da versão ANTES (a RPC exige exatamente este valor).
select atualizado_em as versao_antes from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01';

-- Chama a RPC de verdade: altera um metadado (descrição) — cole o valor de
-- `versao_antes` acima no lugar do subselect, ou deixe o subselect (mais
-- simples, funciona igual dentro da mesma transação).
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := 'aaaaaaaa-1166-4aaa-8aaa-000000000001',
  p_lote_id := 'aaaaaaaa-1166-4aaa-8aaa-000000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01'),
  p_justificativa := 'Teste funcional mínimo — PROMPT 11.6.6 (transação será desfeita, nada persiste)',
  p_descricao := 'Descrição alterada pelo teste funcional 11.6.6'
);

-- Conferências — esperado: descrição alterada; atualizado_em mudou; 1 linha
-- em patrimonio_comparacao_execucoes; nenhuma movimentação (só descrição
-- mudou, sem setor/localização nesta chamada).
select numero_patrimonio, descricao, setor_atual_id, localizacao_atual_id, atualizado_em
from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01';

select operacao_id, patrimonio_id, resultado
from public.patrimonio_comparacao_execucoes
where operacao_id = 'aaaaaaaa-1166-4aaa-8aaa-000000000001';

select count(*) as movimentacoes_deste_teste
from public.movimentacoes
where patrimonio_id = (select id from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01');

-- Reteste de idempotência, AINDA na mesma transação: repetir o MESMO
-- operacao_id com os MESMOS parâmetros deve devolver o resultado já gravado
-- (ja_executado = true), sem erro e sem nova linha em
-- patrimonio_comparacao_execucoes.
select public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id := 'aaaaaaaa-1166-4aaa-8aaa-000000000001',
  p_lote_id := 'aaaaaaaa-1166-4aaa-8aaa-000000000000',
  p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01'),
  p_versao_esperada := (select atualizado_em from public.patrimonios where numero_patrimonio = 'ZZTESTE-11.6.6-01'),
  p_justificativa := 'Teste funcional mínimo — PROMPT 11.6.6 (transação será desfeita, nada persiste)',
  p_descricao := 'Descrição alterada pelo teste funcional 11.6.6'
);
select count(*) as deve_continuar_1 from public.patrimonio_comparacao_execucoes
where operacao_id = 'aaaaaaaa-1166-4aaa-8aaa-000000000001';

reset role;

-- =============================================================================
-- DESFAZ TUDO — nada deste teste persiste. Rode esta linha por último.
-- =============================================================================
rollback;

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO FINAL (rode DEPOIS do rollback, fora de qualquer transação
-- aberta) — esperado: 0 em tudo, e os totais de patrimonios/movimentacoes/
-- setores/localizacoes IDÊNTICOS à "foto antes" do passo A/C.
-- -----------------------------------------------------------------------------
select count(*) as sobras_patrimonio from public.patrimonios where numero_patrimonio like 'ZZTESTE-11.6.6%';
select count(*) as sobras_setor from public.setores where sigla = 'ZZT1166';
select count(*) as sobras_execucao from public.patrimonio_comparacao_execucoes
where operacao_id = 'aaaaaaaa-1166-4aaa-8aaa-000000000001';
