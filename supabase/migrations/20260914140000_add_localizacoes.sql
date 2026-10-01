-- =============================================================================
-- InvTec — suporte a Localizações dentro de um Setor/Gerência.
--
-- `public.setores` passa a representar a gerência responsável (ex.: GETEC);
-- a tabela não é renomeada. Uma localização (ex.: "Home Office") sempre
-- pertence a exatamente uma gerência e é opcional para um patrimônio.
--
-- Esta migration troca a assinatura de `cadastrar_patrimonio` e
-- `registrar_movimentacao` (novos parâmetros de localização). PostgreSQL
-- `CREATE OR REPLACE FUNCTION` não permite mudar a lista de parâmetros de
-- uma função existente — usar CREATE OR REPLACE aqui criaria um SEGUNDO
-- overload, deixando a versão antiga chamável e com seus GRANTs intactos.
-- Por isso: DROP explícito da assinatura antiga + CREATE da nova + reaplicação
-- de REVOKE/GRANT (DROP remove os grants da função removida).
-- =============================================================================

-- =============================================================================
-- 1. TABELA: public.localizacoes
-- =============================================================================

create table public.localizacoes (
  id uuid primary key default gen_random_uuid(),
  -- ON DELETE RESTRICT (nunca CASCADE): uma gerência não pode ser apagada
  -- enquanto tiver localização — e localização nunca é apagada mesmo assim
  -- (exclusão lógica, ver seção 3). O RESTRICT aqui é só defesa em
  -- profundidade: o app não tem DELETE em setores nem em localizacoes.
  setor_id uuid not null references public.setores (id) on delete restrict,
  nome text not null,
  sigla text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint localizacoes_nome_normalizado
    check (nome is not distinct from public.normalize_text(nome)),
  constraint localizacoes_sigla_normalizada
    check (sigla is null or sigla is not distinct from upper(public.normalize_text(sigla)))
);

-- =============================================================================
-- 2. ÍNDICES
-- =============================================================================

-- Unicidade é POR GERÊNCIA, nunca global: a mesma "Home Office" pode existir
-- em GETEC e em GEVEV como localizações distintas; duas "Home Office" dentro
-- da MESMA gerência é que é inválido.
create unique index localizacoes_setor_nome_key
  on public.localizacoes (setor_id, lower(nome));

create unique index localizacoes_setor_sigla_key
  on public.localizacoes (setor_id, sigla)
  where sigla is not null;

create index localizacoes_setor_idx on public.localizacoes (setor_id);

-- =============================================================================
-- 3. FUNÇÕES — localizacoes
-- =============================================================================

create or replace function public.normalize_localizacao()
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

-- A gerência de uma localização é imutável depois de criada, sem exceção
-- (nem para ADMIN): se foi cadastrada errada, o fluxo é desativar e recriar
-- na gerência certa (preserva coerência histórica das movimentações que já
-- a referenciam). Regra absoluta, por isso não checa current_user.
create or replace function public.protect_localizacao_setor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.setor_id is distinct from old.setor_id then
    raise exception
      'A gerência de uma localização não pode ser alterada depois de criada. Desative esta localização e crie uma nova na gerência correta.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Mesma filosofia de `private.prevent_deactivate_setor_em_uso`: trigger (não
-- CHECK, que não pode consultar outra tabela), SECURITY DEFINER para contar
-- patrimônios independentemente da RLS do chamador.
create or replace function private.prevent_deactivate_localizacao_em_uso()
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
    where p.localizacao_atual_id = new.id
      and p.status <> 'BAIXADO';

    if v_qtd > 0 then
      raise exception
        'Não é possível desativar a localização "%": há % patrimônio(s) não baixado(s) vinculado(s) a ela',
        old.nome, v_qtd
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- Uma gerência inativa não pode ganhar localização ativa — nem por criação
-- nem por reativação. FOR SHARE na linha de public.setores serializa contra
-- uma desativação concorrente do setor (que toma lock via UPDATE), em
-- qualquer ordem de entrelaçamento das duas transações.
create or replace function private.validate_setor_ativo_para_localizacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setor_ativo boolean;
begin
  -- só interessa quando a localização está (ou passa a estar) ativa —
  -- desativar uma localização nunca depende do estado do setor.
  if new.ativo is true then
    select s.ativo into v_setor_ativo
    from public.setores s
    where s.id = new.setor_id
    for share;

    if v_setor_ativo is not true then
      raise exception
        'Não é possível criar ou reativar uma localização em uma gerência inexistente ou inativa'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- =============================================================================
