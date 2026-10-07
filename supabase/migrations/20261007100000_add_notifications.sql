-- InvTec — notificações internas de solicitação de acesso (Etapa 4)
--
-- Migration ADITIVA: nenhuma migration anterior é editada. `handle_new_user`
-- e `reenviar_solicitacao_acesso` (Etapa 2) e `aprovar_usuario`/
-- `rejeitar_usuario` (Etapa 2) são redefinidas aqui via CREATE OR REPLACE
-- (mesma assinatura — preserva owner/ACL), só para acrescentar a chamada de
-- notificação; nenhuma regra de negócio delas muda.
--
-- CONCEITO CENTRAL: notification NÃO é a fonte de verdade do estado do
-- usuário (isso continua sendo `profiles.access_status`) — é só um aviso ao
-- ADMIN de que algo aconteceu. "notification lida/não lida" nunca é usado
-- para decidir se uma solicitação ainda está pendente.
--
-- Uma única tabela (`notifications`), não duas (`events`+`recipients`): o
-- InvTec não precisa de uma plataforma genérica de mensageria. Uma LINHA por
-- destinatário, com `event_id` compartilhado entre as linhas geradas pelo
-- MESMO evento — isso já dá leitura individual (cada ADMIN tem sua própria
-- `lida_em`) e permite distinguir um reenvio posterior (novo `event_id`) sem
-- precisar de uma segunda tabela.

-- =============================================================================
-- 1. TABELA — public.notifications
-- =============================================================================
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  -- compartilhado por todas as linhas geradas pelo MESMO evento (ex.: todos
  -- os ADMIN ACTIVE no momento de uma submissão) — nunca reutilizado por um
  -- evento diferente (um reenvio gera um event_id NOVO, nunca reabre o
  -- anterior).
  event_id uuid not null,
  destinatario_id uuid not null references public.profiles (id) on delete restrict,
  -- `text` livre (não enum fechado) de propósito — mesma convenção de
  -- `admin_audit_log.acao` (Etapa 2): uma categoria nova no futuro
  -- (ex.: EMAIL_CHANGE_REQUEST) não deve exigir migration só para ampliar
  -- uma lista fechada. Mínimo desta etapa documentado no comment da coluna.
  tipo text not null,
  titulo text not null,
  corpo text not null,
  -- usuário ao qual a notificação se refere (quem fez a solicitação de
  -- acesso) — nunca a senha/token/CPF completo dele (ver comentário da
  -- função `private.notify_admins_access_request` abaixo).
  alvo_usuario_id uuid not null references public.profiles (id) on delete restrict,
  lida_em timestamptz,
  -- Preenchido para TODAS as linhas do evento quando a solicitação é
  -- resolvida (aprovada/rejeitada) por QUALQUER ADMIN — independente de
  -- `lida_em`, que continua individual. Ver seção "RESOLUÇÃO GLOBAL" no
  -- pedido: ADMIN A pode ter lido e resolvido; ADMIN B pode nunca ter lido,
  -- mas a linha dele também fica resolvida.
  resolvida_em timestamptz,
  resolvida_por uuid references public.profiles (id) on delete restrict,
  criado_em timestamptz not null default now(),
  constraint notifications_resolucao_coerente check (
    (resolvida_em is null and resolvida_por is null)
    or (resolvida_em is not null and resolvida_por is not null)
  )
);

comment on column public.notifications.tipo is
  'Texto livre. Mínimo desta etapa: ACCESS_REQUEST_CREATED, ACCESS_REQUEST_RESUBMITTED.';

comment on table public.notifications is
  'Aviso ao ADMIN — NUNCA a fonte de verdade do estado da conta (isso é profiles.access_status). Uma linha por destinatário; event_id agrupa as linhas do mesmo evento. Nunca contém senha/token/CPF completo.';

-- Caso principal: notificações recentes de UM destinatário, por criado_em
-- DESC (painel do sino).
create index notifications_destinatario_recentes_idx
  on public.notifications (destinatario_id, criado_em desc);

