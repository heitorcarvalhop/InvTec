-- InvTec — private.has_permission + consulta de permissões efetivas +
-- RPCs administrativas de override (Etapa 3)
--
-- Depende de 20261006100000 (permissions/role_permissions/user_permissions
-- já existem) e de toda a Etapa 2 (access_status, admin_audit_log,
-- private.has_perfil já atualizado).
--
-- private.has_perfil CONTINUA EXISTINDO e não é alterada aqui: ela resolve
-- IDENTIDADE de perfil (usada pelas RPCs administrativas de usuários da
-- Etapa 2 e pela proteção do último ADMIN). private.has_permission resolve
-- CAPACIDADE DE NEGÓCIO (perfil base + override). São dois conceitos
-- diferentes, cada um com seu helper.

-- =============================================================================
-- 1. private.has_permission — helper central de autorização de NEGÓCIO
-- =============================================================================
-- Fluxo (seção 10 do pedido): auth.uid() precisa ter profile ACTIVE+ativo
-- (senão nega imediatamente — PENDING/REJECTED/BLOCKED nunca passam por
-- aqui, mesmo com um eventual override granted=true: ver seção 2 abaixo,
-- nenhuma linha de user_permissions é nem consultada se o profile não
-- estiver ACTIVE). Havendo override explícito, ele decide (PERMITIR ou
-- NEGAR); sem override, cai no preset do perfil (role_permissions).
-- `permission_key` inexistente no catálogo nunca encontra uma linha em
-- role_permissions (FK garante que só chaves válidas aparecem lá) nem em
-- user_permissions — o resultado é FALSE por construção, sem precisar de
-- uma checagem extra contra `permissions` (fail closed).
create or replace function private.has_permission(p_permission_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfil_usuario;
  v_override boolean;
begin
  select p.perfil into v_perfil
  from public.profiles p
  where p.id = auth.uid()
    and p.ativo is true
    and p.access_status = 'ACTIVE';

  if v_perfil is null then
    return false;
  end if;

  select up.granted into v_override
  from public.user_permissions up
  where up.user_id = auth.uid()
    and up.permission_key = p_permission_key;

  if v_override is not null then
    return v_override;
  end if;

  return exists (
    select 1
    from public.role_permissions rp
    where rp.perfil = v_perfil
      and rp.permission_key = p_permission_key
  );
end;
$$;

-- DIFERENTE de `private.is_valid_cpf` (que só é chamada de DENTRO de outra
-- função SECURITY DEFINER, nunca precisando de GRANT): `has_permission` é
-- invocada DIRETAMENTE pelas RLS policies de negócio (migration seguinte,
-- 20261006120000), que avaliam no contexto do papel que faz a consulta
-- (`authenticated`), não dentro de uma função definer já "promovida". Sem
-- este GRANT, toda policy que a chama falharia com permissão negada — o
-- MESMO padrão de `private.has_perfil`, que também recebe
-- `grant execute ... to authenticated` na migration inicial pelo mesmo
-- motivo. Chamar a função diretamente não vaza nada: ela já é `SECURITY
-- DEFINER` e só devolve um boolean sobre o PRÓPRIO `auth.uid()`.
revoke all on function private.has_permission(text) from public, anon, authenticated;
grant execute on function private.has_permission(text) to authenticated;

-- =============================================================================
-- 2. minhas_permissoes — self-service, sem parâmetro
-- =============================================================================
-- O Flutter não precisa replicar "perfil + override": chama esta função e
-- recebe só as chaves EFETIVAMENTE concedidas (granted=true efetivo). Se o
-- usuário não estiver ACTIVE (PENDING/REJECTED/BLOCKED), devolve conjunto
-- vazio — nunca erro (a tela "Aguardando aprovação" não precisa tratar uma
-- exceção só para saber que não tem nenhuma permissão).
create or replace function public.minhas_permissoes()
returns table (permission_key text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfil_usuario;
begin
  select p.perfil into v_perfil
  from public.profiles p
  where p.id = auth.uid()
    and p.ativo is true
    and p.access_status = 'ACTIVE';

  if v_perfil is null then
    return;
  end if;

  return query
  select perm.permission_key
  from public.permissions perm
  where coalesce(
    (
      select up.granted
      from public.user_permissions up
      where up.user_id = auth.uid() and up.permission_key = perm.permission_key
    ),
    exists (
      select 1 from public.role_permissions rp
      where rp.perfil = v_perfil and rp.permission_key = perm.permission_key
    )
  );
end;
$$;

-- =============================================================================
-- 3. obter_permissoes_usuario — ADMIN-only, visão completa para a futura UI
-- =============================================================================
-- Para cada chave do catálogo: o padrão do perfil do alvo, o override (se
-- existir — null quando não há), e o valor EFETIVO resultante. Não exige o
-- alvo ACTIVE (é só leitura/diagnóstico — a restrição de ACTIVE do pedido,
-- seção 21, é sobre as RPCs que ESCREVEM um override, abaixo).
create or replace function public.obter_permissoes_usuario(p_user_id uuid)
returns table (
  permission_key text,
  default_do_perfil boolean,
  override boolean,
  efetiva boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perfil public.perfil_usuario;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem consultar permissões de outro usuário'
      using errcode = '42501';
  end if;

  select p.perfil into v_perfil from public.profiles p where p.id = p_user_id;
  if v_perfil is null then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;

  return query
  select
    perm.permission_key,
    exists (
      select 1 from public.role_permissions rp
      where rp.perfil = v_perfil and rp.permission_key = perm.permission_key
    ) as default_do_perfil,
    up.granted as override,
    coalesce(
      up.granted,
      exists (
        select 1 from public.role_permissions rp
        where rp.perfil = v_perfil and rp.permission_key = perm.permission_key
      )
    ) as efetiva
  from public.permissions perm
  left join public.user_permissions up
    on up.user_id = p_user_id and up.permission_key = perm.permission_key
  order by perm.permission_key;
end;
$$;

-- =============================================================================
-- 4. definir_permissao_usuario — cria/atualiza um override
-- =============================================================================
-- ADMIN ACTIVE, alvo ACTIVE (seção 21: gerenciar permissão de conta ainda
-- não aprovada fica fora desta etapa), chave precisa existir no catálogo,
-- granted não pode ser nulo (os 3 estados são HERDAR=sem linha/
-- PERMITIR=true/NEGAR=false — nunca uma linha com granted null). Bloqueia
-- alvo = o próprio ADMIN que está chamando (seção 27: "usuário não concede
-- permissão a si mesmo") — outro ADMIN pode definir o override; o mesmo
-- ADMIN sobre a própria conta, não. UPSERT (ON CONFLICT) é a forma segura
-- contra corrida pedida na seção 28: duas chamadas simultâneas para o
-- mesmo (user_id, permission_key) nunca duplicam linha — a PK composta
-- garante isso, e o UPSERT faz a segunda esperar/sobrescrever de forma
-- consistente, nunca lançar unique_violation para o cliente.
create or replace function public.definir_permissao_usuario(
  p_user_id uuid,
  p_permission_key text,
  p_granted boolean
)
returns public.user_permissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil_alvo public.perfil_usuario;
  v_access_status_alvo public.profile_access_status;
  v_valor_anterior boolean;
  v_resultado public.user_permissions;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem definir permissões de usuário'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Um administrador não pode definir uma permissão para a própria conta'
      using errcode = 'P0001';
  end if;
  if p_permission_key is null or not exists (
    select 1 from public.permissions where permission_key = p_permission_key
  ) then
    raise exception 'Chave de permissão inválida: %', p_permission_key using errcode = 'P0001';
  end if;
  if p_granted is null then
    raise exception 'granted é obrigatório (true ou false)' using errcode = 'P0001';
  end if;

  select perfil, access_status into v_perfil_alvo, v_access_status_alvo
  from public.profiles where id = p_user_id;

  if v_perfil_alvo is null then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;
  if v_access_status_alvo <> 'ACTIVE' then
    raise exception 'Só é possível gerenciar permissões de um usuário ACTIVE (status atual: %)', v_access_status_alvo
      using errcode = 'P0001';
  end if;

  select granted into v_valor_anterior
  from public.user_permissions
  where user_id = p_user_id and permission_key = p_permission_key;

  insert into public.user_permissions (user_id, permission_key, granted, concedido_por)
  values (p_user_id, p_permission_key, p_granted, auth.uid())
  on conflict (user_id, permission_key)
  do update set granted = excluded.granted, concedido_por = excluded.concedido_por
  returning * into v_resultado;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id,
    case when p_granted then 'PERMISSION_GRANTED' else 'PERMISSION_DENIED' end,
    jsonb_build_object('permission_key', p_permission_key, 'granted', v_valor_anterior),
    jsonb_build_object('permission_key', p_permission_key, 'granted', p_granted)
  );

  return v_resultado;
end;
$$;

-- =============================================================================
-- 5. remover_override_permissao_usuario — volta a HERDAR do perfil
-- =============================================================================
-- Diferente de granted=false: aqui a linha é APAGADA, então a permissão
-- passa a seguir o preset do perfil novamente (pode virar permitida ou
-- negada, dependendo do que o preset diz). Idempotente: se não havia
-- override, não há nada para desfazer — devolve null sem gravar auditoria
-- (nada mudou de verdade).
create or replace function public.remover_override_permissao_usuario(
  p_user_id uuid,
  p_permission_key text
)
returns public.user_permissions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_access_status_alvo public.profile_access_status;
  v_removido public.user_permissions;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem remover permissões de usuário'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Um administrador não pode remover um override da própria conta'
      using errcode = 'P0001';
  end if;

  select access_status into v_access_status_alvo from public.profiles where id = p_user_id;
  if v_access_status_alvo is null then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;
  if v_access_status_alvo <> 'ACTIVE' then
    raise exception 'Só é possível gerenciar permissões de um usuário ACTIVE (status atual: %)', v_access_status_alvo
      using errcode = 'P0001';
  end if;

  delete from public.user_permissions
  where user_id = p_user_id and permission_key = p_permission_key
  returning * into v_removido;

  if v_removido.user_id is null then
    return null;
  end if;

  insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
  values (
    auth.uid(), p_user_id, 'PERMISSION_OVERRIDE_REMOVED',
    jsonb_build_object('permission_key', p_permission_key, 'granted', v_removido.granted),
    jsonb_build_object('permission_key', p_permission_key, 'granted', null)
  );

  return v_removido;
end;
$$;

-- =============================================================================
-- 6. resetar_permissoes_usuario — remove TODOS os overrides do usuário
-- =============================================================================
-- Facilita a futura UI ("Resetar permissões" — seção 18/20 do pedido):
-- volta o usuário a herdar 100% do preset do perfil atual. Mesma exigência
-- de alvo ACTIVE e de não ser a própria conta do ADMIN que chama, pelos
-- mesmos motivos das duas RPCs acima.
create or replace function public.resetar_permissoes_usuario(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_access_status_alvo public.profile_access_status;
  v_overrides_antes jsonb;
  v_qtd integer;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Apenas administradores podem resetar as permissões de um usuário'
      using errcode = '42501';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Um administrador não pode resetar os overrides da própria conta'
      using errcode = 'P0001';
  end if;

  select access_status into v_access_status_alvo from public.profiles where id = p_user_id;
  if v_access_status_alvo is null then
    raise exception 'Usuário não encontrado' using errcode = 'P0002';
  end if;
  if v_access_status_alvo <> 'ACTIVE' then
    raise exception 'Só é possível gerenciar permissões de um usuário ACTIVE (status atual: %)', v_access_status_alvo
      using errcode = 'P0001';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('permission_key', permission_key, 'granted', granted)), '[]'::jsonb)
    into v_overrides_antes
  from public.user_permissions
  where user_id = p_user_id;

  delete from public.user_permissions where user_id = p_user_id;
  get diagnostics v_qtd = row_count;

  if v_qtd > 0 then
    insert into public.admin_audit_log (ator_id, alvo_id, acao, dados_antes, dados_depois)
    values (
      auth.uid(), p_user_id, 'USER_PERMISSIONS_RESET',
      jsonb_build_object('overrides', v_overrides_antes),
      jsonb_build_object('overrides', '[]'::jsonb)
    );
  end if;

  return v_qtd;
end;
$$;

-- =============================================================================
-- 7. GRANTS
-- =============================================================================
revoke all on function
  public.minhas_permissoes,
  public.obter_permissoes_usuario(uuid),
  public.definir_permissao_usuario(uuid, text, boolean),
  public.remover_override_permissao_usuario(uuid, text),
  public.resetar_permissoes_usuario(uuid)
from public, anon, authenticated;

grant execute on function public.minhas_permissoes to authenticated;
grant execute on function public.obter_permissoes_usuario(uuid) to authenticated;
grant execute on function public.definir_permissao_usuario(uuid, text, boolean) to authenticated;
grant execute on function public.remover_override_permissao_usuario(uuid, text) to authenticated;
grant execute on function public.resetar_permissoes_usuario(uuid) to authenticated;

-- A checagem `has_perfil('ADMIN')` dentro de cada função (exceto
-- `minhas_permissoes`, self-service) é a autorização real — o GRANT a
-- `authenticated` é só a primeira camada, mesmo padrão de toda RPC
-- administrativa do projeto desde a Etapa 2: GESTOR/OPERADOR/CONSULTA têm
-- EXECUTE, mas toda chamada real falha com 42501 se quem chama não for
-- ADMIN ACTIVE.