-- 4. TRIGGERS — localizacoes
-- =============================================================================
-- BEFORE da mesma tabela disparam em ordem alfabética de nome; as trigger
-- functions abaixo são independentes entre si.

create trigger trg_localizacoes_normalize
  before insert or update on public.localizacoes
  for each row execute function public.normalize_localizacao();

create trigger trg_localizacoes_prevent_deactivate_em_uso
  before update on public.localizacoes
  for each row execute function private.prevent_deactivate_localizacao_em_uso();

create trigger trg_localizacoes_protect_setor
  before update on public.localizacoes
  for each row execute function public.protect_localizacao_setor();

create trigger trg_localizacoes_set_updated_at
  before update on public.localizacoes
  for each row execute function public.set_updated_at();

-- Dispara em TODO insert (localização nasce ativa por padrão) e em update
-- que toque ativo — cobre tanto desativar quanto reativar; a função só
-- valida quando new.ativo é true, então desativar nunca é bloqueado aqui.
create trigger trg_localizacoes_validate_setor_ativo
  before insert or update of ativo on public.localizacoes
  for each row execute function private.validate_setor_ativo_para_localizacao();

-- =============================================================================
-- 5. ALTERAÇÃO: public.patrimonios
-- =============================================================================
-- Nullable: localização é sempre OPCIONAL. ALTER TABLE ADD COLUMN nullable
-- sem DEFAULT não reescreve/bloqueia a tabela — valores existentes nascem null.

alter table public.patrimonios
  add column localizacao_atual_id uuid references public.localizacoes (id) on delete restrict;

create index patrimonios_localizacao_atual_idx on public.patrimonios (localizacao_atual_id);

-- Quando localizacao_atual_id não é null, ela DEVE pertencer ao
-- setor_atual_id do mesmo patrimônio — CHECK não pode consultar outra
-- tabela, então isso é uma trigger: defesa em profundidade mesmo que a
-- lógica das RPCs tenha um bug futuro.
create or replace function private.validate_localizacao_pertence_ao_setor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setor_da_localizacao uuid;
begin
  if new.localizacao_atual_id is not null then
    select l.setor_id into v_setor_da_localizacao
    from public.localizacoes l
    where l.id = new.localizacao_atual_id
    for share;

    if v_setor_da_localizacao is null then
      raise exception 'Localização inexistente'
        using errcode = 'P0002';
    end if;

    if v_setor_da_localizacao <> new.setor_atual_id then
      raise exception 'A localização informada não pertence ao setor/gerência atual do patrimônio'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_patrimonios_validate_localizacao
  before insert or update of localizacao_atual_id, setor_atual_id on public.patrimonios
  for each row execute function private.validate_localizacao_pertence_ao_setor();

-- Mesma proteção já aplicada a status/setor_atual_id/responsavel_atual —
-- localizacao_atual_id só muda por movimentação registrada. Reaplica a
-- função inteira: a trigger já existente passa a usar este corpo.
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
       or new.localizacao_atual_id is distinct from old.localizacao_atual_id
       or new.responsavel_atual is distinct from old.responsavel_atual
       or new.criado_por is distinct from old.criado_por
       or new.data_cadastro is distinct from old.data_cadastro
     ) then
    raise exception 'status, setor_atual_id, localizacao_atual_id e responsavel_atual só podem mudar por movimentação registrada'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
-- Nenhuma mudança de GRANT necessária: localizacao_atual_id nunca entra na
-- lista de colunas de UPDATE liberadas ao cliente — igual a
-- setor_atual_id/status hoje.

