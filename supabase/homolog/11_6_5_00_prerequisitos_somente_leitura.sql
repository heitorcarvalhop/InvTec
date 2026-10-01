-- =============================================================================
-- PROMPT 11.6.5 — PASSO 0 (SOMENTE LEITURA): pré-requisitos da homologação
-- de `public.aplicar_decisao_comparacao_patrimonio` /
-- `public.patrimonio_comparacao_execucoes`
-- (migration 20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql —
-- PREPARADA, NÃO APLICADA em nenhum ambiente ainda).
-- =============================================================================
-- Este arquivo só contém SELECT. Não escreve nada, não cria nada.
--
-- PROMPT 11.6.5, seção 9 — restrição explícita: "não aplicar a migration em
-- produção para contornar a limitação [de não haver Postgres disponível]".
-- ANTES de rodar isto (ou qualquer script desta pasta com prefixo
-- 11_6_5_), em ORDEM:
--   1. `00_check_target_not_producao.sh env/homologacao.env` (ou o `.ps1`)
--      até imprimir "LIBERADO" — confirmação de arquivo E visual do ref do
--      Dashboard aberto.
--   2. Aplicar `20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql`
--      NESTE projeto de homologação (nunca em produção) — via
--      `supabase db push` apontado para homologação, ou colando o SQL
--      completo no SQL Editor da MESMA aba confirmada no passo 1.
--   3. Rodar `01_fixtures_homologacao.sql` (se ainda não tiver rodado nesta
--      base — reaproveita ZZHOMOLOG-000001..5 / ZZHGETEC / ZZHGEASI / os 4
--      usuários zzhomolog.*@invtec.test).
--   4. Rodar `11_6_5_01_fixtures_adicionais.sql` (fixtures específicas
--      desta etapa: um patrimônio BAIXADO, um segundo setor/localização
--      para testar troca de setor, e um documento SEI pendente vinculado a
--      um patrimônio, para o cenário P0042).
-- SÓ ENTÃO rode este arquivo (BLOCO 1 em diante).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BLOCO 1 — a RPC está instalada, com a assinatura ESPERADA (12 parâmetros,
-- SEM p_numero_patrimonio — ver PROMPT 11.6.5, seção 4), security definer,
-- e só `authenticated` pode executar. Esperado: 1 linha; prosecdef = true;
-- authenticated_executa = true; anon_executa = false; a assinatura NÃO
-- contém "numero_patrimonio".
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

-- Confira manualmente (`pg_get_functiondef`) que o CORPO da função:
--   a) chama `pg_advisory_xact_lock(hashtextextended('comparacao_patrimonio:' ...))`
--      ANTES do primeiro SELECT em patrimonio_comparacao_execucoes (seção 2D);
--   b) a comparação de identidade do retry inclui `justificativa` (seção 2C);
--   c) não existe nenhum bloco `exception when` envolvendo as escritas
--      (atomicidade por exceção não tratada — seção 3).
-- (Já coberto estruturalmente por
-- `aplicar_decisao_comparacao_patrimonio_migration_test.dart`, que lê o
-- ARQUIVO da migration — isto aqui confere que o BANCO tem exatamente o
-- que o arquivo diz, e nada mais.)
select pg_get_functiondef(p.oid) as definicao_completa
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'aplicar_decisao_comparacao_patrimonio';


-- -----------------------------------------------------------------------------
-- BLOCO 1B — a tabela de controle existe, com RLS ligada e só SELECT para
-- authenticated (nunca INSERT/UPDATE/DELETE — só a função SECURITY DEFINER
-- escreve). Esperado: 1 linha; rowsecurity = true; authenticated_select =
-- true; authenticated_insert/update/delete = false.
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
-- BLOCO 2 — usuários de teste já promovidos (ver `01_fixtures_homologacao
-- .sql`, passo 2) — as 4 sessões de autorização da seção 6 do prompt usam
-- estes. O 5º cenário ("autenticado sem perfil ativo") usa um usuário
-- deixado SEM promoção (perfil=CONSULTA padrão da trigger, ativo=false) —
-- crie um adicional (ex.: zzhomolog.semperfil@invtec.test) se ainda não
-- existir, sem rodar nenhum UPDATE nele.
-- -----------------------------------------------------------------------------
select p.id as user_id, p.email, p.nome, p.perfil, p.ativo
from public.profiles p
where p.email like 'zzhomolog.%@invtec.test'
order by p.email;


-- -----------------------------------------------------------------------------
-- BLOCO 3 — "FOTO ANTES": contagem + impressão digital (md5) das tabelas
-- que esta RPC toca. ANOTE ESTE RESULTADO — compare com o mesmo bloco
-- rodado no FINAL (depois de toda a bateria de testes e do ROLLBACK/limpeza
-- de cada um): os 1.414 patrimônios/movimentações reais (e o Despacho 577)
-- nunca podem aparecer alterados aqui.
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as total,
       md5(coalesce(string_agg(t::text, '|' order by t.id), '')) as impressao
from public.patrimonios t
union all
select 'movimentacoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.movimentacoes t
union all
select 'patrimonio_comparacao_execucoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.operacao_id), ''))
from public.patrimonio_comparacao_execucoes t
union all
select 'documentos_sei_itens', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei_itens t
union all
select 'setores', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.setores t
union all
select 'localizacoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.localizacoes t
order by tabela;


-- -----------------------------------------------------------------------------
-- BLOCO 4 — sobras de uma tentativa anterior desta etapa (11.6.5). Esperado:
-- 0 em tudo. Se algo aparecer, NÃO prossiga: rode
-- `99_limpeza_homologacao.sql` primeiro.
-- -----------------------------------------------------------------------------
select 'patrimonio_comparacao_execucoes' as tabela, count(*) as sobras
from public.patrimonio_comparacao_execucoes
union all
select 'patrimonios (ZZHOMOLOG-11.6.5)', count(*)
from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-11.6.5%'
union all
select 'documentos_sei (ZZHOMOLOG-SEI-11.6.5)', count(*)
from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.6.5%';
