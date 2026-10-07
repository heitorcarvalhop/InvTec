-- InvTec — checklist PÓS-aplicação do módulo de usuários (Etapas 2-5)
--
-- SOMENTE SELECT. Nenhum INSERT/UPDATE/DELETE/DDL. Nunca aplicado
-- automaticamente — copie manualmente cada bloco para o SQL Editor do
-- Supabase DEPOIS de aplicar as 8 migrations, na ordem do rascunho de
-- plano manual (ver relatório). Compare contra a saída de
-- supabase/manual/pre_user_module_checks.sql.
--
-- NUNCA seleciona senha/token/dado sensível de auth.users — só
-- public.profiles e as tabelas novas do módulo.

-- =============================================================================
-- 1. CONTAGEM DE profiles PRESERVADA
-- =============================================================================
-- Tem que bater EXATAMENTE com o bloco 1 do pre-check. Nenhuma das 8
-- migrations faz INSERT/DELETE em profiles.
select count(*) as total_profiles
from public.profiles;

-- =============================================================================
-- 2. O(S) ADMIN(S) ANTERIOR(ES) CONTINUAM ADMIN/ATIVO/ACTIVE
-- =============================================================================
-- Compare os ids com o bloco 4 do pre-check: mesmo conjunto de ids, cada
-- um agora com perfil='ADMIN', ativo=true E access_status='ACTIVE'. Se
-- faltar alguma linha aqui que existia no pre-check, PARE — é o achado
-- mais crítico possível desta migração.
select id, nome, email, perfil, ativo, access_status, approved_at
from public.profiles
where perfil = 'ADMIN'
order by ativo desc, criado_em;

-- =============================================================================
-- 3. INVARIANTE ativo <-> access_status — ZERO VIOLAÇÕES ESPERADAS
-- =============================================================================
-- Mesmo que a constraint profiles_ativo_access_status_coerente já impeça
-- isso no banco, esta consulta é a confirmação INDEPENDENTE (lida os
-- dados, não confia só na constraint existir). Esperado: ZERO linhas nos
-- dois SELECTs. Qualquer linha aqui é uma violação grave da invariante
-- central do módulo.
select id, nome, ativo, access_status, 'ACTIVE com ativo=false' as problema
from public.profiles
where access_status = 'ACTIVE' and ativo is false
union all
select id, nome, ativo, access_status, 'PENDING/REJECTED/BLOCKED com ativo=true' as problema
from public.profiles
where access_status in ('PENDING', 'REJECTED', 'BLOCKED') and ativo is true;

-- =============================================================================
-- 4. BACKFILL DE access_status COERENTE COM O ativo ANTERIOR
-- =============================================================================
-- Reconstrói o que o backfill da migration 1 deveria ter produzido: toda
-- linha que era ativo=true deveria ter virado ACTIVE; toda ativo=false
-- deveria ter virado BLOCKED (nunca PENDING — PENDING é só para o DEFAULT
-- de contas novas, que nascem depois do backfill). Compare a soma de
-- "ACTIVE" aqui com a contagem de ativo=true do bloco 3 do pre-check, e a
-- soma de "BLOCKED" com a contagem de ativo=false do pre-check (a soma
-- pode ter crescido um pouco se novos cadastros PENDING entraram entre o
-- pre-check e agora).
select access_status, count(*) as qtd
from public.profiles
group by access_status
order by access_status;

-- =============================================================================
-- 5. CATÁLOGO permissions — CONTAGEM
-- =============================================================================
-- ACHADO DA REVISÃO: o pedido original presumia 13 chaves no catálogo,
-- mas a leitura direta de 20261006100000_add_permission_catalog.sql mostra
-- 14 INSERTs (patrimonio.view/create/edit/compare_update,
-- movimentacao.view/create, setor.view/manage, localizacao.view/manage,
-- tipo_patrimonio.view/manage, sei.view/manage). O valor correto esperado
-- aqui é 14, não 13 — ajuste suas expectativas e releia o catálogo se
-- este número divergir de 14.
select count(*) as total_permissions
from public.permissions;

select permission_key, modulo
from public.permissions
order by permission_key;

