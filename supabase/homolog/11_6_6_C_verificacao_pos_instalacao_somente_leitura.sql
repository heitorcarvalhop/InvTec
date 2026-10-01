-- =============================================================================
-- PROMPT 11.6.6, seção 3.C — VERIFICAÇÃO PÓS-INSTALAÇÃO, SOMENTE LEITURA.
-- Rode isto DEPOIS de aplicar (passo B) a migration
-- 20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql no projeto
-- Supabase ATUAL. Mesmo conteúdo do Bloco 1/1B de
-- `11_6_5_00_prerequisitos_somente_leitura.sql` (reaproveitado aqui, sem os
-- blocos específicos de fixtures de homologação que não existem neste
-- projeto). Este arquivo não escreve nada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) A RPC está instalada com a assinatura ESPERADA (12 parâmetros, SEM
--    p_numero_patrimonio), security definer, e só `authenticated` executa.
--    Esperado: 1 linha; security_definer = true; authenticated_executa =
--    true; anon_executa = false; sem_numero_patrimonio = true.
-- -----------------------------------------------------------------------------
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as assinatura,
  p.prosecdef as security_definer,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated_executa,
  has_function_privilege('anon', p.oid, 'execute') as anon_executa,
  pg_get_function_identity_arguments(p.oid) not ilike '%numero_patrimonio%' as sem_numero_patrimonio
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'aplicar_decisao_comparacao_patrimonio';

-- Confira manualmente (leitura do texto) que o corpo da função:
--   a) chama pg_advisory_xact_lock(hashtextextended('comparacao_patrimonio:'...))
--      ANTES do primeiro SELECT em patrimonio_comparacao_execucoes;
--   b) a checagem de identidade do retry inclui `justificativa`;
--   c) não existe nenhum bloco `exception when` envolvendo as escritas.
select pg_get_functiondef(p.oid) as definicao_completa
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'aplicar_decisao_comparacao_patrimonio';

-- -----------------------------------------------------------------------------
-- 2) A tabela de controle existe, com RLS ligada e só SELECT para
--    authenticated (nunca INSERT/UPDATE/DELETE — só a função SECURITY
--    DEFINER escreve). Esperado: 1 linha; rowsecurity = true;
--    authenticated_select = true; authenticated_insert/update/delete = false.
-- -----------------------------------------------------------------------------
select
  c.relname as tabela,
  c.relrowsecurity as rowsecurity,
  has_table_privilege('authenticated', c.oid, 'select') as authenticated_select,
  has_table_privilege('authenticated', c.oid, 'insert') as authenticated_insert,
  has_table_privilege('authenticated', c.oid, 'update') as authenticated_update,
  has_table_privilege('authenticated', c.oid, 'delete') as authenticated_delete
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'patrimonio_comparacao_execucoes';

-- -----------------------------------------------------------------------------
-- 3) Confirma que nada real mudou só de aplicar a migration (criar função +
--    tabela não altera nenhuma linha existente). Compare com o bloco 4 do
--    passo A — os totais devem ser IDÊNTICOS.
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as total from public.patrimonios
union all
select 'movimentacoes', count(*) from public.movimentacoes
union all
select 'setores', count(*) from public.setores
union all
select 'localizacoes', count(*) from public.localizacoes
union all
select 'patrimonio_comparacao_execucoes', count(*) from public.patrimonio_comparacao_execucoes;
