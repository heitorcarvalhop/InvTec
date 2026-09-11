-- InvTec — schema inicial de controle patrimonial
-- Entidades: profiles, setores, tipos_patrimonio, patrimonios, movimentacoes
--
-- IMPORTANTE: esta migration ainda NÃO foi aplicada no Supabase remoto e
-- também NÃO foi executada em nenhum PostgreSQL local. Revise antes de aplicar.
--
-- Convenções de segurança usadas em todo o arquivo:
-- * Toda função fixa `set search_path = ''` e referencia objetos sempre com
--   schema explícito (public.*, auth.uid()).
-- * Toda autorização passa por private.has_perfil(...), que usa EXISTS e por
--   isso retorna true/false, nunca NULL. Nenhuma checagem de permissão usa
--   `x not in (...)` ou comparação que possa resultar em NULL.
-- * CHECKs de normalização usam `is not distinct from`, pois um CHECK que
--   avalia para NULL é considerado APROVADO pelo PostgreSQL.
-- * Funções que são implementação interna (nunca endpoints RPC do Flutter)
--   vivem no schema `private`, não em `public`: `cadastrar_patrimonio` e
--   `registrar_movimentacao` são os únicos endpoints intencionais.

-- =============================================================================
-- 1. EXTENSÕES
-- =============================================================================
-- Nenhuma. gen_random_uuid() é nativa do PostgreSQL 13+.

-- =============================================================================
-- 2. ENUMS
-- =============================================================================
-- Tipos de patrimônio são dado administrativo (tabela tipos_patrimonio). Os
-- enums abaixo representam regras fixas do sistema.

create type public.patrimonio_status as enum (
  'DISPONIVEL',
  'EM_USO',
  'EMPRESTADO',
  'EM_MANUTENCAO',
  'BAIXADO'
);

create type public.movimentacao_tipo as enum (
  'ENTRADA',
  'SAIDA',
  'TRANSFERENCIA',
  'EMPRESTIMO',
  'DEVOLUCAO',
  'MANUTENCAO',
  'RETORNO_MANUTENCAO',
  'BAIXA',
  'AJUSTE_INVENTARIO',
  -- não representa deslocamento físico: mesmo setor, novo responsável
  'ALTERACAO_RESPONSAVEL'
);

create type public.perfil_usuario as enum (
  'ADMIN',
  'GESTOR',
  'OPERADOR',
  'CONSULTA'
);

-- =============================================================================
-- 3. FUNÇÃO AUXILIAR USADA EM CHECKS
-- =============================================================================
-- Precisa existir antes das tabelas. Remove espaço/tab/CR/LF das pontas e
-- converte string vazia em NULL. Não altera o conteúdo interno (zeros à
-- esquerda são preservados).

