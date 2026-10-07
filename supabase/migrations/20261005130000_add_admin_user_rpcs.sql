-- InvTec — RPCs administrativas de usuários + admin_audit_log (Etapa 2)
--
-- Depende da migration anterior (20261005120000_add_profile_access_control):
-- access_status, cpf, rejection_count, private.is_valid_cpf,
-- private.has_perfil já atualizado e o trigger de proteção do último ADMIN
-- já existem quando este arquivo roda.
--
-- Todas as 7 funções abaixo são o ÚNICO caminho de escrita administrativa em
-- profiles (não há GRANT de UPDATE para `authenticated` — ver migration
-- anterior, seção 10). Cada uma: valida ADMIN ACTIVE (exceto
-- reenviar_solicitacao_acesso, self-service), valida entrada, trava a linha
-- alvo (`for update`), aplica a mudança e grava auditoria NA MESMA
-- TRANSAÇÃO — ou tudo acontece, ou nada.

-- =============================================================================
-- 1. admin_audit_log — trilha de auditoria IMUTÁVEL
-- =============================================================================
-- Mesmo padrão de `documentos_sei_eventos`: append-only, sem UPDATE/DELETE
-- concedido a ninguém (nem às próprias funções desta migration, que só
-- fazem INSERT). `acao` é `text` LIVRE (não enum, não CHECK de lista
-- fechada) — de propósito: novas ações administrativas no futuro (Etapa 3+:
-- permissões granulares, Etapa 4: notificações) não devem exigir uma
-- migration só para ampliar uma lista fechada. As ações mínimas desta etapa
-- estão documentadas no comment da coluna.
create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  -- ATOR: quem executou a ação — um ADMIN, OU o próprio usuário quando a
  -- ação é o reenvio self-service (ator_id = alvo_id nesse caso).
  ator_id uuid not null references public.profiles (id) on delete restrict,
  -- ALVO: usuário afetado pela ação.
  alvo_id uuid not null references public.profiles (id) on delete restrict,
  acao text not null,
  motivo text,
  dados_antes jsonb,
  dados_depois jsonb,
  criado_em timestamptz not null default now()
);

comment on column public.admin_audit_log.acao is
  'Texto livre. Mínimo desta etapa: USER_APPROVED, USER_REJECTED, ACCESS_RESUBMITTED, USER_BLOCKED, USER_UNBLOCKED, USER_ROLE_CHANGED, USER_NAME_CHANGED, USER_CPF_CHANGED.';

comment on table public.admin_audit_log is
  'Auditoria administrativa imutável. NUNCA contém senha, token ou credencial — só os campos de negócio relevantes (dados_antes/depois são jsonb de colunas de profiles, nunca de auth.users).';

create index admin_audit_log_alvo_idx on public.admin_audit_log (alvo_id, criado_em desc);
create index admin_audit_log_ator_idx on public.admin_audit_log (ator_id, criado_em desc);

alter table public.admin_audit_log enable row level security;

create policy admin_audit_log_select on public.admin_audit_log
  for select to authenticated
  using ((select private.has_perfil('ADMIN')));

-- sem INSERT/UPDATE/DELETE policy: escrita só pelas 7 funções abaixo
-- (SECURITY DEFINER, rodam como dono do banco).

revoke all on table public.admin_audit_log from public, anon, authenticated;
grant select on public.admin_audit_log to authenticated;

