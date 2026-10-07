-- InvTec — catálogo de permissões granulares + presets por perfil (Etapa 3)
--
-- Modelo: PERFIL BASE (preset) + OVERRIDE INDIVIDUAL. Os quatro perfis
-- (ADMIN/GESTOR/OPERADOR/CONSULTA) continuam existindo e continuam sendo a
-- fonte de autorização ESTRUTURAL/administrativa (private.has_perfil, usada
-- pelas RPCs de usuários da Etapa 2). Esta migration só introduz a tabela de
-- CAPACIDADES DE NEGÓCIO — a próxima (20261006110000) cria o helper de
-- leitura (private.has_permission) e as RPCs de gerenciamento; a seguinte
-- (20261006120000) migra as policies/RPCs de negócio existentes para usá-lo.
--
-- Convenções seguidas (mesmas das migrations anteriores):
-- * Toda função fixa `set search_path = ''` e referencia objetos com schema
--   explícito.
-- * CHECKs ficam reservados para invariantes estruturais simples.
-- * `private` é só para funções de uso interno (nunca endpoints RPC).

-- =============================================================================
-- 1. CATÁLOGO — public.permissions
-- =============================================================================
-- Fonte central das chaves válidas. `permission_key` segue a convenção
-- `modulo.acao` (ver comentário da coluna). Nenhuma RPC de override aceita
-- uma chave que não esteja aqui — ver private.has_permission e
-- definir_permissao_usuario (próxima migration): ausência na tabela =
-- permissão inexistente = sempre nega (fail closed).
--
-- Catálogo MÍNIMO: mapeia 1:1 as capacidades de negócio reais já auditadas
-- no Flutter (canManage de Patrimônios/Movimentações/Setores/Localizações,
-- podeGerenciar de SEI, o toggle "Comparar e Atualizar (ADMIN)") e as
-- policies/RPCs já existentes no banco desde a migration inicial — nenhuma
-- chave nova "hipergranular" (tipo botão/diálogo) foi inventada.
create table public.permissions (
  permission_key text primary key,
  modulo text not null,
  descricao text not null,
  criado_em timestamptz not null default now(),
  constraint permissions_key_formato check (permission_key ~ '^[a-z_]+\.[a-z_]+$')
);

comment on column public.permissions.permission_key is
  'Convenção modulo.acao (ex.: patrimonio.create). Representa CAPACIDADE DE NEGÓCIO, nunca detalhe de UI (nada de button_click/dialog_open).';

insert into public.permissions (permission_key, modulo, descricao) values
  ('patrimonio.view', 'patrimonio', 'Visualizar patrimônios'),
  ('patrimonio.create', 'patrimonio', 'Cadastrar novo patrimônio (inclui importação de planilha convencional)'),
  ('patrimonio.edit', 'patrimonio', 'Editar metadados de um patrimônio existente e registrar movimentações'),
  ('patrimonio.compare_update', 'patrimonio', 'Executar e aplicar decisões de "Comparar e Atualizar" (importação administrativa). Operação crítica: ver seção de RLS/RPCs sobre a dupla trava ADMIN + permissão'),
  ('movimentacao.view', 'movimentacao', 'Visualizar histórico de movimentações'),
  ('movimentacao.create', 'movimentacao', 'Registrar movimentação de um patrimônio já cadastrado'),
  ('setor.view', 'setor', 'Visualizar setores'),
  ('setor.manage', 'setor', 'Criar/editar/ativar-desativar setores'),
  ('localizacao.view', 'localizacao', 'Visualizar localizações'),
  ('localizacao.manage', 'localizacao', 'Criar/editar/ativar-desativar localizações'),
  ('tipo_patrimonio.view', 'tipo_patrimonio', 'Visualizar tipos de patrimônio'),
  ('tipo_patrimonio.manage', 'tipo_patrimonio', 'Criar/editar/ativar-desativar tipos de patrimônio (sem tela própria no Flutter ainda)'),
  ('sei.view', 'sei', 'Visualizar documentos SEI e seus itens/eventos'),
  ('sei.manage', 'sei', 'Criar/editar/cancelar/concluir (individual ou em lote) documentos SEI pendentes');

