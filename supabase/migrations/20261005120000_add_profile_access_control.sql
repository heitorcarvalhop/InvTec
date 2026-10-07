-- InvTec — fundação de controle de acesso de usuários (Etapa 2)
--
-- Introduz o estado completo da conta (`access_status`: PENDING/ACTIVE/
-- REJECTED/BLOCKED), CPF único e validado, e a garantia server-side de que
-- apenas contas ACTIVE operam o sistema. NÃO cria UI, permissões granulares
-- ou notificações — isso é escopo de etapas futuras.
--
-- Convenções seguidas (mesmas da migration inicial):
-- * Toda função fixa `set search_path = ''` e referencia objetos com schema
--   explícito.
-- * Toda autorização passa por `private.has_perfil(...)` — nenhuma policy
--   nova lê `perfil`/`ativo`/`access_status` diretamente.
-- * CHECKs usam comparação direta (não `is not distinct from`) somente
--   depois que a coluna correspondente já é `NOT NULL` — nunca antes.
-- * Funções de uso interno (nunca endpoints RPC do Flutter) vivem em
--   `private`.
--
-- =============================================================================
-- 1. ENUM
-- =============================================================================
-- Segue o padrão de `perfil_usuario`/`patrimonio_status`: tipo nomeado
-- `<entidade>_<conceito>`, coluna nomeada só `<conceito>`.

create type public.profile_access_status as enum (
  'PENDING',
  'ACTIVE',
  'REJECTED',
  'BLOCKED'
);

-- =============================================================================
-- 2. NOVAS COLUNAS EM profiles
-- =============================================================================
-- `access_status` nasce NULLABLE de propósito — ver seção 3 (backfill
-- seguro). Nenhuma outra coluna nova aceita NULL de forma ambígua: `cpf`
-- pode ser NULL (usuário legado nunca forneceu), as demais são metadados de
-- aprovação/rejeição que só existem depois do evento correspondente.

alter table public.profiles add column cpf text;
alter table public.profiles add column access_status public.profile_access_status;
alter table public.profiles add column rejection_count integer not null default 0;
alter table public.profiles add column approved_at timestamptz;
alter table public.profiles add column approved_by uuid references public.profiles (id) on delete restrict;
alter table public.profiles add column rejected_reason text;
alter table public.profiles add column blocked_reason text;

-- `blocked_at`/`blocked_by` NÃO foram criados: `admin_audit_log` (próxima
-- migration) já registra ator + timestamp de todo `USER_BLOCKED`/
-- `USER_REJECTED` — duplicar esses dois campos em `profiles` só para evitar
-- um JOIN seria especulativo (nenhum consumidor desta etapa precisa disso
-- direto na linha de `profiles`).

comment on column public.profiles.cpf is
  'Somente dígitos (normalizado por trigger). NULL para contas legadas que nunca forneceram CPF — ver profiles_cpf_key (único parcial) e private.is_valid_cpf.';
comment on column public.profiles.access_status is
  'Estado completo da conta. Mantido coerente com `ativo` por profiles_ativo_access_status_coerente — nunca escrito fora das RPCs administrativas/handle_new_user.';
comment on column public.profiles.rejection_count is
  'Incrementado só por rejeitar_usuario. 3 rejeições → BLOCKED automático (ver profiles_rejection_count_coerente). Nunca zerado pelo próprio usuário.';

-- =============================================================================
-- 3. BACKFILL SEGURO + NOT NULL + DEFAULT
-- =============================================================================
-- NUNCA um DEFAULT cego: cada linha EXISTENTE recebe o status derivado do
-- seu próprio `ativo` atual, preservando exatamente o acesso que já tem.
-- `ativo=false` vira BLOCKED (não PENDING) — são contas já desativadas por
-- decisão administrativa anterior, não cadastros novos aguardando a
-- primeira análise. Só DEPOIS do backfill a coluna vira NOT NULL, e só
-- ENTÃO ganha um DEFAULT — que passa a valer para INSERTs futuros
-- (`handle_new_user`, seção 6), nunca para as linhas que já existiam.

update public.profiles
set access_status = case when ativo then 'ACTIVE' else 'BLOCKED' end
where access_status is null;

alter table public.profiles alter column access_status set not null;
alter table public.profiles alter column access_status set default 'PENDING';

-- =============================================================================
-- 4. INVARIANTE ativo ↔ access_status
-- =============================================================================
-- `ativo` é mantido por compatibilidade com o código Flutter atual (que só
-- lê esse campo hoje) — mas as duas colunas NUNCA podem divergir. Só é
-- seguro adicionar este CHECK agora, depois do backfill: antes disso,
-- linhas antigas com `access_status` ainda nulo violariam a constraint.
alter table public.profiles add constraint profiles_ativo_access_status_coerente
  check (
    (access_status = 'ACTIVE' and ativo is true)
    or (access_status in ('PENDING', 'REJECTED', 'BLOCKED') and ativo is false)
  );