create or replace function public.normalize_text(p_valor text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select nullif(btrim(p_valor, E' \t\r\n'), '');
$$;

-- =============================================================================
-- 4. TABELAS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- profiles: perfil de aplicação vinculado a auth.users (Supabase Auth)
-- ---------------------------------------------------------------------------
create table public.profiles (
  -- ON DELETE RESTRICT (não CASCADE): usuários do InvTec são DESATIVADOS
  -- (ativo = false), nunca excluídos. Excluir o usuário no Supabase Auth
  -- enquanto o profile existir é bloqueado pelo banco, para não perder a
  -- identidade histórica referenciada por patrimonios.criado_por e
  -- movimentacoes.realizado_por. Para remover alguém de fato, o fluxo
  -- correto é: desativar o profile e, se necessário, o usuário no Auth
  -- (sem apagar a linha).
  id uuid primary key references auth.users (id) on delete restrict,
  nome text not null,
  -- cópia do email do Supabase Auth; sincronizada automaticamente por
  -- trigger em auth.users (trg_auth_users_sync_email); não editável pelo
  -- cliente
  email text,
  perfil public.perfil_usuario not null default 'CONSULTA',
  -- InvTec é interno: todo usuário nasce SEM acesso até um ADMIN ativá-lo
  ativo boolean not null default false,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- setores
-- ---------------------------------------------------------------------------
create table public.setores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  sigla text,
  descricao text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  constraint setores_nome_normalizado
    check (nome is not distinct from public.normalize_text(nome)),
  constraint setores_sigla_normalizada
    check (sigla is null or sigla is not distinct from upper(public.normalize_text(sigla)))
);

-- ---------------------------------------------------------------------------
-- tipos_patrimonio: dado administrativo (cresce com o tempo)
-- ---------------------------------------------------------------------------
create table public.tipos_patrimonio (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  descricao text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  constraint tipos_patrimonio_nome_normalizado
    check (nome is not distinct from public.normalize_text(nome))
);

-- ---------------------------------------------------------------------------
-- patrimonios
-- ---------------------------------------------------------------------------
create table public.patrimonios (
  id uuid primary key default gen_random_uuid(),
  -- texto (nunca integer): preserva zeros à esquerda como "00045872"
  numero_patrimonio text,
  numero_serie text,
  tipo_id uuid not null references public.tipos_patrimonio (id) on delete restrict,
  marca text,
  modelo text,
  descricao text,
  observacao text,
  status public.patrimonio_status not null default 'DISPONIVEL',
  setor_atual_id uuid not null references public.setores (id) on delete restrict,
  -- texto livre, mantido SOMENTE pelas RPCs (ver docs/database.md)
  responsavel_atual text,
  data_aquisicao date,
  data_cadastro timestamptz not null default now(),
  -- NOT NULL + RESTRICT: sempre aponta para um profile existente (nunca
  -- vira texto solto, nunca vira NULL). Seguro porque profiles nunca é
  -- apagado de fato (só desativado) — ver comentário em public.profiles.
  criado_por uuid not null references public.profiles (id) on delete restrict,
  atualizado_em timestamptz not null default now(),
  constraint patrimonios_numero_patrimonio_normalizado check (
    numero_patrimonio is null
    or numero_patrimonio is not distinct from upper(public.normalize_text(numero_patrimonio))
  ),
  constraint patrimonios_numero_serie_normalizado check (
    numero_serie is null
    or numero_serie is not distinct from public.normalize_text(numero_serie)
  ),
  constraint patrimonios_responsavel_atual_normalizado check (
    responsavel_atual is null
    or responsavel_atual is not distinct from public.normalize_text(responsavel_atual)
  ),
  -- invariante: status e responsável nunca se contradizem
  constraint patrimonios_status_responsavel_coerente check (
    (status = 'DISPONIVEL' and responsavel_atual is null)
    or (status in ('EM_USO', 'EMPRESTADO') and responsavel_atual is not null)
    or status in ('EM_MANUTENCAO', 'BAIXADO')
  )
);

-- ---------------------------------------------------------------------------
-- movimentacoes: histórico imutável
-- ---------------------------------------------------------------------------
create table public.movimentacoes (
  id uuid primary key default gen_random_uuid(),
  patrimonio_id uuid not null references public.patrimonios (id) on delete restrict,
  tipo public.movimentacao_tipo not null,
  -- setor/responsável ANTES da movimentação (vem do banco, exceto no cadastro)
  origem_id uuid references public.setores (id) on delete restrict,
  responsavel_origem text,
  -- setor/responsável DEPOIS da movimentação (NULL em BAIXA)
  destino_id uuid references public.setores (id) on delete restrict,
  responsavel_destino text,
  motivo text,
  observacao text,
  numero_documento text,
  numero_chamado text,
  -- NOT NULL + RESTRICT: mesma garantia de criado_por (ver public.profiles)
  realizado_por uuid not null references public.profiles (id) on delete restrict,
  data_movimentacao timestamptz not null default now(),
  criado_em timestamptz not null default now()
);

-- =============================================================================
-- 5. ÍNDICES
-- =============================================================================

-- unicidade case-insensitive (valores já chegam com trim pelos CHECKs)
create unique index setores_nome_key on public.setores (lower(nome));
create unique index setores_sigla_key on public.setores (sigla) where sigla is not null;
create unique index tipos_patrimonio_nome_key on public.tipos_patrimonio (lower(nome));

-- o CHECK garante que o valor armazenado já está normalizado (trim +
-- maiúsculas), então a unicidade simples equivale à unicidade normalizada.
-- Última linha de defesa contra cadastros concorrentes com o mesmo número.
create unique index patrimonios_numero_patrimonio_key
  on public.patrimonios (numero_patrimonio)
  where numero_patrimonio is not null;

create index patrimonios_numero_serie_idx
  on public.patrimonios (numero_serie)
  where numero_serie is not null;

create index patrimonios_tipo_idx on public.patrimonios (tipo_id);
create index patrimonios_setor_atual_idx on public.patrimonios (setor_atual_id);
create index patrimonios_status_idx on public.patrimonios (status);

-- histórico de um patrimônio por data; também atende a checagem de data
-- mínima em registrar_movimentacao
create index movimentacoes_patrimonio_data_idx
  on public.movimentacoes (patrimonio_id, data_movimentacao desc);

create index movimentacoes_data_idx
  on public.movimentacoes (data_movimentacao desc);

-- =============================================================================
-- 6. FUNÇÕES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Schema private: implementação interna, nunca exposta como endpoint RPC.
--
-- Não é adicionado aos "Exposed schemas" da Data API do Supabase (isso é
-- uma configuração do painel/projeto — Settings → API — fora do alcance de
-- uma migration SQL; ao configurar o projeto remoto, conferir que `private`
-- não está nessa lista, que por padrão só contém `public`/`graphql_public`).
--
-- Mesmo que fosse adicionado por engano, os GRANTs da seção 9 continuam
-- bloqueando o acesso: só private.has_perfil recebe EXECUTE, e apenas para
-- authenticated (as demais funções deste schema são funções de trigger,
-- que o PostgreSQL já impede de ser chamadas fora do mecanismo de trigger,
-- independente de GRANT).
create schema private;

-- ---------------------------------------------------------------------------
-- Autorização
-- ---------------------------------------------------------------------------

-- true somente se o usuário autenticado tem profile, está ativo E possui um
-- dos perfis informados. Perfil inexistente, inativo ou sem papel → false.
-- EXISTS nunca retorna NULL. SECURITY DEFINER para ler profiles sem cair em
-- recursão de RLS; só consulta a linha do próprio chamador.
--
-- Fica em `private` (não `public`) porque é implementação interna: chamada
-- pelas policies de RLS e pelas duas RPCs públicas, nunca diretamente pelo
-- Flutter.
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
      and p.perfil = any (p_perfis)
  );