alter table public.permissions enable row level security;

-- Leitura: qualquer autenticado ACTIVE (a futura UI de administração precisa
-- listar as chaves disponíveis para montar a tela de overrides). Sem
-- nenhuma escrita client-side — o catálogo só muda por migration.
create policy permissions_select on public.permissions
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

revoke all on table public.permissions from public, anon, authenticated;
grant select on table public.permissions to authenticated;

-- =============================================================================
-- 2. PRESETS — public.role_permissions
-- =============================================================================
-- Permissões PADRÃO de cada perfil. Presença da linha = perfil tem a
-- permissão por padrão; ausência = não tem. Sem JSONB (pedido explícito):
-- uma linha por par (perfil, permission_key).
create table public.role_permissions (
  perfil public.perfil_usuario not null,
  permission_key text not null references public.permissions (permission_key) on delete restrict,
  primary key (perfil, permission_key)
);

alter table public.role_permissions enable row level security;

create policy role_permissions_select on public.role_permissions
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

-- sem INSERT/UPDATE/DELETE policy: o preset por perfil é dado de
-- configuração do produto, não um dado administrável pela UI nesta etapa —
-- muda só por migration (evita um ADMIN alterar o PADRÃO do perfil OPERADOR
-- inteiro por engano, confundindo com um override individual).
revoke all on table public.role_permissions from public, anon, authenticated;
grant select on table public.role_permissions to authenticated;

-- =============================================================================
-- 3. SEED — reproduz EXATAMENTE o comportamento atual do InvTec
-- =============================================================================
-- Fonte: policies/RPCs já existentes (migrations 20260910120000 em diante) +
-- auditoria do agente auth-permissoes sobre os pontos `canManage`/
-- `podeGerenciar` do Flutter. Depois desta migration, um usuário SEM
-- nenhum override precisa continuar fazendo exatamente o que já fazia.
insert into public.role_permissions (perfil, permission_key) values
  -- ADMIN: tudo, incluindo a operação crítica compare_update.
  ('ADMIN', 'patrimonio.view'),
  ('ADMIN', 'patrimonio.create'),
  ('ADMIN', 'patrimonio.edit'),
  ('ADMIN', 'patrimonio.compare_update'),
  ('ADMIN', 'movimentacao.view'),
  ('ADMIN', 'movimentacao.create'),
  ('ADMIN', 'setor.view'),
  ('ADMIN', 'setor.manage'),
  ('ADMIN', 'localizacao.view'),
  ('ADMIN', 'localizacao.manage'),
  ('ADMIN', 'tipo_patrimonio.view'),
  ('ADMIN', 'tipo_patrimonio.manage'),
  ('ADMIN', 'sei.view'),
  ('ADMIN', 'sei.manage'),

  -- GESTOR: tudo, EXCETO patrimonio.compare_update (sempre foi ADMIN puro).
  ('GESTOR', 'patrimonio.view'),
  ('GESTOR', 'patrimonio.create'),
  ('GESTOR', 'patrimonio.edit'),
  ('GESTOR', 'movimentacao.view'),
  ('GESTOR', 'movimentacao.create'),
  ('GESTOR', 'setor.view'),
  ('GESTOR', 'setor.manage'),
  ('GESTOR', 'localizacao.view'),
  ('GESTOR', 'localizacao.manage'),
  ('GESTOR', 'tipo_patrimonio.view'),
  ('GESTOR', 'tipo_patrimonio.manage'),
  ('GESTOR', 'sei.view'),
  ('GESTOR', 'sei.manage'),

  -- OPERADOR: view/create/edit de patrimônio+movimentação+SEI, mas NUNCA
  -- setor.manage/localizacao.manage/tipo_patrimonio.manage (hoje só
  -- ADMIN/GESTOR) nem patrimonio.compare_update.
  ('OPERADOR', 'patrimonio.view'),
  ('OPERADOR', 'patrimonio.create'),
  ('OPERADOR', 'patrimonio.edit'),
  ('OPERADOR', 'movimentacao.view'),
  ('OPERADOR', 'movimentacao.create'),
  ('OPERADOR', 'setor.view'),
  ('OPERADOR', 'localizacao.view'),
  ('OPERADOR', 'tipo_patrimonio.view'),
  ('OPERADOR', 'sei.view'),
  ('OPERADOR', 'sei.manage'),

  -- CONSULTA: somente leitura, em tudo.
  ('CONSULTA', 'patrimonio.view'),
  ('CONSULTA', 'movimentacao.view'),
  ('CONSULTA', 'setor.view'),
  ('CONSULTA', 'localizacao.view'),
  ('CONSULTA', 'tipo_patrimonio.view'),
  ('CONSULTA', 'sei.view');