-- Rede de segurança, não o mecanismo primário: a transição real (quem pode
-- rejeitar, quando o contador vira BLOCKED) acontece dentro de
-- `rejeitar_usuario` (próxima migration). Este CHECK só impede o par
-- impossível "3+ rejeições, mas não BLOCKED" de existir, mesmo sob um bug
-- futuro ou um UPDATE direto por engano.
alter table public.profiles add constraint profiles_rejection_count_coerente
  check (rejection_count < 3 or access_status = 'BLOCKED');

-- =============================================================================
-- 5. CPF — VALIDAÇÃO, NORMALIZAÇÃO E UNICIDADE
-- =============================================================================

-- Formato (11 dígitos) é barato e estrutural: fica em CHECK, igual às
-- outras normalizações do projeto. O ALGORITMO do dígito verificador NÃO é
-- um CHECK (ver private.is_valid_cpf abaixo) — CHECK é reservado para
-- invariantes estruturais simples; um CHECK aqui impediria até handle_new_user
-- de aceitar um CPF digitado errado (abortando o cadastro inteiro em vez de
-- deixar a aprovação administrativa pegar o erro — ver seção 6/7).
alter table public.profiles add constraint profiles_cpf_formato
  check (cpf is null or cpf ~ '^[0-9]{11}$');

-- Índice único PARCIAL (não UNIQUE simples): usuários legados ficam com
-- `cpf = NULL` indefinidamente (nunca forneceram), e múltiplos NULL nunca
-- devem colidir entre si. Garante no banco que dois cadastros simultâneos
-- com o mesmo CPF nunca os dois vencem — o segundo INSERT/UPDATE falha com
-- unique_violation.
create unique index profiles_cpf_key on public.profiles (cpf) where cpf is not null;

-- Normaliza para só dígitos ANTES do CHECK de formato avaliar (BEFORE
-- trigger). Nome começa com "normalize_" para disparar alfabeticamente
-- ANTES de "protect_columns"/"prevent_..."/"set_updated_at" na mesma
-- tabela — mesma convenção de `normalize_setor`/`normalize_patrimonio`.
create or replace function public.normalize_profile_cpf()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.cpf := nullif(regexp_replace(coalesce(new.cpf, ''), '[^0-9]', '', 'g'), '');
  return new;
end;
$$;

create trigger trg_profiles_normalize_cpf
  before insert or update of cpf on public.profiles
  for each row execute function public.normalize_profile_cpf();