-- Setor/gerência não pode ser desativado com localização ATIVA vinculada
-- (além da regra já existente de patrimônio não baixado). Reaplica a função
-- inteira: a trigger já existente passa a usar este corpo.
create or replace function private.prevent_deactivate_setor_em_uso()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qtd_patrimonios integer;
  v_qtd_localizacoes integer;
begin
  if old.ativo is true and new.ativo is false then
    select count(*) into v_qtd_patrimonios
    from public.patrimonios p
    where p.setor_atual_id = new.id
      and p.status <> 'BAIXADO';

    if v_qtd_patrimonios > 0 then
      raise exception
        'Não é possível desativar o setor "%": há % patrimônio(s) não baixado(s) vinculado(s) a ele',
        old.nome, v_qtd_patrimonios
        using errcode = 'P0001';
    end if;

    select count(*) into v_qtd_localizacoes
    from public.localizacoes l
    where l.setor_id = new.id
      and l.ativo is true;

    if v_qtd_localizacoes > 0 then
      raise exception
        'Não é possível desativar o setor "%": há % localização(ões) ativa(s) vinculada(s) a ele. Desative as localizações primeiro.',
        old.nome, v_qtd_localizacoes
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

-- =============================================================================
-- 6. ALTERAÇÃO: public.movimentacoes
-- =============================================================================
-- Nullable: histórico já existente continua válido com null. ON DELETE
-- RESTRICT, nunca CASCADE — localizacoes nunca é apagada de fato.
--
-- A FK preserva a IDENTIDADE da localização (o id), não um retrato textual
-- do nome no momento da movimentação: se a localização for renomeada, uma
-- consulta futura do histórico (join por id) mostra o nome ATUAL, não o
-- nome de quando a movimentação foi registrada. Não há snapshot textual.

alter table public.movimentacoes
  add column localizacao_origem_id uuid references public.localizacoes (id) on delete restrict,
  add column localizacao_destino_id uuid references public.localizacoes (id) on delete restrict;

create index movimentacoes_localizacao_destino_idx
  on public.movimentacoes (localizacao_destino_id)
  where localizacao_destino_id is not null;

-- =============================================================================
-- 7. RPC: public.cadastrar_patrimonio — nova assinatura
-- =============================================================================
-- Assinatura antiga (15 parâmetros) — DROP explícito, ver cabeçalho do
-- arquivo sobre por que CREATE OR REPLACE não serve aqui.
drop function if exists public.cadastrar_patrimonio(
  uuid, uuid, text, text, text, text, text, text, date, uuid, text, text, text, text, timestamptz
);