-- =============================================================================
-- 4. OVERRIDES INDIVIDUAIS — public.user_permissions
-- =============================================================================
-- Semântica de TRÊS estados, por (usuário, permission_key):
--   * SEM LINHA        -> HERDA o padrão do perfil (role_permissions).
--   * granted = true   -> PERMITE, mesmo que o perfil base não tenha.
--   * granted = false  -> NEGA, mesmo que o perfil base tenha.
-- `granted` é NOT NULL de propósito: a ausência de override é modelada pela
-- AUSÊNCIA DA LINHA, nunca por um valor NULL na coluna — um
-- `definir_permissao_usuario(..., granted => null)` deve falhar na RPC
-- (próxima migration), nunca criar uma linha ambígua aqui.
create table public.user_permissions (
  user_id uuid not null references public.profiles (id) on delete restrict,
  permission_key text not null references public.permissions (permission_key) on delete restrict,
  granted boolean not null,
  concedido_por uuid not null references public.profiles (id) on delete restrict,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (user_id, permission_key)
);

comment on table public.user_permissions is
  'Overrides individuais explícitos. Semântica de 3 estados — ver comentário acima da tabela na migration 20261006100000. Escrita só via RPCs administrativas (próxima migration); nunca GRANT direto a authenticated.';

-- mesmo padrão de updated_em das outras tabelas do projeto (trigger
-- dedicada, nome começando com "set_" para disparar depois de qualquer
-- normalização — aqui não há nenhuma, mas mantém a convenção).
create or replace function public.set_updated_at_user_permissions()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger trg_user_permissions_set_updated_at
  before update on public.user_permissions
  for each row execute function public.set_updated_at_user_permissions();

-- `returns trigger` já impede chamada direta via SQL ("trigger functions
-- can only be called as triggers") — mas o `revoke` explícito é mantido por
-- disciplina/consistência: TODA função do projeto, mesmo as de trigger
-- (`set_updated_at`, `normalize_setor`, `protect_profile_columns`...), recebe
-- este revoke na migration onde nasce.
revoke all on function public.set_updated_at_user_permissions() from public, anon, authenticated;

alter table public.user_permissions enable row level security;

-- Leitura: só ADMIN (a futura tela de administração de overrides). O
-- usuário comum NUNCA precisa ler os próprios overrides crus — consulta
-- pela RPC minhas_permissoes() (próxima migration), que já devolve o
-- resultado EFETIVO (perfil + override resolvidos), sem expor a mecânica
-- interna nem os overrides de outros usuários.
create policy user_permissions_select on public.user_permissions
  for select to authenticated
  using ((select private.has_perfil('ADMIN')));

-- sem INSERT/UPDATE/DELETE policy: escrita só pelas RPCs
-- definir_permissao_usuario / remover_override_permissao_usuario /
-- resetar_permissoes_usuario (SECURITY DEFINER, próxima migration) — mesmo
-- padrão de profiles desde a Etapa 2 (zero GRANT de escrita direta a
-- `authenticated`, para toda mudança gerar auditoria).
revoke all on table public.user_permissions from public, anon, authenticated;
grant select on table public.user_permissions to authenticated;

create index user_permissions_user_idx on public.user_permissions (user_id);

-- Índice de performance citado no pedido (seção 11): já coberto pela PK
-- (user_id, permission_key) e por (perfil, permission_key) em
-- role_permissions — nenhum índice extra é necessário além deles e do
-- índice explícito acima (útil para "todos os overrides de um usuário",
-- que a PK sozinha já serve, mas um índice dedicado documenta a intenção e
-- é redundante-mas-barato).