-- Algoritmo oficial do CPF: rejeita formato errado (defesa redundante com o
-- CHECK, mas a função precisa ser independente/reusável), as 10 sequências
-- de dígito repetido (00000000000..99999999999) e dígitos verificadores
-- incorretos. IMMUTABLE: função pura, sem acesso a tabela.
--
-- Fica em `private` e NUNCA recebe GRANT de EXECUTE para `authenticated`
-- (ver seção 8) — só é chamável a partir de outra função SECURITY DEFINER
-- (que roda com o privilégio do dono do banco). Isso é deliberado: o
-- objetivo é nunca existir um endpoint tipo `cpf_existe(...)` que permita
-- enumerar/testar CPFs de fora.
create or replace function private.is_valid_cpf(p_cpf text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_digitos int[];
  v_soma int;
  v_digito1 int;
  v_digito2 int;
  v_i int;
begin
  if p_cpf is null or p_cpf !~ '^[0-9]{11}$' then
    return false;
  end if;

  -- sequências repetidas (00000000000, 11111111111, ..., 99999999999)
  if p_cpf ~ '^(\d)\1{10}$' then
    return false;
  end if;

  v_digitos := array(
    select substring(p_cpf from v_i for 1)::int
    from generate_series(1, 11) v_i
    order by v_i
  );

  v_soma := 0;
  for v_i in 1..9 loop
    v_soma := v_soma + v_digitos[v_i] * (11 - v_i);
  end loop;
  v_digito1 := 11 - (v_soma % 11);
  if v_digito1 >= 10 then
    v_digito1 := 0;
  end if;
  if v_digito1 <> v_digitos[10] then
    return false;
  end if;

  v_soma := 0;
  for v_i in 1..10 loop
    v_soma := v_soma + v_digitos[v_i] * (12 - v_i);
  end loop;
  v_digito2 := 11 - (v_soma % 11);
  if v_digito2 >= 10 then
    v_digito2 := 0;
  end if;
  if v_digito2 <> v_digitos[11] then
    return false;
  end if;

  return true;
end;
$$;

-- `is_valid_cpf` NÃO é função de trigger (retorna boolean, não `trigger`) —
-- diferente de `handle_new_user`/`prevent_remove_last_active_admin`
-- (protegidas automaticamente pelo mecanismo de trigger do Postgres, sem
-- precisar de revoke), esta precisa do `revoke` EXPLÍCITO abaixo, senão
-- herda EXECUTE de PUBLIC por padrão — e `authenticated` já tem `USAGE ON
-- SCHEMA private` (concedido na migration inicial, para `has_perfil`),
-- então sem este revoke o cliente poderia chamar `private.is_valid_cpf(cpf)`
-- diretamente e usá-la como um `cpf_existe(...)` de fato (mesmo só
-- retornando validade matemática, não existência — o padrão de timing/
-- resposta ainda vazaria informação). Mesmo padrão da migration inicial
-- (`revoke all on function private.has_perfil, ... from public, anon,
-- authenticated`).
revoke all on function private.is_valid_cpf(text) from public, anon, authenticated;

-- =============================================================================
-- 6. handle_new_user — PENDING por padrão, metadata de privilégio IGNORADA
-- =============================================================================
-- Reaproveita a MESMA trigger que já cria o profile hoje (AFTER INSERT ON
-- auth.users, mesma transação do signup) — nenhum mecanismo concorrente
-- novo. `nome`/`cpf` podem vir de `raw_user_meta_data` (dado de identidade,
-- fornecido pelo próprio usuário no formulário de cadastro); `perfil`,
-- `ativo`, `access_status` e `rejection_count` são sempre LITERAIS fixos no
-- INSERT — nunca lidos de `raw_user_meta_data` — então não existe chave de
-- metadata que um cliente possa enviar (`perfil`, `role`, `ativo`,
-- `access_status`, `rejection_count`, `approved_by` ou qualquer outra) capaz
-- de alterar o resultado: a função simplesmente nunca olha para essas
-- chaves. `cpf`, se vier malformado ou com dígito verificador inválido, é
-- aceito mesmo assim (só o FORMATO de 11 dígitos é um CHECK — ver seção 5);
-- a validação completa (`private.is_valid_cpf`) só bloqueia a APROVAÇÃO
-- (próxima migration), nunca a criação da conta — um erro de digitação no
-- cadastro não pode travar o usuário fora do sistema antes mesmo de existir.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nome, email, cpf, perfil, ativo, access_status, rejection_count)
  values (
    new.id,
    coalesce(
      public.normalize_text(new.raw_user_meta_data ->> 'nome'),
      new.email,
      new.id::text
    ),
    new.email,
    new.raw_user_meta_data ->> 'cpf',
    'CONSULTA',
    false,
    'PENDING',
    0
  );
  return new;
end;
$$;