$$;

-- ---------------------------------------------------------------------------
-- Triggers genéricas / de normalização
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

create or replace function public.normalize_setor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nome := public.normalize_text(new.nome);
  new.sigla := upper(public.normalize_text(new.sigla));
  return new;
end;
$$;

create or replace function public.normalize_tipo_patrimonio()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nome := public.normalize_text(new.nome);
  return new;
end;
$$;

create or replace function public.normalize_patrimonio()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.numero_patrimonio := upper(public.normalize_text(new.numero_patrimonio));
  new.numero_serie := public.normalize_text(new.numero_serie);
  new.responsavel_atual := public.normalize_text(new.responsavel_atual);
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

-- Cria o profile de todo novo usuário do Supabase Auth: sempre CONSULTA e
-- INATIVO. SECURITY DEFINER porque o cliente não tem INSERT em profiles.
-- Fica em `private`: é uma função de trigger, nunca um endpoint RPC.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nome, email, perfil, ativo)
  values (
    new.id,
    coalesce(
      public.normalize_text(new.raw_user_meta_data ->> 'nome'),
      new.email,
      new.id::text
    ),
    new.email,
    'CONSULTA',
    false
  );
  return new;
end;
$$;

-- Mantém profiles.email sincronizado quando o email muda no Supabase Auth
-- (ex.: usuário troca o próprio email, ou é alterado pelo dashboard). Sem
-- isso, profiles.email fica desatualizado — ele só era copiado na criação.
-- SECURITY DEFINER porque o cliente não tem UPDATE de email em profiles;
-- só copia new.email para a linha correspondente, nada mais.
-- Fica em `private`: é uma função de trigger, nunca um endpoint RPC.
create or replace function private.handle_user_email_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set email = new.email
  where id = new.id;
  return new;
end;
$$;

-- Defesa em profundidade além do GRANT por coluna: mesmo que um GRANT amplo
-- seja aplicado por engano no futuro (ex.: "grant all on all tables"), os
-- papéis do cliente não conseguem alterar id/email/perfil/ativo/criado_em.
-- Roda como invoker: via API o current_user é anon/authenticated; no SQL
-- Editor (bootstrap do primeiro ADMIN) ou dentro de uma futura RPC
-- administrativa SECURITY DEFINER, o current_user é o dono do banco.
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
       or new.perfil is distinct from old.perfil
       or new.ativo is distinct from old.ativo
       or new.criado_em is distinct from old.criado_em
     ) then
    raise exception 'id, email, perfil, ativo e criado_em de profiles só podem ser alterados por fluxo administrativo'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- setores
-- ---------------------------------------------------------------------------

-- Impede desativar um setor que ainda tenha patrimônio não baixado. Trigger
-- (e não CHECK), pois CHECK não pode consultar outra tabela. SECURITY DEFINER
-- para contar TODOS os patrimônios, independentemente do que a RLS do
-- chamador permitiria ver.
--
-- Concorrência: o UPDATE trava a linha do setor antes desta trigger rodar.
-- As RPCs travam o setor de destino com FOR SHARE, que conflita com essa
-- trava — uma espera a outra terminar. Como a função é VOLATILE, o SELECT
-- abaixo usa snapshot novo e enxerga o patrimônio que acabou de ser movido.
-- Fica em `private`: é uma função de trigger, nunca um endpoint RPC.
create or replace function private.prevent_deactivate_setor_em_uso()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qtd integer;
begin
  if old.ativo is true and new.ativo is false then
    select count(*) into v_qtd
    from public.patrimonios p
    where p.setor_atual_id = new.id
      and p.status <> 'BAIXADO';

    if v_qtd > 0 then
      raise exception
        'Não é possível desativar o setor "%": há % patrimônio(s) não baixado(s) vinculado(s) a ele',
        old.nome, v_qtd
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- patrimonios
-- ---------------------------------------------------------------------------

-- Defesa em profundidade além do GRANT por coluna: status, setor_atual_id e
-- responsavel_atual só mudam via registrar_movimentacao (que roda como dono
-- do banco), nunca por UPDATE vindo do cliente.
create or replace function public.protect_patrimonio_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated')
     and (
       new.id is distinct from old.id
       or new.status is distinct from old.status
       or new.setor_atual_id is distinct from old.setor_atual_id
       or new.responsavel_atual is distinct from old.responsavel_atual
       or new.criado_por is distinct from old.criado_por
       or new.data_cadastro is distinct from old.data_cadastro
     ) then
    raise exception 'status, setor_atual_id e responsavel_atual só podem mudar por movimentação registrada'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Edição direta de tipo_id não pode apontar para tipo inativo. FOR SHARE