-- =============================================================================
-- 6. role_permissions POR PERFIL
-- =============================================================================
-- Esperado (contagem exata, lida diretamente do seed da migration 3):
--   ADMIN    = 14 (todas, incluindo patrimonio.compare_update)
--   GESTOR   = 13 (todas, EXCETO patrimonio.compare_update)
--   OPERADOR = 10 (view/create/edit de patrimônio+movimentação, view de
--                  setor/localização/tipo_patrimonio, sei.view E sei.manage)
--   CONSULTA = 6  (só as 6 chaves *.view)
--   TOTAL    = 43
select perfil, count(*) as qtd
from public.role_permissions
group by perfil
order by perfil;

-- Confirmação específica pedida na revisão: OPERADOR tem sei.view E
-- sei.manage (não só view). Esperado: 2 linhas.
select perfil, permission_key
from public.role_permissions
where perfil = 'OPERADOR' and permission_key in ('sei.view', 'sei.manage');

-- Confirmação específica pedida na revisão: patrimonio.compare_update é
-- ADMIN-only dentro do preset (a segunda trava real está no código da RPC
-- aplicar_decisao_comparacao_patrimonio, que exige has_perfil('ADMIN') +
-- has_permission — isto aqui confirma só o preset). Esperado: 1 linha.
select perfil, permission_key
from public.role_permissions
where permission_key = 'patrimonio.compare_update';

-- =============================================================================
-- 7. EXISTÊNCIA DAS TABELAS/FUNÇÕES/POLICIES ESSENCIAIS
-- =============================================================================
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('notifications', 'admin_audit_log', 'permissions',
                      'role_permissions', 'user_permissions')
order by table_name;

select routine_schema, routine_name
from information_schema.routines
where routine_schema in ('public', 'private')
  and routine_name in ('has_perfil', 'has_permission', 'minhas_permissoes',
                        'obter_permissoes_usuario', 'definir_permissao_usuario',
                        'remover_override_permissao_usuario',
                        'resetar_permissoes_usuario', 'aprovar_usuario',
                        'rejeitar_usuario', 'reenviar_solicitacao_acesso',
                        'alterar_identidade_usuario', 'bloquear_usuario',
                        'desbloquear_usuario', 'alterar_perfil_usuario',
                        'marcar_notificacao_lida', 'marcar_todas_notificacoes_lidas',
                        'is_valid_cpf', 'notify_admins_access_request',
                        'resolve_access_request_notifications',
                        'prevent_remove_last_active_admin')
order by routine_schema, routine_name;

select schemaname, tablename, policyname
from pg_policies
where schemaname = 'public'
  and tablename in ('profiles', 'permissions', 'role_permissions',
                     'user_permissions', 'notifications', 'admin_audit_log')
order by tablename, policyname;

-- =============================================================================
-- 8. PROFILES COM cpf IS NULL (ESPERADO = LEGADOS, NÃO É ERRO)
-- =============================================================================
-- Todo profile criado ANTES da migration 1 nunca forneceu CPF — fica
-- NULL indefinidamente (índice único é parcial, nulls nunca colidem). Não
-- é uma falha; é só para você ter a contagem de quantas contas precisarão
-- de alterar_identidade_usuario (ADMIN preenchendo o CPF) no futuro, se o
-- CPF vier a ser exigido para alguma ação administrativa.
select count(*) as profiles_sem_cpf
from public.profiles
where cpf is null;

-- =============================================================================
-- 9. notifications NASCE VAZIA (TABELA NOVA) + ESTRUTURA BÁSICA
-- =============================================================================
-- Esperado: ZERO linhas (nenhum evento de notificação pode ter sido
-- gerado antes de a tabela existir). Se houver qualquer linha aqui logo
-- após aplicar as migrations, investigue antes de seguir.
select count(*) as total_notifications
from public.notifications;

-- Estrutura básica (colunas esperadas, inclusive a UNIQUE da migration 7).
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'notifications'
order by ordinal_position;

select conname, contype
from pg_constraint
where conrelid = 'public.notifications'::regclass
  and conname = 'notifications_event_destinatario_unique';

-- =============================================================================
-- 10. publication supabase_realtime — profiles E notifications presentes
-- =============================================================================
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename in ('profiles', 'notifications');
