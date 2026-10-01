-- =============================================================================
-- PROMPT 11.4.4 — PASSO 0 (SOMENTE LEITURA): pré-requisitos da homologação
-- transacional de public.concluir_item_documento_sei.
-- =============================================================================
-- Este arquivo só contém SELECT. Não escreve nada, não cria nada.
--
-- ONDE RODAR: no SQL Editor do projeto onde as migrations 20260925130000 e
-- 20260925140000 foram aplicadas, com o "Role" do editor em `postgres`.
-- Prefira o projeto de HOMOLOGAÇÃO (ver 00_check_target_not_producao.*). Se o
-- único banco com a RPC instalada for o de produção, veja "RISCOS" no relatório
-- do PROMPT 11.4.4 antes de rodar o script principal.
--
-- Rode cada bloco separadamente (o editor mostra o resultado do ÚLTIMO SELECT
-- de uma execução) e ANOTE o resultado do BLOCO 3: é a "foto antes" que o
-- arquivo 11_4_4_99_rollback_e_verificacao.sql compara depois do ROLLBACK.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BLOCO 1 — A RPC está instalada e o papel `authenticated` pode executá-la?
-- Esperado: 1 linha; assinatura com 5 parâmetros; prosecdef = true;
-- authenticated_executa = true; anon_executa = false.
-- -----------------------------------------------------------------------------
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as assinatura,
  p.prosecdef as security_definer,
  has_function_privilege('authenticated', p.oid, 'execute') as authenticated_executa,
  has_function_privilege('anon', p.oid, 'execute') as anon_executa,
  current_user as papel_do_editor,
  pg_has_role(current_user, 'authenticated', 'member') as editor_pode_assumir_authenticated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'concluir_item_documento_sei';


-- -----------------------------------------------------------------------------
-- BLOCO 2 — QUAL USUÁRIO USAR? (o script principal NÃO cria usuário e NÃO
-- inventa UUID: ele usa um profile que JÁ EXISTE e está ativo.)
--
-- Escolha UM `id` desta lista (perfil ADMIN, GESTOR ou OPERADOR, ativo) e cole
-- no lugar de __USER_ID_HOMOLOGACAO__ no script principal. Em homologação,
-- prefira um dos usuários zzhomolog.*@invtec.test (ver 01_fixtures).
-- O usuário NÃO é alterado: o script só grava o id dele como autor/realizado_por
-- das linhas fictícias (que somem no ROLLBACK).
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
-- inteiras) de todas as tabelas que a RPC toca ou que o script cria.
-- ANOTE ESTE RESULTADO. Depois do ROLLBACK, o bloco equivalente do arquivo 99
-- precisa devolver EXATAMENTE os mesmos valores (contagem E md5): o md5 das
-- linhas inteiras também prova que nenhuma linha EXISTENTE (patrimônio real,
-- Despacho 577, itens, setores, localizações) foi modificada.
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
-- BLOCO 4 — sobras de uma tentativa anterior? Esperado: 0 em tudo. Se algo
-- aparecer, NÃO rode o script principal: investigue (ele mesmo aborta se
-- encontrar estas sobras).
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as sobras
from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-11.4.4%'
union all
select 'documentos_sei', count(*)
from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.4.4%'
union all
select 'setores', count(*)
from public.setores where nome like 'ZZHOMOLOG-11.4.4%' or sigla like 'ZZHOMOLOG-11.4.4%'
union all
select 'tipos_patrimonio', count(*)
from public.tipos_patrimonio where nome like 'ZZHOMOLOG-11.4.4%'
union all
select 'movimentacoes', count(*)
from public.movimentacoes
where numero_documento like 'ZZHOMOLOG-SEI-11.4.4%' or numero_chamado like 'ZZHOMOLOG-4556%'
order by tabela;