-- impede desativação concorrente do tipo até esta transação terminar.
-- SECURITY DEFINER porque FOR SHARE também exige passar pela policy de
-- UPDATE de tipos_patrimonio, que um OPERADOR não tem.
-- Fica em `private`: é uma função de trigger, nunca um endpoint RPC.
create or replace function private.validate_tipo_patrimonio_ativo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ativo boolean;
begin
  if new.tipo_id is distinct from old.tipo_id then
    select t.ativo into v_ativo
    from public.tipos_patrimonio t
    where t.id = new.tipo_id
    for share;

    if v_ativo is not true then
      raise exception 'Tipo de patrimônio inexistente ou inativo'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- cadastrar_patrimonio: cria o patrimônio e sua ENTRADA inicial atomicamente.
-- Único caminho de INSERT em patrimonios (o cliente não tem GRANT de INSERT).
-- ---------------------------------------------------------------------------
create or replace function public.cadastrar_patrimonio(
  p_tipo_id uuid,
  p_destino_id uuid,
  p_numero_patrimonio text default null,
  p_numero_serie text default null,
  p_marca text default null,
  p_modelo text default null,
  p_descricao text default null,
  p_observacao text default null,
  p_data_aquisicao date default null,
  p_origem_id uuid default null,
  p_responsavel_origem text default null,
  p_responsavel_destino text default null,
  p_motivo text default null,
  p_observacao_movimentacao text default null,
  p_data_movimentacao timestamptz default null
)
returns public.patrimonios
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_numero text := upper(public.normalize_text(p_numero_patrimonio));
  v_responsavel_destino text := public.normalize_text(p_responsavel_destino);
  v_data timestamptz := coalesce(p_data_movimentacao, now());
  v_tipo_ativo boolean;
  v_destino_ativo boolean;
  v_patrimonio public.patrimonios;
begin
  -- 1-2. usuário e permissão
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para cadastrar patrimônio'
      using errcode = '42501';
  end if;

  -- 3. dados
  if p_tipo_id is null or p_destino_id is null then
    raise exception 'tipo_id e destino_id são obrigatórios'
      using errcode = 'P0001';
  end if;

  -- tolerância de 5 min para diferença de relógio do dispositivo; dentro da
  -- tolerância a data é limitada ao relógio do servidor
  if v_data > now() + interval '5 minutes' then
    raise exception 'data_movimentacao não pode estar no futuro'
      using errcode = 'P0001';
  end if;
  v_data := least(v_data, now());

  -- FOR SHARE: o tipo não pode ser desativado até este cadastro terminar
  select t.ativo into v_tipo_ativo
  from public.tipos_patrimonio t
  where t.id = p_tipo_id
  for share;

  if v_tipo_ativo is not true then
    raise exception 'Tipo de patrimônio inexistente ou inativo'
      using errcode = 'P0001';
  end if;

  -- 4. origem/destino. FOR SHARE: o destino não pode ser desativado até
  -- este cadastro terminar
  select s.ativo into v_destino_ativo
  from public.setores s
  where s.id = p_destino_id
  for share;

  if v_destino_ativo is not true then
    raise exception 'Setor de destino inexistente ou inativo'
      using errcode = 'P0001';
  end if;

  if p_origem_id is not null then
    if p_origem_id = p_destino_id then
      raise exception 'Origem e destino não podem ser o mesmo setor em uma ENTRADA'
        using errcode = 'P0001';
    end if;
    -- origem é referência histórica: pode estar inativa, mas precisa existir
    if not exists (select 1 from public.setores s where s.id = p_origem_id) then
      raise exception 'Setor de origem não encontrado'
        using errcode = 'P0002';
    end if;
  end if;

  -- checagem amigável; o índice único é a defesa real contra corrida
  if v_numero is not null and exists (
    select 1 from public.patrimonios p where p.numero_patrimonio = v_numero
  ) then
    raise exception 'Já existe um patrimônio com o número %', v_numero
      using errcode = '23505';
  end if;

  -- 5 e 7. patrimônio: setor = destino, responsável = responsável de destino
  insert into public.patrimonios (
    numero_patrimonio, numero_serie, tipo_id, marca, modelo, descricao,
    observacao, status, setor_atual_id, responsavel_atual, data_aquisicao,
    criado_por
  ) values (
    v_numero, p_numero_serie, p_tipo_id, p_marca, p_modelo, p_descricao,
    p_observacao,
    (case when v_responsavel_destino is null then 'DISPONIVEL' else 'EM_USO' end)::public.patrimonio_status,
    p_destino_id, v_responsavel_destino, p_data_aquisicao,
    auth.uid()
  )
  returning * into v_patrimonio;

  -- 6. movimentação inicial
  insert into public.movimentacoes (
    patrimonio_id, tipo, origem_id, responsavel_origem,
    destino_id, responsavel_destino, motivo, observacao,
    realizado_por, data_movimentacao
  ) values (
    v_patrimonio.id, 'ENTRADA', p_origem_id, public.normalize_text(p_responsavel_origem),
    p_destino_id, v_responsavel_destino, p_motivo, p_observacao_movimentacao,
    auth.uid(), v_data
  );

  -- 8.
  return v_patrimonio;