-- =============================================================================
-- 2. aprovar_usuario
-- =============================================================================
create or replace function public.aprovar_usuario(
  p_user_id uuid,
  p_perfil public.perfil_usuario
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem aprovar usuários' using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Um administrador não pode aprovar a própria solicitação' using errcode = 'P0001';
  end if;
  if p_perfil is null then
    raise exception 'Perfil é obrigatório' using errcode = 'P0001';
  end if;

  select * into v_antes from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  if v_antes.access_status <> 'PENDING' then
    raise exception 'Usuário não está com solicitação pendente (status atual: %)', v_antes.access_status
      using errcode = 'P0001';
  end if;

  if v_antes.cpf is null or private.is_valid_cpf(v_antes.cpf) is not true then
    raise exception 'Não é possível aprovar um usuário sem CPF válido cadastrado' using errcode = 'P0001';
  end if;

  update public.profiles
  set access_status = 'ACTIVE',
      ativo = true,
      perfil = p_perfil,
      approved_at = now(),
      approved_by = auth.uid(),
      rejected_reason = null,
      blocked_reason = null
  where id = p_user_id
  returning * into v_depois;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id, 'USER_APPROVED',
    jsonb_build_object('access_status', v_antes.access_status, 'perfil', v_antes.perfil),
    jsonb_build_object('access_status', v_depois.access_status, 'perfil', v_depois.perfil, 'approved_by', v_depois.approved_by)
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 3. rejeitar_usuario
-- =============================================================================
create or replace function public.rejeitar_usuario(
  p_user_id uuid,
  p_motivo text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
  v_motivo text := public.normalize_text(p_motivo);
  v_novo_status public.profile_access_status;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem rejeitar usuários' using errcode = '42501';
  end if;

  if v_motivo is null then
    raise exception 'Motivo da rejeição é obrigatório' using errcode = 'P0001';
  end if;

  select * into v_antes from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  if v_antes.access_status <> 'PENDING' then
    raise exception 'Usuário não está com solicitação pendente (status atual: %)', v_antes.access_status
      using errcode = 'P0001';
  end if;

  -- 3ª rejeição (ou mais) → BLOCKED automático. A RPC decide o status
  -- resultante atomicamente junto com o incremento — profiles_rejection_count_coerente
  -- (migration anterior) é só a rede de segurança, nunca o mecanismo primário.
  v_novo_status := case when v_antes.rejection_count + 1 >= 3 then 'BLOCKED' else 'REJECTED' end;

  update public.profiles
  set access_status = v_novo_status,
      ativo = false,
      rejection_count = v_antes.rejection_count + 1,
      rejected_reason = v_motivo,
      -- quando o bloqueio é consequência da 3ª rejeição, blocked_reason
      -- reaproveita o mesmo motivo (não há um segundo motivo distinto a
      -- pedir) — para a conta BLOCKED já nascer com uma explicação visível.
      blocked_reason = case when v_novo_status = 'BLOCKED' then v_motivo else blocked_reason end
  where id = p_user_id
  returning * into v_depois;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, motivo, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id, 'USER_REJECTED', v_motivo,
    jsonb_build_object('access_status', v_antes.access_status, 'rejection_count', v_antes.rejection_count),
    jsonb_build_object('access_status', v_depois.access_status, 'rejection_count', v_depois.rejection_count)
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 4. reenviar_solicitacao_acesso — self-service, SEM user_id do cliente
-- =============================================================================
-- Nunca recebe nome/cpf/email: o usuário não pode trocar a própria
-- identidade reenviando a solicitação (bypass explicitamente vedado).
-- Também não zera rejection_count — só uma RPC administrativa
-- (desbloquear_usuario) zera, e só no caso descrito nela.
create or replace function public.reenviar_solicitacao_acesso()
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
begin
  select * into v_antes from public.profiles where id = auth.uid() for update;
  if not found then
    raise exception 'Perfil não encontrado' using errcode = 'P0002';
  end if;

  if v_antes.access_status <> 'REJECTED' then
    raise exception 'Só é possível reenviar uma solicitação rejeitada (status atual: %)', v_antes.access_status
      using errcode = 'P0001';
  end if;
  if v_antes.rejection_count >= 3 then
    raise exception 'Limite de rejeições atingido — não é possível reenviar' using errcode = 'P0001';
  end if;

  update public.profiles
  set access_status = 'PENDING'
  where id = auth.uid()
  returning * into v_depois;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
  values (
    auth.uid(), auth.uid(), 'ACCESS_RESUBMITTED',
    jsonb_build_object('access_status', v_antes.access_status, 'rejection_count', v_antes.rejection_count),
    jsonb_build_object('access_status', v_depois.access_status, 'rejection_count', v_depois.rejection_count)
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 5. alterar_identidade_usuario — ADMIN corrige nome/cpf
-- =============================================================================
-- Uma RPC só para nome+cpf (não duas): o admin sempre informa a identidade
-- completa resultante, o que mantém dados_antes/dados_depois simples e
-- evita ambiguidade de "campo omitido = não mexer" vs. "campo omitido =
-- limpar". Motivo é SEMPRE obrigatório (preferência explícita do pedido
-- para CPF, estendida a nome pela mesma RPC). Grava uma linha de auditoria
-- POR CAMPO que realmente mudou (USER_NAME_CHANGED / USER_CPF_CHANGED) —
-- não dispara nenhuma se o admin reenviar os mesmos valores (idempotente).
-- E-mail NÃO entra aqui — fora de escopo desta etapa (seção 22 do pedido).
create or replace function public.alterar_identidade_usuario(
  p_user_id uuid,
  p_novo_nome text,
  p_novo_cpf text,
  p_motivo text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
  v_nome text := public.normalize_text(p_novo_nome);
  v_cpf text := nullif(regexp_replace(coalesce(p_novo_cpf, ''), '[^0-9]', '', 'g'), '');
  v_motivo text := public.normalize_text(p_motivo);
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem alterar nome/CPF de outro usuário' using errcode = '42501';
  end if;

  if v_nome is null then
    raise exception 'Nome é obrigatório' using errcode = 'P0001';
  end if;
  if v_motivo is null then
    raise exception 'Motivo é obrigatório' using errcode = 'P0001';
  end if;
  -- CPF é sempre exigido aqui (nunca aceita NULL) — esta RPC é para
  -- CORRIGIR identidade, não para apagar um CPF já cadastrado. Sem esta
  -- checagem, um ADMIN conseguiria zerar o CPF de uma conta já ACTIVE,
  -- quebrando silenciosamente a invariante "toda conta ACTIVE aprovada
  -- tinha CPF válido no momento da aprovação" (aprovar_usuario exige CPF
  -- válido só NAQUELE momento, não é revalidado depois).
  if v_cpf is null or private.is_valid_cpf(v_cpf) is not true then
    raise exception 'CPF inválido' using errcode = 'P0001';
  end if;

  select * into v_antes from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  if v_cpf is not null and exists (
    select 1 from public.profiles where cpf = v_cpf and id <> p_user_id
  ) then
    raise exception 'CPF já está em uso por outro usuário' using errcode = 'P0021';
  end if;

  update public.profiles
  set nome = v_nome,
      cpf = v_cpf
  where id = p_user_id
  returning * into v_depois;

  if v_depois.nome is distinct from v_antes.nome then
    insert into public.admin_audit_log (ator_id, alvo_id, acao, motivo, dados_antes, dados_depois)
    values (auth.uid(), p_user_id, 'USER_NAME_CHANGED', v_motivo,
      jsonb_build_object('nome', v_antes.nome), jsonb_build_object('nome', v_depois.nome));
  end if;

  if v_depois.cpf is distinct from v_antes.cpf then
    insert into public.admin_audit_log (ator_id, alvo_id, acao, motivo, dados_antes, dados_depois)
    values (auth.uid(), p_user_id, 'USER_CPF_CHANGED', v_motivo,
      jsonb_build_object('cpf', v_antes.cpf), jsonb_build_object('cpf', v_depois.cpf));
  end if;

  return v_depois;
end;
$$;

-- =============================================================================
-- 6. bloquear_usuario
-- =============================================================================
create or replace function public.bloquear_usuario(
  p_user_id uuid,
  p_motivo text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
  v_motivo text := public.normalize_text(p_motivo);
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem bloquear usuários' using errcode = '42501';
  end if;
  if v_motivo is null then
    raise exception 'Motivo do bloqueio é obrigatório' using errcode = 'P0001';
  end if;

  select * into v_antes from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  if v_antes.access_status = 'BLOCKED' then
    raise exception 'Usuário já está bloqueado' using errcode = 'P0001';
  end if;

  -- Se o alvo for o último ADMIN ACTIVE, o UPDATE abaixo é abortado pela
  -- trigger trg_profiles_prevent_remove_last_active_admin (dispara porque
  -- access_status muda) — nenhuma checagem duplicada aqui, para a regra
  -- nunca divergir entre a RPC e a garantia real no banco.
  update public.profiles
  set access_status = 'BLOCKED',
      ativo = false,
      blocked_reason = v_motivo
  where id = p_user_id
  returning * into v_depois;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, motivo, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id, 'USER_BLOCKED', v_motivo,
    jsonb_build_object('access_status', v_antes.access_status, 'ativo', v_antes.ativo),
    jsonb_build_object('access_status', v_depois.access_status, 'ativo', v_depois.ativo)
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 7. desbloquear_usuario
-- =============================================================================
-- Dois caminhos, nunca ambíguos: já foi aprovado alguma vez (approved_at
-- preenchido) → restaura ACTIVE com o perfil que já tinha. Nunca foi
-- aprovado (bloqueado pelas 3 rejeições, approved_at ainda nulo) → volta
-- para PENDING com o contador ZERADO, para uma nova análise do zero.
create or replace function public.desbloquear_usuario(
  p_user_id uuid
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem desbloquear usuários' using errcode = '42501';
  end if;

  select * into v_antes from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  if v_antes.access_status <> 'BLOCKED' then
    raise exception 'Usuário não está bloqueado (status atual: %)', v_antes.access_status
      using errcode = 'P0001';
  end if;

  if v_antes.approved_at is not null then
    update public.profiles
    set access_status = 'ACTIVE',
        ativo = true,
        blocked_reason = null
    where id = p_user_id
    returning * into v_depois;
  else
    update public.profiles
    set access_status = 'PENDING',
        ativo = false,
        rejection_count = 0,
        rejected_reason = null,
        blocked_reason = null
    where id = p_user_id
    returning * into v_depois;
  end if;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id, 'USER_UNBLOCKED',
    jsonb_build_object('access_status', v_antes.access_status, 'rejection_count', v_antes.rejection_count, 'approved_at', v_antes.approved_at),
    jsonb_build_object('access_status', v_depois.access_status, 'rejection_count', v_depois.rejection_count)
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 8. alterar_perfil_usuario
-- =============================================================================
create or replace function public.alterar_perfil_usuario(
  p_user_id uuid,
  p_novo_perfil public.perfil_usuario
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_antes public.profiles;
  v_depois public.profiles;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem alterar o perfil de um usuário' using errcode = '42501';
  end if;
  if p_novo_perfil is null then
    raise exception 'Perfil é obrigatório' using errcode = 'P0001';
  end if;

  select * into v_antes from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  if v_antes.perfil = p_novo_perfil then
    return v_antes;
  end if;

  -- Se isto tirar o último ADMIN ACTIVE do papel ADMIN, a trigger
  -- trg_profiles_prevent_remove_last_active_admin aborta o UPDATE.
  update public.profiles
  set perfil = p_novo_perfil
  where id = p_user_id
  returning * into v_depois;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id, 'USER_ROLE_CHANGED',
    jsonb_build_object('perfil', v_antes.perfil),
    jsonb_build_object('perfil', v_depois.perfil)
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 9. GRANTS
-- =============================================================================
-- `private.is_valid_cpf` não recebe EXECUTE nenhum (ver seção 5 da migration
-- anterior) — chamada só de dentro destas funções SECURITY DEFINER, que
-- rodam como dono do banco.
revoke all on function
  public.aprovar_usuario,
  public.rejeitar_usuario,
  public.reenviar_solicitacao_acesso,
  public.alterar_identidade_usuario,
  public.bloquear_usuario,
  public.desbloquear_usuario,
  public.alterar_perfil_usuario
from public, anon, authenticated;

grant execute on function public.aprovar_usuario to authenticated;
grant execute on function public.rejeitar_usuario to authenticated;
grant execute on function public.reenviar_solicitacao_acesso to authenticated;
grant execute on function public.alterar_identidade_usuario to authenticated;
grant execute on function public.bloquear_usuario to authenticated;
grant execute on function public.desbloquear_usuario to authenticated;
grant execute on function public.alterar_perfil_usuario to authenticated;

-- A checagem `has_perfil('ADMIN')` dentro de cada função é a autorização
-- real — o GRANT a `authenticated` é só a primeira camada (mesmo padrão já
-- usado em `cadastrar_patrimonio`/`registrar_movimentacao`/as 4 funções de
-- documentos_sei_pendente): CONSULTA/OPERADOR/GESTOR têm EXECUTE, mas toda
-- chamada real falha com 42501 se quem chama não for ADMIN ACTIVE — exceto
-- `reenviar_solicitacao_acesso`, que é intencionalmente self-service (sem
-- checagem de perfil, qualquer autenticado reenvia a PRÓPRIA solicitação).