-- =============================================================================
-- 7. private.has_perfil — agora exige access_status = ACTIVE
-- =============================================================================
-- Único helper de autorização do projeto: TODAS as policies de RLS e TODAS
-- as RPCs de escrita chamam só esta função (nenhuma lê `perfil`/`ativo`
-- diretamente) — por isso esta é a ÚNICA mudança necessária para que
-- PENDING/REJECTED/BLOCKED deixem de conseguir operar qualquer tabela de
-- negócio ou RPC existente. Nenhuma policy individual precisa ser tocada.
-- `ativo is true` e `access_status = 'ACTIVE'` são redundantes entre si
-- (garantido por profiles_ativo_access_status_coerente), mas mantidos
-- EXPLICITAMENTE os dois: é barato, e documenta a intenção sem depender
-- silenciosamente de uma constraint estar sempre em vigor.
create or replace function private.has_perfil(variadic p_perfis public.perfil_usuario[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.ativo is true
      and p.access_status = 'ACTIVE'
      and p.perfil = any (p_perfis)
  );
$$;

-- =============================================================================
-- 8. PROTEÇÃO DO ÚLTIMO ADMIN ACTIVE
-- =============================================================================
-- Garantia REAL (não só nas RPCs administrativas, que vêm na próxima
-- migration): nenhum UPDATE — nem futuro, nem feito por engano direto no
-- SQL Editor — consegue tirar o último ADMIN ACTIVE dessa condição.
--
-- Concorrência: `pg_advisory_xact_lock` (mesmo padrão de
-- `criar_documento_sei_pendente`/`aplicar_decisao_comparacao_patrimonio`)
-- serializa qualquer UPDATE concorrente que tire um ADMIN ACTIVE da
-- condição, chaveado por uma constante fixa (a invariante é GLOBAL — "existe
-- ao menos um ADMIN ACTIVE no sistema inteiro" — não por linha). Sem a
-- trava, duas transações concorrentes rebaixando dois admins diferentes
-- poderiam cada uma contar "ainda existe o outro" (ainda não commitado) e
-- as duas passarem, zerando os administradores.
create or replace function private.prevent_remove_last_active_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_era_admin_ativo boolean;
  v_continua_admin_ativo boolean;
  v_outros_admins_ativos integer;
begin
  v_era_admin_ativo := old.perfil = 'ADMIN' and old.access_status = 'ACTIVE';
  v_continua_admin_ativo := new.perfil = 'ADMIN' and new.access_status = 'ACTIVE';

  if v_era_admin_ativo and not v_continua_admin_ativo then
    perform pg_advisory_xact_lock(hashtextextended('last_active_admin_guard', 0));

    select count(*) into v_outros_admins_ativos
    from public.profiles
    where perfil = 'ADMIN' and access_status = 'ACTIVE' and id <> old.id;

    if v_outros_admins_ativos = 0 then
      raise exception 'Não é possível remover o último administrador ativo do sistema'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_profiles_prevent_remove_last_active_admin
  before update of perfil, access_status on public.profiles
  for each row execute function private.prevent_remove_last_active_admin();

-- =============================================================================
-- 9. protect_profile_columns — agora cobre TODAS as colunas sensíveis
-- =============================================================================
-- Antes só protegia id/email/perfil/ativo/criado_em (nome era gravável pelo
-- próprio usuário). Com a nova regra de identidade (seção 10 abaixo: NINGUÉM
-- edita a própria linha, nem nome/cpf, nem depois de REJECTED), a lista
-- cresce para cobrir TODA coluna que não seja gerida automaticamente por
-- trigger (`atualizado_em`, via set_updated_at). current_user só é
-- anon/authenticated vindo da API do cliente — dentro de uma RPC SECURITY
-- DEFINER (próxima migration) ou no SQL Editor, current_user é o dono do
-- banco, e esta trigger não interfere.
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated')
     and (
       new.id is distinct from old.id
       or new.email is distinct from old.email
       or new.nome is distinct from old.nome
       or new.cpf is distinct from old.cpf
       or new.perfil is distinct from old.perfil
       or new.ativo is distinct from old.ativo
       or new.access_status is distinct from old.access_status
       or new.rejection_count is distinct from old.rejection_count
       or new.approved_at is distinct from old.approved_at
       or new.approved_by is distinct from old.approved_by
       or new.rejected_reason is distinct from old.rejected_reason
       or new.blocked_reason is distinct from old.blocked_reason
       or new.criado_em is distinct from old.criado_em
     ) then
    raise exception 'profiles só pode ser alterado por fluxo administrativo (RPC)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- =============================================================================
-- 10. RLS/GRANTS DE profiles — identidade não é mais autoeditável
-- =============================================================================
-- Regra nova (substitui qualquer leitura anterior da auditoria): depois do
-- cadastro, NINGUÉM edita a própria linha — nem nome, nem cpf, nem email —
-- em NENHUM estado (PENDING/REJECTED/ACTIVE/BLOCKED). Toda mudança de
-- identidade passa por RPC administrativa (próxima migration), que gera
-- auditoria. Por isso: sem policy de UPDATE alguma em profiles, e sem GRANT
-- de UPDATE (nem mesmo da coluna nome) para `authenticated` — toda escrita
-- é feita pelas RPCs SECURITY DEFINER, que rodam como dono do banco e não
-- dependem de GRANT/RLS.
drop policy if exists profiles_update on public.profiles;
revoke update (nome) on public.profiles from authenticated;

-- SELECT: a própria linha continua SEMPRE visível — inclusive PENDING/
-- REJECTED/BLOCKED, que precisam poder ler o próprio access_status/
-- rejection_count/rejected_reason/blocked_reason para a futura tela
-- "Aguardando aprovação" (este branch NUNCA passou por has_perfil, então
-- não é afetado pela mudança da seção 7). ADMIN ACTIVE também vê todos, para
-- a futura tela de administração — GESTOR deixou de ver a lista completa
-- nesta revisão: todas as RPCs administrativas desta etapa são exclusivas de
-- ADMIN (seções 16-25 do pedido), então a visibilidade de SELECT foi
-- alinhada ao mesmo público, em vez de manter GESTOR com uma leitura sem
-- nenhuma ação correspondente.
-- PostgreSQL não tem `CREATE OR REPLACE POLICY` — a antiga é removida e
-- recriada com a nova condição.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.has_perfil('ADMIN'))
  );

-- sem policy de UPDATE (ver acima), sem INSERT (trigger handle_new_user) e
-- sem DELETE (usar access_status/ativo) — profiles nunca é apagado
-- (ON DELETE RESTRICT em auth.users, patrimonios.criado_por,
-- movimentacoes.realizado_por continuam intocados por esta migration).