end;
$$;

-- ---------------------------------------------------------------------------
-- registrar_movimentacao: toda movimentação de patrimônio JÁ cadastrado.
-- Origem e responsável de origem vêm SEMPRE do estado atual do banco.
-- ---------------------------------------------------------------------------
create or replace function public.registrar_movimentacao(
  p_patrimonio_id uuid,
  p_tipo public.movimentacao_tipo,
  p_destino_id uuid default null,
  p_responsavel_destino text default null,
  p_motivo text default null,
  p_observacao text default null,
  p_numero_documento text default null,
  p_numero_chamado text default null,
  p_data_movimentacao timestamptz default null
)
returns public.movimentacoes
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_responsavel_destino text := public.normalize_text(p_responsavel_destino);
  v_agora timestamptz;
  v_data timestamptz;
  v_patrimonio public.patrimonios;
  v_movimentacao public.movimentacoes;
  v_ultima_data timestamptz;
  v_transicao_permitida boolean;
  v_destino_ativo boolean;
  v_novo_setor uuid;
  v_novo_responsavel text;
  v_novo_status public.patrimonio_status;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para registrar movimentações'
      using errcode = '42501';
  end if;

  if p_patrimonio_id is null or p_tipo is null then
    raise exception 'patrimonio_id e tipo são obrigatórios'
      using errcode = 'P0001';
  end if;

  -- trava o patrimônio: movimentações concorrentes sobre o mesmo item são
  -- serializadas, e a segunda enxerga o estado já atualizado pela primeira
  select p.* into v_patrimonio
  from public.patrimonios p
  where p.id = p_patrimonio_id
  for update;

  if not found then
    raise exception 'Patrimônio % não encontrado', p_patrimonio_id
      using errcode = 'P0002';
  end if;

  -- data resolvida DEPOIS da trava e com clock_timestamp(): now() é o início
  -- da transação, então uma movimentação que esperou outra terminar poderia
  -- ficar datada antes dela e ser rejeitada pela checagem cronológica abaixo
  v_agora := clock_timestamp();

  if p_data_movimentacao is not null
     and p_data_movimentacao > v_agora + interval '5 minutes' then
    raise exception 'data_movimentacao não pode estar no futuro'
      using errcode = 'P0001';
  end if;
  v_data := least(coalesce(p_data_movimentacao, v_agora), v_agora);

  -- -------------------------------------------------------------------------
  -- Matriz de transição (status atual → tipos permitidos)
  -- -------------------------------------------------------------------------
  v_transicao_permitida := case
    when p_tipo in (
      'ENTRADA', 'SAIDA', 'TRANSFERENCIA', 'EMPRESTIMO', 'MANUTENCAO',
      'ALTERACAO_RESPONSAVEL'
    )
      then v_patrimonio.status in ('DISPONIVEL', 'EM_USO')
    when p_tipo = 'DEVOLUCAO'
      then v_patrimonio.status = 'EMPRESTADO'
    when p_tipo = 'RETORNO_MANUTENCAO'
      then v_patrimonio.status = 'EM_MANUTENCAO'
    when p_tipo = 'BAIXA'
      then v_patrimonio.status <> 'BAIXADO'
    when p_tipo = 'AJUSTE_INVENTARIO'
      then true
    else false
  end;

  if v_transicao_permitida is not true then
    raise exception 'Movimentação % não é permitida para patrimônio com status %',
      p_tipo, v_patrimonio.status
      using errcode = 'P0001';
  end if;

  -- histórico em ordem cronológica: como a origem é o estado atual, uma
  -- movimentação datada antes da última produziria um histórico impossível
  select max(m.data_movimentacao) into v_ultima_data
  from public.movimentacoes m
  where m.patrimonio_id = v_patrimonio.id;

  if v_ultima_data is not null and v_data < v_ultima_data then
    raise exception 'data_movimentacao (%) é anterior à última movimentação do patrimônio (%)',
      v_data, v_ultima_data
      using errcode = 'P0001';
  end if;

  -- -------------------------------------------------------------------------
  -- Regras de destino/responsável por tipo
  -- -------------------------------------------------------------------------
  if p_tipo in (
    'ENTRADA', 'SAIDA', 'TRANSFERENCIA', 'EMPRESTIMO',
    'DEVOLUCAO', 'MANUTENCAO', 'RETORNO_MANUTENCAO'
  ) then
    -- deslocamento físico: destino obrigatório e diferente do setor atual
    if p_destino_id is null then
      raise exception 'O tipo % exige destino_id', p_tipo
        using errcode = 'P0001';
    end if;
    if p_destino_id = v_patrimonio.setor_atual_id then
      raise exception 'Destino igual ao setor atual do patrimônio não é permitido para %', p_tipo
        using errcode = 'P0001';
    end if;
  elsif p_tipo = 'BAIXA' then
    -- não há destino: último setor e último responsável são preservados
    if p_destino_id is not null or v_responsavel_destino is not null then
      raise exception 'BAIXA não aceita destino_id nem responsavel_destino'
        using errcode = 'P0001';
    end if;
  elsif p_tipo = 'AJUSTE_INVENTARIO' then
    if v_responsavel_destino is not null then
      raise exception 'AJUSTE_INVENTARIO não altera o responsável'
        using errcode = 'P0001';
    end if;
    if v_patrimonio.status = 'BAIXADO'
       and p_destino_id is not null
       and p_destino_id <> v_patrimonio.setor_atual_id then
      raise exception 'Patrimônio baixado não pode mudar de setor'
        using errcode = 'P0001';
    end if;
  elsif p_tipo = 'ALTERACAO_RESPONSAVEL' then
    -- não representa deslocamento físico: setor permanece o mesmo, então
    -- destino_id nem é aceito como parâmetro (evita ambiguidade sobre
    -- "para onde" quando não há de fato um destino diferente)
    if p_destino_id is not null then
      raise exception 'ALTERACAO_RESPONSAVEL não aceita destino_id — o setor não muda'
        using errcode = 'P0001';
    end if;
    if v_responsavel_destino is null then
      raise exception 'ALTERACAO_RESPONSAVEL exige responsavel_destino'
        using errcode = 'P0001';
    end if;
    if v_responsavel_destino = v_patrimonio.responsavel_atual then
      raise exception 'O novo responsável deve ser diferente do responsável atual'
        using errcode = 'P0001';
    end if;
  end if;

  if p_tipo = 'EMPRESTIMO' and v_responsavel_destino is null then
    raise exception 'EMPRESTIMO exige responsavel_destino'
      using errcode = 'P0001';
  end if;

  -- destino novo precisa estar ativo; FOR SHARE impede desativação
  -- concorrente até esta transação terminar
  if p_destino_id is not null and p_destino_id <> v_patrimonio.setor_atual_id then
    select s.ativo into v_destino_ativo
    from public.setores s
    where s.id = p_destino_id
    for share;

    if v_destino_ativo is not true then
      raise exception 'Setor de destino inexistente ou inativo'
        using errcode = 'P0001';
    end if;
  end if;

  -- -------------------------------------------------------------------------
  -- Estado resultante
  -- -------------------------------------------------------------------------
  case p_tipo
    when 'ENTRADA', 'SAIDA', 'TRANSFERENCIA', 'DEVOLUCAO', 'RETORNO_MANUTENCAO' then
      v_novo_setor := p_destino_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := (case when v_responsavel_destino is null then 'DISPONIVEL' else 'EM_USO' end)::public.patrimonio_status;
    when 'EMPRESTIMO' then
      v_novo_setor := p_destino_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := 'EMPRESTADO';
    when 'MANUTENCAO' then
      v_novo_setor := p_destino_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := 'EM_MANUTENCAO';
    when 'ALTERACAO_RESPONSAVEL' then
      -- setor inalterado por definição; responsavel_destino já foi
      -- validado como obrigatório e diferente do atual
      v_novo_setor := v_patrimonio.setor_atual_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := 'EM_USO';
    when 'BAIXA' then
      v_novo_setor := v_patrimonio.setor_atual_id;
      v_novo_responsavel := v_patrimonio.responsavel_atual;
      v_novo_status := 'BAIXADO';
    when 'AJUSTE_INVENTARIO' then
      -- em BAIXADO, destino só pode ser nulo ou o próprio setor atual
      -- (validado acima), então nada muda; status nunca muda (sem reativação)
      v_novo_setor := coalesce(p_destino_id, v_patrimonio.setor_atual_id);
      v_novo_responsavel := v_patrimonio.responsavel_atual;
      v_novo_status := v_patrimonio.status;
  end case;

  insert into public.movimentacoes (
    patrimonio_id, tipo, origem_id, responsavel_origem,
    destino_id, responsavel_destino, motivo, observacao,
    numero_documento, numero_chamado, realizado_por, data_movimentacao
  ) values (
    v_patrimonio.id, p_tipo, v_patrimonio.setor_atual_id, v_patrimonio.responsavel_atual,
    case when p_tipo = 'BAIXA' then null else v_novo_setor end,
    case when p_tipo = 'BAIXA' then null else v_novo_responsavel end,
    p_motivo, p_observacao,
    p_numero_documento, p_numero_chamado, auth.uid(), v_data
  )
  returning * into v_movimentacao;

  update public.patrimonios
  set setor_atual_id = v_novo_setor,
      responsavel_atual = v_novo_responsavel,
      status = v_novo_status
  where id = v_patrimonio.id;

  return v_movimentacao;