-- Novos parâmetros (p_localizacao_destino_id, p_localizacao_origem_id)
-- acrescentados ao FINAL da lista, depois de p_data_movimentacao — mantém
-- compatibilidade posicional com quem porventura chame por posição, além
-- de deixar claro no diff que nada antigo mudou de lugar.
create function public.cadastrar_patrimonio(
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
  p_data_movimentacao timestamptz default null,
  p_localizacao_destino_id uuid default null,
  p_localizacao_origem_id uuid default null
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
  v_localizacao_destino_setor uuid;
  v_localizacao_destino_ativo boolean;
  v_localizacao_origem_setor uuid;
  v_patrimonio public.patrimonios;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para cadastrar patrimônio'
      using errcode = '42501';
  end if;

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

  -- FOR SHARE: o destino não pode ser desativado até este cadastro terminar
  select s.ativo into v_destino_ativo
  from public.setores s
  where s.id = p_destino_id
  for share;

  if v_destino_ativo is not true then
    raise exception 'Setor de destino inexistente ou inativo'
      using errcode = 'P0001';
  end if;

  -- Localização de destino: opcional, mas quando informada precisa estar
  -- ativa e pertencer ao MESMO setor de destino — nunca uma localização
  -- "solta" de outra gerência. FOR SHARE trava contra desativação
  -- concorrente, igual ao setor.
  if p_localizacao_destino_id is not null then
    select l.setor_id, l.ativo into v_localizacao_destino_setor, v_localizacao_destino_ativo
    from public.localizacoes l
    where l.id = p_localizacao_destino_id
    for share;

    if v_localizacao_destino_setor is null then
      raise exception 'Localização de destino não encontrada'
        using errcode = 'P0002';
    end if;
    if v_localizacao_destino_ativo is not true then
      raise exception 'Localização de destino inativa'
        using errcode = 'P0001';
    end if;
    if v_localizacao_destino_setor <> p_destino_id then
      raise exception 'A localização de destino informada não pertence ao setor de destino'
        using errcode = 'P0001';
    end if;
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

  -- Localização de origem: também histórica (pode estar inativa), mas só
  -- faz sentido junto de uma origem, e precisa pertencer a ELA.
  if p_localizacao_origem_id is not null then
    if p_origem_id is null then
      raise exception 'localizacao_origem_id informado sem origem_id'
        using errcode = 'P0001';
    end if;
    select l.setor_id into v_localizacao_origem_setor
    from public.localizacoes l
    where l.id = p_localizacao_origem_id;

    if v_localizacao_origem_setor is null then
      raise exception 'Localização de origem não encontrada'
        using errcode = 'P0002';
    end if;
    if v_localizacao_origem_setor <> p_origem_id then
      raise exception 'A localização de origem informada não pertence ao setor de origem'
        using errcode = 'P0001';
    end if;
  end if;

  -- checagem amigável; o índice único é a defesa real contra corrida
  if v_numero is not null and exists (
    select 1 from public.patrimonios p where p.numero_patrimonio = v_numero
  ) then
    raise exception 'Já existe um patrimônio com o número %', v_numero
      using errcode = '23505';
  end if;

  -- setor = destino, responsável = responsável de destino
  insert into public.patrimonios (
    numero_patrimonio, numero_serie, tipo_id, marca, modelo, descricao,
    observacao, status, setor_atual_id, localizacao_atual_id, responsavel_atual,
    data_aquisicao, criado_por
  ) values (
    v_numero, p_numero_serie, p_tipo_id, p_marca, p_modelo, p_descricao,
    p_observacao,
    (case when v_responsavel_destino is null then 'DISPONIVEL' else 'EM_USO' end)::public.patrimonio_status,
    p_destino_id, p_localizacao_destino_id, v_responsavel_destino, p_data_aquisicao,
    auth.uid()
  )
  returning * into v_patrimonio;

  -- movimentação inicial
  insert into public.movimentacoes (
    patrimonio_id, tipo, origem_id, localizacao_origem_id, responsavel_origem,
    destino_id, localizacao_destino_id, responsavel_destino, motivo, observacao,
    realizado_por, data_movimentacao
  ) values (
    v_patrimonio.id, 'ENTRADA', p_origem_id, p_localizacao_origem_id, public.normalize_text(p_responsavel_origem),
    p_destino_id, p_localizacao_destino_id, v_responsavel_destino, p_motivo, p_observacao_movimentacao,
    auth.uid(), v_data
  );

  return v_patrimonio;
end;
$$;

revoke all on function public.cadastrar_patrimonio from public, anon, authenticated;
grant execute on function public.cadastrar_patrimonio to authenticated;

-- =============================================================================
-- 8. RPC: public.registrar_movimentacao — nova assinatura
-- =============================================================================
-- DROP da assinatura anterior (9 parâmetros), ver cabeçalho do arquivo.
drop function if exists public.registrar_movimentacao(
  uuid, public.movimentacao_tipo, uuid, text, text, text, text, text, timestamptz
);

create function public.registrar_movimentacao(
  p_patrimonio_id uuid,
  p_tipo public.movimentacao_tipo,
  p_destino_id uuid default null,
  p_responsavel_destino text default null,
  p_motivo text default null,
  p_observacao text default null,
  p_numero_documento text default null,
  p_numero_chamado text default null,
  p_data_movimentacao timestamptz default null,
  p_localizacao_destino_id uuid default null,
  -- null NÃO significa "limpar" — significa "preservar o valor atual"
  -- (semântica já usada pelos outros campos opcionais). Para "limpar a
  -- localização sem mudar de setor" é preciso um sinal explícito, daí este
  -- booleano em vez de sobrecarregar p_localizacao_destino_id.
  p_limpar_localizacao boolean default false
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
  v_setor_para_localizacao uuid;
  v_localizacao_destino_setor uuid;
  v_localizacao_destino_ativo boolean;
  v_novo_setor uuid;
  v_novo_localizacao uuid;
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

  -- p_limpar_localizacao só existe para AJUSTE_INVENTARIO; checagem
  -- independente de setor/patrimônio, então roda antes de travar a linha.
  if p_limpar_localizacao is true and p_tipo <> 'AJUSTE_INVENTARIO' then
    raise exception 'limpar_localizacao só é permitido em AJUSTE_INVENTARIO'
      using errcode = 'P0001';
  end if;

  if p_limpar_localizacao is true and p_localizacao_destino_id is not null then
    raise exception 'limpar_localizacao e localizacao_destino_id não podem ser usados juntos'
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

  -- setor contra o qual a localização de destino (se informada) precisa
  -- ser validada: o próprio destino quando existe, senão o setor atual do
  -- patrimônio (AJUSTE_INVENTARIO pode mudar só a localização, sem mudar
  -- de setor — nesse caso p_destino_id vem null).
  v_setor_para_localizacao := coalesce(p_destino_id, v_patrimonio.setor_atual_id);

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
  -- Regras de destino/responsável/localização por tipo
  -- -------------------------------------------------------------------------
  if p_tipo in (
    'ENTRADA', 'SAIDA', 'EMPRESTIMO', 'DEVOLUCAO', 'MANUTENCAO', 'RETORNO_MANUTENCAO'
  ) then
    -- deslocamento físico entre setores: destino obrigatório e diferente
    -- do setor atual (estes tipos não têm o conceito de "movimentação
    -- interna"; só TRANSFERENCIA, abaixo).
    if p_destino_id is null then
      raise exception 'O tipo % exige destino_id', p_tipo
        using errcode = 'P0001';
    end if;
    if p_destino_id = v_patrimonio.setor_atual_id then
      raise exception 'Destino igual ao setor atual do patrimônio não é permitido para %', p_tipo
        using errcode = 'P0001';
    end if;
  elsif p_tipo = 'TRANSFERENCIA' then
    -- TRANSFERENCIA cobre dois cenários sem novo enum: destino_id é sempre
    -- obrigatório, e para "movimentação interna" o cliente envia
    -- explicitamente o MESMO setor atual (nunca null), deixando a intenção
    -- inequívoca — quem decide o rótulo é a UI, comparando origem/destino.
    if p_destino_id is null then
      raise exception 'TRANSFERENCIA exige destino_id (o mesmo setor atual para movimentação interna, ou outro setor para transferência entre gerências)'
        using errcode = 'P0001';
    end if;

    if p_destino_id = v_patrimonio.setor_atual_id then
      -- movimentação interna: setor não muda, então TEM que mudar a
      -- localização — senão a "transferência" não faz nada.
      if p_localizacao_destino_id is null then
        raise exception 'Movimentação interna (mesmo setor) exige localizacao_destino_id'
          using errcode = 'P0001';
      end if;
      if p_localizacao_destino_id is not distinct from v_patrimonio.localizacao_atual_id then
        raise exception 'A localização de destino precisa ser diferente da localização atual'
          using errcode = 'P0001';
      end if;
    end if;
    -- quando o setor muda (transferência entre gerências), localização de
    -- destino é opcional — validada abaixo, junto com os demais tipos.
  elsif p_tipo = 'BAIXA' then
    -- não há destino: último setor, localização e responsável são preservados
    if p_destino_id is not null or v_responsavel_destino is not null or p_localizacao_destino_id is not null then
      raise exception 'BAIXA não aceita destino_id, localizacao_destino_id nem responsavel_destino'
        using errcode = 'P0001';
    end if;
  elsif p_tipo = 'AJUSTE_INVENTARIO' then
    if v_responsavel_destino is not null then
      raise exception 'AJUSTE_INVENTARIO não altera o responsável'
        using errcode = 'P0001';
    end if;
    -- BAIXADO pode registrar AJUSTE_INVENTARIO (ex.: só para documentar
    -- motivo/observação), mas o ajuste NUNCA pode alterar o estado
    -- operacional preservado pela BAIXA — nem setor, nem localização.
    if v_patrimonio.status = 'BAIXADO' then
      if p_destino_id is not null and p_destino_id <> v_patrimonio.setor_atual_id then
        raise exception 'Patrimônio baixado não pode mudar de setor'
          using errcode = 'P0001';
      end if;
      if p_localizacao_destino_id is not null
         and p_localizacao_destino_id is distinct from v_patrimonio.localizacao_atual_id then
        raise exception 'Patrimônio baixado não pode mudar de localização'
          using errcode = 'P0001';
      end if;
      if p_limpar_localizacao is true then
        raise exception 'Patrimônio baixado não pode limpar a localização'
          using errcode = 'P0001';
      end if;
    end if;
  elsif p_tipo = 'ALTERACAO_RESPONSAVEL' then
    -- não representa deslocamento físico: setor e localização permanecem
    -- os mesmos, então nenhum dos dois é aceito como parâmetro.
    if p_destino_id is not null then
      raise exception 'ALTERACAO_RESPONSAVEL não aceita destino_id — o setor não muda'
        using errcode = 'P0001';
    end if;
    if p_localizacao_destino_id is not null then
      raise exception 'ALTERACAO_RESPONSAVEL não aceita localizacao_destino_id — a localização não muda'
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

  -- Localização de destino (quando informada): precisa estar ativa e
  -- pertencer ao setor-alvo calculado acima. BAIXA/ALTERACAO_RESPONSAVEL já
  -- garantiram acima que este parâmetro chega null. FOR SHARE: mesma
  -- proteção de concorrência do setor.
  if p_localizacao_destino_id is not null then
    select l.setor_id, l.ativo into v_localizacao_destino_setor, v_localizacao_destino_ativo
    from public.localizacoes l
    where l.id = p_localizacao_destino_id
    for share;

    if v_localizacao_destino_setor is null then
      raise exception 'Localização de destino não encontrada'
        using errcode = 'P0002';
    end if;
    if v_localizacao_destino_ativo is not true then
      raise exception 'Localização de destino inativa'
        using errcode = 'P0001';
    end if;
    if v_localizacao_destino_setor <> v_setor_para_localizacao then
      raise exception 'A localização de destino informada não pertence ao setor de destino'
        using errcode = 'P0001';
    end if;
  end if;

  -- -------------------------------------------------------------------------
  -- Estado resultante
  -- -------------------------------------------------------------------------
  case p_tipo
    when 'ENTRADA', 'SAIDA', 'TRANSFERENCIA', 'DEVOLUCAO', 'RETORNO_MANUTENCAO' then
      v_novo_setor := p_destino_id;
      v_novo_localizacao := p_localizacao_destino_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := (case when v_responsavel_destino is null then 'DISPONIVEL' else 'EM_USO' end)::public.patrimonio_status;
    when 'EMPRESTIMO' then
      v_novo_setor := p_destino_id;
      v_novo_localizacao := p_localizacao_destino_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := 'EMPRESTADO';
    when 'MANUTENCAO' then
      v_novo_setor := p_destino_id;
      v_novo_localizacao := p_localizacao_destino_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := 'EM_MANUTENCAO';
    when 'ALTERACAO_RESPONSAVEL' then
      -- setor e localização inalterados por definição
      v_novo_setor := v_patrimonio.setor_atual_id;
      v_novo_localizacao := v_patrimonio.localizacao_atual_id;
      v_novo_responsavel := v_responsavel_destino;
      v_novo_status := 'EM_USO';
    when 'BAIXA' then
      v_novo_setor := v_patrimonio.setor_atual_id;
      v_novo_localizacao := v_patrimonio.localizacao_atual_id;
      v_novo_responsavel := v_patrimonio.responsavel_atual;
      v_novo_status := 'BAIXADO';
    when 'AJUSTE_INVENTARIO' then
      -- em BAIXADO, destino só pode ser nulo ou o próprio setor atual
      -- (validado acima), então setor nunca muda nesse caso; status nunca
      -- muda (sem reativação por ajuste).
      v_novo_setor := coalesce(p_destino_id, v_patrimonio.setor_atual_id);
      -- ordem de prioridade: localização nova explícita > limpeza explícita
      -- > setor mudou sem localização nova (limpa, para não deixar
      -- referência órfã de outra gerência) > nada mudou (preserva).
      v_novo_localizacao := case
        when p_localizacao_destino_id is not null then p_localizacao_destino_id
        when p_limpar_localizacao is true then null
        when p_destino_id is not null and p_destino_id <> v_patrimonio.setor_atual_id then null
        else v_patrimonio.localizacao_atual_id
      end;
      v_novo_responsavel := v_patrimonio.responsavel_atual;
      v_novo_status := v_patrimonio.status;
  end case;

  insert into public.movimentacoes (
    patrimonio_id, tipo, origem_id, localizacao_origem_id, responsavel_origem,
    destino_id, localizacao_destino_id, responsavel_destino, motivo, observacao,
    numero_documento, numero_chamado, realizado_por, data_movimentacao
  ) values (
    v_patrimonio.id, p_tipo, v_patrimonio.setor_atual_id, v_patrimonio.localizacao_atual_id, v_patrimonio.responsavel_atual,
    case when p_tipo = 'BAIXA' then null else v_novo_setor end,
    case when p_tipo = 'BAIXA' then null else v_novo_localizacao end,
    case when p_tipo = 'BAIXA' then null else v_novo_responsavel end,
    p_motivo, p_observacao,
    p_numero_documento, p_numero_chamado, auth.uid(), v_data
  )
  returning * into v_movimentacao;

  update public.patrimonios
  set setor_atual_id = v_novo_setor,
      localizacao_atual_id = v_novo_localizacao,
      responsavel_atual = v_novo_responsavel,
      status = v_novo_status
  where id = v_patrimonio.id;

  return v_movimentacao;
end;
$$;

revoke all on function public.registrar_movimentacao from public, anon, authenticated;
grant execute on function public.registrar_movimentacao to authenticated;

-- =============================================================================
-- 9. GRANTS E RLS: public.localizacoes
-- =============================================================================
-- Mesmo tratamento de `public.setores`: revoga tudo primeiro (default
-- privileges de projetos Supabase podem conceder acesso amplo por
-- engano), depois concede só o necessário.

revoke all on table public.localizacoes from public, anon, authenticated;

grant select on public.localizacoes to authenticated;
-- id/criado_em/atualizado_em/ativo(no insert) são sempre do banco; sem
-- DELETE (exclusão lógica); setor_id só é gravável no INSERT — o UPDATE
-- não o inclui (trigger protect_localizacao_setor é a segunda camada).
grant insert (setor_id, nome, sigla) on public.localizacoes to authenticated;
grant update (nome, sigla, ativo) on public.localizacoes to authenticated;

alter table public.localizacoes enable row level security;

-- Leitura: mesmo público de setores (ADMIN/GESTOR/OPERADOR/CONSULTA).
create policy localizacoes_select on public.localizacoes
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

-- Escrita: só ADMIN/GESTOR, igual a setores. OPERADOR/CONSULTA são
-- somente leitura.
create policy localizacoes_insert on public.localizacoes
  for insert to authenticated
  with check ((select private.has_perfil('ADMIN', 'GESTOR')));

create policy localizacoes_update on public.localizacoes
  for update to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR')))
  with check ((select private.has_perfil('ADMIN', 'GESTOR')));

-- anon: nenhuma policy e nenhum GRANT → zero acesso, igual às demais
-- tabelas. Sem policy de DELETE (e sem GRANT de DELETE) — exclusão lógica
-- apenas, igual a setores/tipos_patrimonio.

-- =============================================================================
-- 10. DEFAULT PRIVILEGES
-- =============================================================================
-- Não precisa repetir aqui: a migration inicial já roda
-- `alter default privileges for role postgres in schema public/private
-- revoke ...` para TODOS os objetos futuros criados pelo role `postgres` —
-- isso já cobre a tabela e as funções criadas por esta migration.
