-- =============================================================================
-- PROMPT 11.6.6, seção 3.A — CONSULTA INICIAL, SOMENTE LEITURA.
-- Rode isto no SQL Editor do projeto Supabase ATUAL (o mesmo já em uso —
-- nenhum projeto/banco novo) ANTES de aplicar a migration
-- 20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql.
-- Este arquivo não escreve nada, não cria nada, não altera nada.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) A função e a tabela novas NÃO podem existir ainda (confirma que a
--    migration realmente está pendente, sem conflito de nome). Esperado:
--    "ja_existe" = false nas duas linhas.
-- -----------------------------------------------------------------------------
select 'aplicar_decisao_comparacao_patrimonio (function)' as objeto,
       exists (
         select 1 from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'aplicar_decisao_comparacao_patrimonio'
       ) as ja_existe
union all
select 'patrimonio_comparacao_execucoes (table)',
       exists (
         select 1 from pg_class c
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'patrimonio_comparacao_execucoes'
       );

-- -----------------------------------------------------------------------------
-- 2) Dependências que a nova função chama já devem existir (a migration NÃO
--    as recria — só reaproveita). Esperado: "existe" = true em todas.
-- -----------------------------------------------------------------------------
select 'registrar_movimentacao' as dependencia,
       exists (
         select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'registrar_movimentacao'
       ) as existe
union all
select 'private.has_perfil',
       exists (
         select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'private' and p.proname = 'has_perfil'
       )
union all
select 'documentos_sei_itens (table)',
       exists (
         select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'documentos_sei_itens'
       )
union all
select 'trg_patrimonios_set_updated_at (trigger)',
       exists (select 1 from pg_trigger where tgname = 'trg_patrimonios_set_updated_at');

-- -----------------------------------------------------------------------------
-- 3) Histórico de migrations já aplicadas neste projeto (só existe se as
--    migrations foram aplicadas via Supabase CLI — se a tabela não existir,
--    ignore este bloco e confira manualmente no Dashboard, em
--    Database > Migrations). Esperado: a mais recente é
--    20260928100000_add_concluir_itens_documento_sei_lote e
--    20260930120000_add_aplicar_decisao_comparacao_patrimonio AINDA NÃO
--    aparece na lista.
-- -----------------------------------------------------------------------------
SELECT to_regclass('supabase_migrations.schema_migrations')
       AS tabela_de_migrations;

-- -----------------------------------------------------------------------------
-- 4) "Foto antes" — contagens das tabelas que a nova função toca. Guarde este
--    resultado para comparar com o bloco C (pós-instalação) e, principalmente,
--    para conferir DEPOIS do teste funcional (bloco D) que os totais de
--    patrimonios/movimentacoes voltaram exatamente a este valor.
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as total from public.patrimonios
union all
select 'movimentacoes', count(*) from public.movimentacoes
union all
select 'setores', count(*) from public.setores
union all
select 'localizacoes', count(*) from public.localizacoes;