-- Contagem de não lidas — parcial (só as linhas que importam para o badge),
-- muito mais barato que um índice completo em lida_em.
create index notifications_destinatario_nao_lidas_idx
  on public.notifications (destinatario_id)
  where lida_em is null;

-- Resolução global: localizar rapidamente as linhas ainda abertas de um
-- usuário-alvo (todas as linhas/destinatários daquele evento) quando
-- aprovar_usuario/rejeitar_usuario resolve a solicitação.
create index notifications_alvo_abertas_idx
  on public.notifications (alvo_usuario_id)
  where resolvida_em is null;

-- Consulta pelo event_id (ex.: debug/auditoria — "todas as linhas deste
-- evento").
create index notifications_event_idx on public.notifications (event_id);

alter table public.notifications enable row level security;

-- Só o próprio destinatário, e só se ainda for ADMIN ACTIVE no momento da
-- leitura (um ADMIN desativado/bloqueado depois de receber notificações
-- antigas não continua lendo a lista). `has_perfil('ADMIN')` já exige
-- ACTIVE internamente (Etapa 2).
create policy notifications_select on public.notifications
  for select to authenticated
  using (
    destinatario_id = (select auth.uid())
    and (select private.has_perfil('ADMIN'))
  );

-- sem INSERT/UPDATE/DELETE policy: toda escrita é por função SECURITY
-- DEFINER (abaixo) — nenhum GRANT de escrita para authenticated.
revoke all on table public.notifications from public, anon, authenticated;
grant select on table public.notifications to authenticated;

-- =============================================================================
-- 2. private.notify_admins_access_request — helper de criação (interno)
-- =============================================================================
-- Gera UM event_id novo, localiza todos os ADMIN ACTIVE NESTE MOMENTO e
-- insere uma linha por destinatário. Silenciosamente não insere nada se não
-- existir nenhum ADMIN ACTIVE ainda (bootstrap) — nunca lança erro por isso.
--
-- FAIL-SAFE DELIBERADO: todo o corpo está dentro de um bloco com EXCEPTION
-- WHEN OTHERS que só registra um WARNING (nunca propaga). Motivo: esta
-- função é chamada de DENTRO de `handle_new_user`/`reenviar_solicitacao_acesso`,
-- na MESMA transação do cadastro/reenvio — um bug futuro na infraestrutura de
-- notificação (ex.: uma coluna renomeada, um índice corrompido) NUNCA deve
-- impedir o signup ou o reenvio de completarem. Uma EXCEPTION em PL/pgSQL
-- cria um savepoint implícito: o rollback fica contido ao INSERT de
-- notificação, sem desfazer o restante da transação do chamador.
create or replace function private.notify_admins_access_request(
  p_alvo_usuario_id uuid,
  p_tipo text,
  p_titulo text,
  p_corpo text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid := gen_random_uuid();
begin
  insert into public.notifications (event_id, destinatario_id, tipo, titulo, corpo, alvo_usuario_id)
  select v_event_id, p.id, p_tipo, p_titulo, p_corpo, p_alvo_usuario_id
  from public.profiles p
  where p.perfil = 'ADMIN' and p.access_status = 'ACTIVE' and p.ativo is true;
exception
  when others then
    raise warning 'notify_admins_access_request falhou (tipo=%, alvo=%): %', p_tipo, p_alvo_usuario_id, sqlerrm;
end;
$$;

-- Nunca chamada diretamente pelo cliente — só de dentro de outra função
-- SECURITY DEFINER (mesmo padrão de `private.is_valid_cpf`, Etapa 2).
revoke all on function private.notify_admins_access_request(uuid, text, text, text) from public, anon, authenticated;

-- =============================================================================
-- 3. private.resolve_access_request_notifications — resolução global (interno)
-- =============================================================================
-- Resolve TODAS as linhas ainda abertas (resolvida_em is null) cujo
-- alvo_usuario_id é o usuário decidido — para TODOS os destinatários
-- (ADMIN A e ADMIN B), independente de `lida_em` de cada um. Não filtra por
-- `event_id` especificamente: pelo invariante do fluxo (cada
-- aprovar/rejeitar já resolve o que estava aberto), só pode haver UM evento
-- aberto por usuário no momento em que esta função roda — filtrar só por
-- "ainda aberta" é mais simples e também limpa, como rede de segurança,
-- qualquer linha órfã que um bug futuro deixasse aberta por engano.
-- Mesmo padrão fail-safe da função anterior: nunca lança erro.
create or replace function private.resolve_access_request_notifications(p_alvo_usuario_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.notifications
  set resolvida_em = now(), resolvida_por = auth.uid()
  where alvo_usuario_id = p_alvo_usuario_id
    and tipo in ('ACCESS_REQUEST_CREATED', 'ACCESS_REQUEST_RESUBMITTED')
    and resolvida_em is null;
exception
  when others then
    raise warning 'resolve_access_request_notifications falhou (alvo=%): %', p_alvo_usuario_id, sqlerrm;
end;
$$;

revoke all on function private.resolve_access_request_notifications(uuid) from public, anon, authenticated;

-- =============================================================================
-- 4. handle_new_user — gera ACCESS_REQUEST_CREATED
-- =============================================================================
-- Reaproveita a MESMA trigger (AFTER INSERT ON auth.users) — dispara uma
-- única vez por conta criada, nunca em login (login não gera INSERT em
-- auth.users), então nunca duplica notificação para o mesmo cadastro.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text := coalesce(
    public.normalize_text(new.raw_user_meta_data ->> 'nome'),
    new.email,
    new.id::text
  );
begin
  insert into public.profiles (id, nome, email, cpf, perfil, ativo, access_status, rejection_count)
  values (
    new.id,
    v_nome,
    new.email,
    new.raw_user_meta_data ->> 'cpf',
    'CONSULTA',
    false,
    'PENDING',
    0
  );

  perform private.notify_admins_access_request(
    new.id,
    'ACCESS_REQUEST_CREATED',
    'Nova solicitação de acesso',
    v_nome || ' solicitou acesso ao InvTec.'
  );

  return new;
end;
$$;

-- =============================================================================
-- 5. reenviar_solicitacao_acesso — gera ACCESS_REQUEST_RESUBMITTED
-- =============================================================================
-- Mesma função da Etapa 2, com UMA linha nova (a chamada de notificação) no
-- fim, antes do `return`. Nenhuma outra regra muda: ainda self-service, sem
-- user_id do cliente, não altera nome/cpf/email/perfil/rejection_count.
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

  -- NOVO event_id — nunca reaproveita o da submissão anterior (que já foi
  -- resolvido quando este usuário foi rejeitado, ver seção 6 abaixo).
  perform private.notify_admins_access_request(
    auth.uid(),
    'ACCESS_REQUEST_RESUBMITTED',
    'Solicitação de acesso reenviada',
    v_depois.nome || ' reenviou a solicitação de acesso.'
  );

  return v_depois;
end;
$$;

-- =============================================================================
-- 6. aprovar_usuario / rejeitar_usuario — resolução global
-- =============================================================================
-- Mesmas duas funções da Etapa 2, com UMA linha nova cada (a chamada de
-- resolução) antes do `return`. Nenhuma regra de aprovação/rejeição muda.
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

  perform private.resolve_access_request_notifications(p_user_id);

  return v_depois;
end;
$$;

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

  perform private.resolve_access_request_notifications(p_user_id);

  return v_depois;
end;
$$;

-- =============================================================================
-- 7. marcar_notificacao_lida — só o próprio destinatário
-- =============================================================================
-- Nunca aceita user_id do cliente — sempre auth.uid(). Idempotente: se já
-- estiver lida, devolve o estado atual sem tocar em lida_em (e nunca toca
-- resolvida_em/resolvida_por, que são administrados só pela resolução
-- global).
--
-- `has_perfil('ADMIN')` explícito aqui — achado real da revisão de QA: como
-- esta função é SECURITY DEFINER, ela não está sujeita à RLS de
-- `notifications` (que, além de `destinatario_id = auth.uid()`, também exige
-- `has_perfil('ADMIN')` — ver comentário da policy `notifications_select`).
-- Sem esta checagem, um ex-ADMIN desativado/rebaixado cujo JWT ainda não
-- expirou conseguiria ler de volta (via `RETURNING *`) o conteúdo completo
-- das PRÓPRIAS notificações antigas, contornando exatamente a garantia que
-- a policy de SELECT foi desenhada para dar.
create or replace function public.marcar_notificacao_lida(p_notification_id uuid)
returns public.notifications
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_notification public.notifications;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem marcar notificações como lidas' using errcode = '42501';
  end if;

  select * into v_notification
  from public.notifications
  where id = p_notification_id and destinatario_id = auth.uid()
  for update;

  if not found then
    raise exception 'Notificação não encontrada' using errcode = 'P0002';
  end if;

  if v_notification.lida_em is null then
    update public.notifications
    set lida_em = now()
    where id = p_notification_id
    returning * into v_notification;
  end if;

  return v_notification;
end;
$$;

-- =============================================================================
-- 8. marcar_todas_notificacoes_lidas — só as do próprio destinatário
-- =============================================================================
-- Marca lida_em em TODAS as não lidas do chamador, resolvidas ou não (a
-- semântica de "lida" é sempre individual e independente de "resolvida" —
-- ver seção 11 do pedido). Mesmo motivo da função anterior para o
-- `has_perfil('ADMIN')` explícito (SECURITY DEFINER não é sujeita à RLS).
create or replace function public.marcar_todas_notificacoes_lidas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qtd integer;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem marcar notificações como lidas' using errcode = '42501';
  end if;

  update public.notifications
  set lida_em = now()
  where destinatario_id = auth.uid() and lida_em is null;

  get diagnostics v_qtd = row_count;
  return v_qtd;
end;
$$;

-- =============================================================================
-- 9. LEITURA — nenhuma RPC dedicada
-- =============================================================================
-- "Últimas notificações" e "total de não lidas" são um SELECT simples, já
-- protegido por `notifications_select` (RLS): o Flutter faz
-- `select * from notifications where destinatario_id = auth.uid() order by
-- criado_em desc limit 10` (usa o índice da seção 1) e
-- `select count(*) from notifications where lida_em is null` (HEAD request
-- do PostgREST, usa o índice parcial) — nenhuma RPC adicional reduziria
-- complexidade real aqui; criar uma só duplicaria o que RLS + índice já
-- resolvem.

-- =============================================================================
-- 10. GRANTS — RPCs
-- =============================================================================
revoke all on function
  public.marcar_notificacao_lida(uuid),
  public.marcar_todas_notificacoes_lidas()
from public, anon, authenticated;

grant execute on function public.marcar_notificacao_lida(uuid) to authenticated;
grant execute on function public.marcar_todas_notificacoes_lidas() to authenticated;

-- =============================================================================
-- 11. REALTIME
-- =============================================================================
-- O projeto ainda não usa Supabase Realtime em nenhuma tabela — esta é a
-- primeira. `notifications` já está com RLS habilitada (seção 1): o
-- Realtime do Supabase avalia a policy de SELECT para cada assinante antes
-- de emitir o evento, então adicionar a tabela à publicação não abre leitura
-- nenhuma além do que `notifications_select` já permite — um ADMIN só
-- recebe em tempo real as próprias linhas (destinatario_id = auth.uid()),
-- nunca as de outro ADMIN.
alter publication supabase_realtime add table public.notifications;
