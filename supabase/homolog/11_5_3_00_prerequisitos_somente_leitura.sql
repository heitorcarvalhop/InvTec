-- =============================================================================
-- PROMPT 11.5.3 — PASSO 0 (SOMENTE LEITURA): pré-requisitos da homologação
-- transacional de public.concluir_itens_documento_sei_lote.
-- =============================================================================
-- Este arquivo só contém SELECT. Não escreve nada, não cria nada.
--
-- ONDE RODAR: PROMPT 11.5.3.1 — este teste roda no projeto Supabase EXISTENTE
-- (o mesmo onde 20260928100000_add_concluir_itens_documento_sei_lote.sql já
-- foi aplicada e confirmada pelo usuário) — não há um segundo projeto de
-- homologação disponível para esta etapa. A segurança do teste não depende de
-- rodar num projeto separado: depende de (a) usar EXCLUSIVAMENTE fixtures
-- fictícias com o prefixo ZZHOMOLOG-11.5.3, nunca tocando patrimônio,
-- documento ou setor/localização reais, e (b) a transação inteira terminar em
-- ROLLBACK, nunca em COMMIT (ver o cabeçalho de 11_5_3_concluir_lote_
-- rollback.sql). Rode com o "Role" do editor em `postgres`. Estado já
-- confirmado antes deste prompt: 1414 patrimônios, 1414 movimentações, 2
-- documentos SEI, 35 itens SEI, 5 eventos SEI, 0 lotes registrados — o BLOCO 3
-- abaixo relê esses números NA HORA (não confie neste comentário, que pode
-- ficar desatualizado).
--
-- Rode cada bloco separadamente (o editor mostra o resultado do ÚLTIMO SELECT
-- de uma execução) e ANOTE o resultado do BLOCO 3: é a "foto antes" que
-- 11_5_3_99_verificacao_pos_rollback.sql compara depois do ROLLBACK.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BLOCO 1 — as DUAS RPCs estão instaladas, com as assinaturas certas, e
-- `authenticated` pode executar as duas? Esperado: 2 linhas.
--   * concluir_item_documento_sei: 5 parâmetros — PRECISA continuar EXATAMENTE
--     assim (a migration de lote NUNCA a altera; ver PROMPT 11.5.2/11.5.2.1).
--   * concluir_itens_documento_sei_lote: 6 parâmetros (novo p_lote_id).
-- prosecdef = true; authenticated_executa = true; anon_executa = false nas duas.
-- -----------------------------------------------------------------------------
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as assinatura,
  p.prosecdef as security_definer,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated_executa,
  has_function_privilege('anon', p.oid, 'execute') as anon_executa
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('concluir_item_documento_sei', 'concluir_itens_documento_sei_lote')
order by p.proname;


-- -----------------------------------------------------------------------------
-- BLOCO 1B — a tabela de controle do lote existe, com RLS ligada e só SELECT
-- para authenticated (nunca INSERT/UPDATE/DELETE). Esperado: 1 linha;
-- rowsecurity = true; authenticated_select = true; authenticated_insert =
-- false; authenticated_update = false; authenticated_delete = false.
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
where n.nspname = 'public' and c.relname = 'documentos_sei_lotes_conclusao';


-- -----------------------------------------------------------------------------
-- BLOCO 2 — QUAL USUÁRIO USAR? (o script principal NÃO cria usuário e NÃO
-- inventa UUID: ele usa um profile que JÁ EXISTE e está ativo.)
--
-- Escolha UM `id` desta lista (perfil ADMIN, GESTOR ou OPERADOR, ativo) e cole
-- no lugar de __USER_ID_HOMOLOGACAO__ no script principal. Em homologação,
-- prefira um dos usuários zzhomolog.*@invtec.test (ver 01_fixtures_homologacao
-- do PROMPT 11.3.4). O usuário NÃO é alterado: o script só grava o id dele
-- como autor/realizado_por das linhas fictícias (que somem no ROLLBACK).
-- -----------------------------------------------------------------------------
select
  p.id as user_id,
  p.email,
  p.nome,
  p.perfil,
  p.ativo
from public.profiles p
where p.ativo is true
  and p.perfil in ('ADMIN', 'GESTOR', 'OPERADOR')
order by (p.email like 'zzhomolog.%') desc, p.perfil, p.email;


-- -----------------------------------------------------------------------------
-- BLOCO 3 — "FOTO ANTES": contagem + impressão digital (md5 das linhas
-- inteiras) de todas as tabelas que o lote toca (as mesmas 8 tabelas de
-- 11_4_4, mais `documentos_sei_lotes_conclusao`, nova nesta etapa). ANOTE ESTE
-- RESULTADO. Depois do ROLLBACK, o bloco equivalente do arquivo 99 precisa
-- devolver EXATAMENTE os mesmos valores (contagem E md5): o md5 das linhas
-- inteiras também prova que nenhuma linha EXISTENTE (patrimônio real, Despacho
-- 577, os 2 documentos SEI já existentes, seus itens/eventos) foi modificada.
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as total,
       md5(coalesce(string_agg(t::text, '|' order by t.id), '')) as impressao
from public.patrimonios t
union all
select 'movimentacoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.movimentacoes t
union all
select 'documentos_sei', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei t
union all
select 'documentos_sei_itens', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei_itens t
union all
select 'documentos_sei_eventos', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei_eventos t
union all
select 'documentos_sei_lotes_conclusao', count(*), md5(coalesce(string_agg(t::text, '|' order by t.lote_id), ''))
from public.documentos_sei_lotes_conclusao t
union all
select 'setores', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.setores t
union all
select 'localizacoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.localizacoes t
union all
select 'tipos_patrimonio', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.tipos_patrimonio t
order by tabela;


-- -----------------------------------------------------------------------------
-- BLOCO 4 — sobras de uma tentativa anterior desta etapa (11.5.3), com o
-- prefixo NOVO (nunca reaproveita ZZHOMOLOG-11.4.4). Esperado: 0 em tudo. Se
-- algo aparecer, NÃO rode o script principal: investigue (ele mesmo aborta se
-- encontrar estas sobras).
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as sobras
from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-11.5.3%'
union all
select 'documentos_sei', count(*)
from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.5.3%'
union all
select 'setores', count(*)
from public.setores where nome like 'ZZHOMOLOG-11.5.3%' or sigla like 'ZZHOMOLOG-11.5.3%'
union all
select 'tipos_patrimonio', count(*)
from public.tipos_patrimonio where nome like 'ZZHOMOLOG-11.5.3%'
union all
select 'movimentacoes', count(*)
from public.movimentacoes
where numero_documento like 'ZZHOMOLOG-SEI-11.5.3%' or numero_chamado like 'ZZHOMOLOG-4556-11.5.3%'
union all
select 'documentos_sei_lotes_conclusao', count(*)
from public.documentos_sei_lotes_conclusao
where documento_id in (select id from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.5.3%')
order by tabela;