end;
$$;

-- =============================================================================
-- 7. TRIGGERS
-- =============================================================================
-- Triggers BEFORE da mesma tabela disparam em ordem alfabética de nome; as
-- abaixo são independentes entre si (a normalização é idempotente).

create trigger trg_profiles_protect_columns
  before update on public.profiles
  for each row execute function public.protect_profile_columns();

create trigger trg_profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger trg_setores_normalize
  before insert or update on public.setores
  for each row execute function public.normalize_setor();

create trigger trg_setores_prevent_deactivate_em_uso
  before update on public.setores
  for each row execute function private.prevent_deactivate_setor_em_uso();

create trigger trg_tipos_patrimonio_normalize
  before insert or update on public.tipos_patrimonio
  for each row execute function public.normalize_tipo_patrimonio();

create trigger trg_patrimonios_normalize
  before insert or update on public.patrimonios
  for each row execute function public.normalize_patrimonio();

create trigger trg_patrimonios_protect_columns
  before update on public.patrimonios
  for each row execute function public.protect_patrimonio_columns();

create trigger trg_patrimonios_set_updated_at
  before update on public.patrimonios
  for each row execute function public.set_updated_at();

create trigger trg_patrimonios_validate_tipo
  before update of tipo_id on public.patrimonios
  for each row execute function private.validate_tipo_patrimonio_ativo();

