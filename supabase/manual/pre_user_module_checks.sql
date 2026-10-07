-- InvTec — checklist PRÉ-aplicação do módulo de usuários (Etapas 2-5)
--
-- SOMENTE SELECT. Nenhum INSERT/UPDATE/DELETE/DDL. Nunca aplicado
-- automaticamente — copie manualmente cada bloco para o SQL Editor do
-- Supabase ANTES de colar a primeira migration nova
-- (20261005120000_add_profile_access_control.sql).
--
-- Objetivo: fotografar o estado real do banco (profiles/patrimonios/
-- movimentacoes) para comparar com supabase/manual/post_user_module_checks.sql
-- depois de aplicar as 8 migrations. Guarde a saída de cada bloco (ex.:
-- cole em um arquivo de texto ou print da tela) — o post-check depende de
-- comparar contra estes números.

-- =============================================================================
-- 1. TOTAL DE PROFILES
-- =============================================================================
-- Baseline de contagem total. Depois das 8 migrations este número tem que
-- ser EXATAMENTE igual — nenhuma delas faz INSERT/DELETE em profiles.
select count(*) as total_profiles
from public.profiles;

-- =============================================================================
-- 2. DISTRIBUIÇÃO POR perfil
-- =============================================================================
-- Nenhuma das 8 migrations muda `perfil` de ninguém (só adiciona colunas e
-- RPCs) — esta distribuição também tem que se manter idêntica depois.
select perfil, count(*) as qtd
from public.profiles
group by perfil
order by perfil;

-- =============================================================================
-- 3. DISTRIBUIÇÃO POR ativo
-- =============================================================================
-- Base para validar o backfill de access_status da migration 1
-- (ativo=true -> ACTIVE, ativo=false -> BLOCKED). Guarde os dois números.
select ativo, count(*) as qtd
from public.profiles
group by ativo
order by ativo;

-- =============================================================================
-- 4. ADMINS ATUAIS E SEU STATUS ativo
-- =============================================================================
-- O(s) ADMIN(s) listado(s) aqui são o que SEÇÃO C do plano de revisão
-- precisa continuar existindo, com o MESMO id, perfil=ADMIN, ativo=true,
-- depois das 8 migrations (e access_status=ACTIVE, que ainda não existe
-- nesta foto). Se mais de uma linha aparecer com ativo=true, confirme que
-- a trigger de proteção do último admin (criada na migration 1) não é o
-- único motivo para tranquilidade — ela só impede REMOVER o último, nunca
-- protege contra múltiplos admins ativos hoje (o que é normal).
select id, nome, email, perfil, ativo, criado_em
from public.profiles
where perfil = 'ADMIN'
order by ativo desc, criado_em;

-- =============================================================================
-- 5. A COLUNA cpf JÁ EXISTE POR ACASO? (NÃO DEVERIA)
-- =============================================================================
-- Esperado: ZERO linhas. Se aparecer alguma linha aqui, a migration 1
-- (que faz `alter table public.profiles add column cpf text`) vai falhar
-- com "column already exists" — pare e investigue antes de aplicar.
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'profiles'
  and column_name in ('cpf', 'access_status', 'rejection_count', 'approved_at',
                       'approved_by', 'rejected_reason', 'blocked_reason');

-- =============================================================================
-- 6. VOLUME DE FK PARA profiles (noção de impacto / tempo de migração)
-- =============================================================================
-- Nenhuma das 8 migrations faz ALTER/UPDATE em patrimonios ou movimentacoes,
-- mas esta contagem dá a escala real de dados que dependem de
-- profiles.id (criado_por / realizado_por) permanecer estável — útil para
-- estimar o tempo de uma eventual auditoria manual pós-migração.
select
  (select count(*) from public.patrimonios) as total_patrimonios,
  (select count(*) from public.movimentacoes) as total_movimentacoes,
  (select count(distinct criado_por) from public.patrimonios) as profiles_distintos_como_criado_por,
  (select count(distinct realizado_por) from public.movimentacoes) as profiles_distintos_como_realizado_por;

-- =============================================================================
-- 7. NOTIFICATIONS / ADMIN_AUDIT_LOG JÁ EXISTEM? (NÃO DEVERIAM)
-- =============================================================================
-- Esperado: ZERO linhas. Confirma que as migrations 2 e 6 (que criam
-- admin_audit_log e notifications) ainda não foram aplicadas neste banco.
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('admin_audit_log', 'notifications', 'permissions',
                      'role_permissions', 'user_permissions');