create trigger trg_auth_users_handle_new_user
  after insert on auth.users
  for each row execute function private.handle_new_user();

create trigger trg_auth_users_sync_email
  after update of email on auth.users
  for each row execute function private.handle_user_email_updated();

-- =============================================================================
-- 8. SEED
-- =============================================================================
-- Depois das triggers, para que a normalização se aplique também aqui.

insert into public.tipos_patrimonio (nome) values
  ('Notebook'),
  ('Desktop'),
  ('Monitor'),
  ('Teclado'),
  ('Mouse'),
  ('Impressora'),
  ('Nobreak'),
  ('Switch'),
  ('Dock Station'),
  ('Outros');

-- =============================================================================
-- 9. GRANTS
-- =============================================================================
-- Revoga TUDO primeiro, de public, anon e authenticated. Isso é necessário
-- porque projetos Supabase podem ter default privileges que concedem
-- privilégios EXPLÍCITOS a anon/authenticated em objetos novos: nesse caso
-- `revoke ... from public` não os remove, e `grant select` não reduz um
-- `all` já existente. service_role não é tocado: ele contorna RLS por
-- definição e jamais pode existir no aplicativo cliente.

revoke all on table
  public.profiles,
  public.setores,
  public.tipos_patrimonio,
  public.patrimonios,
  public.movimentacoes
from public, anon, authenticated;

revoke all on function
  public.normalize_text,
  public.set_updated_at,
  public.normalize_setor,
  public.normalize_tipo_patrimonio,
  public.normalize_patrimonio,
  public.protect_profile_columns,
  public.protect_patrimonio_columns,
  public.cadastrar_patrimonio,
  public.registrar_movimentacao
from public, anon, authenticated;

-- Schema private: mesmo tratamento (funções recém-criadas recebem EXECUTE
-- de PUBLIC por padrão no PostgreSQL, independente do schema em que vivem).
revoke all on function
  private.has_perfil,
  private.handle_new_user,
  private.handle_user_email_updated,
  private.prevent_deactivate_setor_em_uso,
  private.validate_tipo_patrimonio_ativo
from public, anon, authenticated;

grant usage on schema public to authenticated;

-- private: só has_perfil é chamada de fora de um contexto de trigger (pelas
-- policies de RLS e pelas duas RPCs públicas), então é a única com USAGE no
-- schema e EXECUTE concedidos — e só para authenticated. anon não recebe
-- USAGE em private. As demais 4 funções de `private` são funções de
-- trigger (retornam `trigger`): o PostgreSQL já impede chamá-las fora do
-- mecanismo de trigger, então nenhum GRANT de EXECUTE é necessário para
-- elas funcionarem — nem para o disparo da trigger em si, que não depende
-- de USAGE/EXECUTE do papel que originou o comando.
grant usage on schema private to authenticated;
grant execute on function private.has_perfil to authenticated;

-- profiles: leitura (RLS limita) e UPDATE apenas do nome
grant select on public.profiles to authenticated;
grant update (nome) on public.profiles to authenticated;

-- setores / tipos: id e criado_em são sempre do banco; novo registro nasce
-- ativo; sem DELETE (exclusão lógica). RLS limita a ADMIN/GESTOR.
grant select on public.setores to authenticated;
grant insert (nome, sigla, descricao) on public.setores to authenticated;
grant update (nome, sigla, descricao, ativo) on public.setores to authenticated;

grant select on public.tipos_patrimonio to authenticated;
grant insert (nome, descricao) on public.tipos_patrimonio to authenticated;
grant update (nome, descricao, ativo) on public.tipos_patrimonio to authenticated;

-- patrimonios: sem INSERT (só via cadastrar_patrimonio) e sem DELETE.
-- UPDATE só de metadados; status, setor_atual_id e responsavel_atual mudam
-- apenas por registrar_movimentacao.
grant select on public.patrimonios to authenticated;
grant update (
  numero_patrimonio, numero_serie, tipo_id, marca, modelo,
  descricao, observacao, data_aquisicao
) on public.patrimonios to authenticated;

-- movimentacoes: somente leitura. Escrita só pelas RPCs.
grant select on public.movimentacoes to authenticated;

-- normalize_text: usada em CHECKs, avaliados com o privilégio de quem faz o
-- INSERT/UPDATE. Inofensiva se chamada diretamente.
grant execute on function
  public.normalize_text,
  public.cadastrar_patrimonio,
  public.registrar_movimentacao
to authenticated;

-- =============================================================================
-- 10. ROW LEVEL SECURITY
-- =============================================================================
-- `(select ...)` em volta de auth.uid()/has_perfil faz o PostgreSQL avaliar
-- uma vez por consulta, e não uma vez por linha.

alter table public.profiles enable row level security;
alter table public.setores enable row level security;
alter table public.tipos_patrimonio enable row level security;
alter table public.patrimonios enable row level security;
alter table public.movimentacoes enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

-- a própria linha é sempre visível (mesmo inativo), para o app poder exibir
-- "Seu acesso ao InvTec está desativado"; ADMIN/GESTOR ativos veem todos
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select private.has_perfil('ADMIN', 'GESTOR'))
  );

-- somente a própria linha, somente se ativo; o GRANT limita à coluna nome
create policy profiles_update on public.profiles
  for update to authenticated
  using (
    id = (select auth.uid())
    and (select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA'))
  )
  with check (
    id = (select auth.uid())
    and (select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA'))
  );

-- sem INSERT (trigger handle_new_user) e sem DELETE (usar ativo = false)

-- ---------------------------------------------------------------------------
-- setores
-- ---------------------------------------------------------------------------

create policy setores_select on public.setores
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

create policy setores_insert on public.setores
  for insert to authenticated
  with check ((select private.has_perfil('ADMIN', 'GESTOR')));

create policy setores_update on public.setores
  for update to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR')))
  with check ((select private.has_perfil('ADMIN', 'GESTOR')));

-- ---------------------------------------------------------------------------
-- tipos_patrimonio
-- ---------------------------------------------------------------------------

create policy tipos_patrimonio_select on public.tipos_patrimonio
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

create policy tipos_patrimonio_insert on public.tipos_patrimonio
  for insert to authenticated
  with check ((select private.has_perfil('ADMIN', 'GESTOR')));

create policy tipos_patrimonio_update on public.tipos_patrimonio
  for update to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR')))
  with check ((select private.has_perfil('ADMIN', 'GESTOR')));

-- ---------------------------------------------------------------------------
-- patrimonios
-- ---------------------------------------------------------------------------

create policy patrimonios_select on public.patrimonios
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

create policy patrimonios_update on public.patrimonios
  for update to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR')))
  with check ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR')));

-- sem INSERT (cadastrar_patrimonio) e sem DELETE (exclusão física proibida)

-- ---------------------------------------------------------------------------
-- movimentacoes
-- ---------------------------------------------------------------------------

create policy movimentacoes_select on public.movimentacoes
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

-- sem INSERT/UPDATE/DELETE: histórico imutável. Bloqueado em duas camadas
-- (sem GRANT e sem policy); escrita apenas pelas RPCs SECURITY DEFINER.

-- =============================================================================
-- 11. DEFAULT PRIVILEGES (proteção para objetos futuros)
-- =============================================================================
-- Tudo acima protege os objetos que ESTA migration cria. Sem isso, nada
-- impede que uma migration futura crie uma function/table/sequence nova em
-- public e ela saia com privilégio amplo por esquecimento — em especial
-- functions, que o PostgreSQL concede EXECUTE a PUBLIC automaticamente.
--
-- ALTER DEFAULT PRIVILEGES não é retroativo (não afeta os objetos já
-- criados acima, já tratados um a um nas seções 7 e 9) e só vale para
-- objetos criados depois, pelo role indicado em FOR ROLE — aqui, `postgres`,
-- que é o role usado para rodar migrations no Supabase (dashboard, CLI e
-- SQL Editor). O resultado prático: "novo objeto = privado até uma
-- migration futura liberar explicitamente com GRANT".
--
-- service_role está incluído por completo (BYPASSRLS pula as policies de
-- RLS, mas GRANT/REVOKE de tabela e function continuam valendo normalmente
-- para ele) — qualquer acesso dele a um objeto novo também passa a exigir
-- GRANT explícito de uma migration futura.

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated, service_role;

-- Mesma proteção para o schema private, criado nesta migration: se uma
-- função interna nova for adicionada lá no futuro, ela nasce inacessível
-- até alguém decidir conceder EXECUTE explicitamente — igual às 5 que já
-- existem hoje.
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema private
  revoke all on tables from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema private
  revoke all on sequences from public, anon, authenticated, service_role;
