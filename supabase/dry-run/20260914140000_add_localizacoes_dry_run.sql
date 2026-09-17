-- =============================================================================
-- DRY-RUN — supabase/migrations/20260914140000_add_localizacoes.sql
--
-- NÃO É UMA MIGRATION. Não fica em supabase/migrations/ de propósito, para
-- nunca ser aplicado automaticamente por CLI/deploy.
--
-- O QUE ESTE ARQUIVO FAZ:
--   BEGIN;
--   [conteúdo EXATO da migration aprovada, copiado sem nenhuma alteração]
--   [bateria de testes: estrutura, constraints, RPCs, RLS/grants]
--   ROLLBACK;
--   [consultas somente-leitura, fora da transação, confirmando que nada
--    permaneceu — nem o schema novo, nem os dados ZZ_DRYRUN_*]
--
-- Todo dado criado durante o teste usa o prefixo ZZ_DRYRUN_ (gerências,
-- localizações) ou ZZDRYRUN- (número de patrimônio) e é destruído pelo
-- ROLLBACK. Nenhum dado real é tocado.
--
-- COMO EXECUTAR (seção 25 do pedido — não é executado automaticamente):
--   1. Abrir no SQL Editor do Supabase (projeto real).
--   2. Colar o conteúdo INTEIRO deste arquivo e rodar de uma vez.
--   3. Ler a aba "Messages"/"Notices" do resultado: cada teste imprime uma
--      linha `NOTICE: OK - <descrição>` em caso de sucesso. Qualquer
--      `ERROR: FALHA - ...` interrompe a execução ali (a transação inteira
--      ainda é desfeita — nada fica gravado — mas os testes seguintes não
--      rodam; nesse caso, reporte qual foi a última linha "OK" impressa).
--   4. Ao final, conferir as últimas linhas ("pós-ROLLBACK") confirmando
--      que public.localizacoes NÃO existe mais e que nenhum ZZ_DRYRUN
--      permanece.
--
-- SIMULAÇÃO DE auth.uid() (seção 3 do pedido):
--   As RPCs desta migration chamam auth.uid() e private.has_perfil(...),
--   que leem o claim `sub` do "JWT" via os parâmetros de sessão
--   `request.jwt.claim.sub` (Supabase define auth.uid() como
--   `coalesce(current_setting('request.jwt.claim.sub', true),
--   (current_setting('request.jwt.claims', true)::jsonb->>'sub'))::uuid`).
--   Este script localiza um profile ADMIN ativo JÁ EXISTENTE (nunca cria
--   usuário novo no Supabase Auth) e usa `set_config(..., true)` — o
--   equivalente a SET LOCAL, revertido automaticamente no ROLLBACK — para
--   simular esse claim, e `SET LOCAL ROLE authenticated` para que as
--   policies de RLS realmente sejam avaliadas (o role `postgres`/dono das
--   tabelas é isento de RLS por padrão; `authenticated` não é).
--
--   PREMISSA/RISCO (ver relatório, item "riscos/limitações"): este padrão
--   assume que o role usado pelo SQL Editor (tipicamente `postgres`) é
--   membro do role `authenticated` no projeto, permitindo `SET ROLE`. Esse
--   é o padrão documentado do Supabase para testar RLS via SQL Editor. Se
--   o `SET LOCAL ROLE authenticated;` abaixo falhar com erro de permissão,
--   PARE e reporte — não existe workaround seguro para contornar isso
--   improvisando (ex.: criar usuário Auth permanente), conforme instruído.
--
-- IDs de profiles reais NUNCA são impressos (seção 3) — só usados
-- internamente via variáveis/GUCs de sessão.
-- =============================================================================

begin;

-- =============================================================================
-- PARTE 1 — CONTEÚDO EXATO DA MIGRATION APROVADA
-- (supabase/migrations/20260914140000_add_localizacoes.sql, sem alterações)
-- =============================================================================

-- =============================================================================
-- InvTec — suporte a Localizações dentro de um Setor/Gerência.
--
-- IMPORTANTE: esta migration ainda NÃO foi aplicada no Supabase remoto.
-- Revise antes de aplicar. Não modifica as migrations já aplicadas
-- (20260910120000_initial_schema.sql, 20260911130000_update_tipos_...sql).
--
-- CONTEXTO DE NEGÓCIO: `public.setores` passa a representar a unidade
-- organizacional / gerência responsável (ex.: GETEC, GEVEV) — a tabela NÃO
-- é renomeada. Uma localização (ex.: "Home Office", "Datacenter -
-- Universitário") sempre pertence a exatamente uma gerência e é OPCIONAL
-- para um patrimônio. Nenhuma localização real é criada por esta migration
-- (ela é só estrutura) — ver seção "SEED" ausente de propósito.
--
-- Esta migration troca a assinatura de `cadastrar_patrimonio` e
-- `registrar_movimentacao` (novos parâmetros de localização). PostgreSQL
-- `CREATE OR REPLACE FUNCTION` NÃO permite mudar a lista de parâmetros de
-- uma função existente — usar CREATE OR REPLACE aqui criaria um SEGUNDO
-- overload, deixando a versão antiga (sem validação de localização)
-- chamável e com seus GRANTs intactos. Por isso: DROP explícito da
-- assinatura antiga + CREATE da nova + REAPLICAÇÃO explícita de
-- REVOKE/GRANT (DROP remove os grants da função removida).
--
-- OPERACIONAL (fora do escopo desta migration em si): depois de aplicar,
-- o PostgREST precisa recarregar o cache de esquema para reconhecer as
-- novas assinaturas de RPC — `NOTIFY pgrst, 'reload schema';` ou reiniciar
-- via painel (Settings → API → Reload schema cache).
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

-- Unicidade é POR GERÊNCIA, nunca global (seção 4 da especificação): a
-- mesma "Home Office" pode existir em GETEC e em GEVEV como localizações
-- distintas; duas "Home Office" dentro da MESMA gerência é que é inválido.
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

-- Seção 5: depois de criada, a gerência de uma localização é imutável —
-- sem exceção (nem para ADMIN via edição direta). Se foi cadastrada na
-- gerência errada, o fluxo correto é desativar e recriar na gerência
-- certa (preserva coerência histórica das movimentações que já a
-- referenciam). Diferente de `protect_patrimonio_columns`, não existe
-- aqui um "caminho administrativo" que possa contornar isso — a regra é
-- absoluta, então não checamos current_user.
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

-- Seção 6: mesma filosofia de `private.prevent_deactivate_setor_em_uso` —
-- Trigger (não CHECK, que não pode consultar outra tabela). SECURITY
-- DEFINER para contar patrimônios independentemente da RLS do chamador.
-- Fica em `private`: função de trigger, nunca endpoint RPC.
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

-- Revisão pós-entrega (seção 1 da correção): uma gerência inativa não pode
-- ganhar localização ativa — nem por criação (localização nasce ativa por
-- padrão) nem por reativação (ativo false → true). FOR SHARE na linha de
-- public.setores: uma desativação concorrente do setor faz UPDATE, que
-- toma lock de linha automaticamente — então esta checagem sempre
-- serializa contra ela, em qualquer ordem de entrelaçamento das duas
-- transações. Resultado: nunca sobra setor inativo + localização ativa.
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
-- 5. ALTERAÇÃO: public.patrimonios (seção 8)
-- =============================================================================
-- Nullable: localização é sempre OPCIONAL. Patrimônios já existentes
-- continuam válidos com localizacao_atual_id = null (seção 41) — ALTER
-- TABLE ADD COLUMN nullable sem DEFAULT não reescreve/bloqueia a tabela
-- para valores existentes, todos nascem null.

alter table public.patrimonios
  add column localizacao_atual_id uuid references public.localizacoes (id) on delete restrict;

create index patrimonios_localizacao_atual_idx on public.patrimonios (localizacao_atual_id);

-- Seção 9: quando localizacao_atual_id não é null, ela DEVE pertencer ao
-- setor_atual_id do mesmo patrimônio — CHECK não pode consultar outra
-- tabela, então isso é uma trigger. Dispara em INSERT (cadastrar_patrimonio)
-- e sempre que setor_atual_id OU localizacao_atual_id mudar (UPDATE feito
-- por registrar_movimentacao) — defesa em profundidade mesmo que a lógica
-- da RPC tenha um bug futuro.
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

-- Seção 10: mesma proteção já aplicada a status/setor_atual_id/
-- responsavel_atual — localizacao_atual_id só muda por movimentação
-- registrada (RPC SECURITY DEFINER), nunca por UPDATE direto do cliente.
-- Reaplica a função inteira (CREATE OR REPLACE mantém o mesmo nome e a
-- mesma trigger `trg_patrimonios_protect_columns` já criada na migration
-- inicial passa a usar este corpo automaticamente).
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
-- lista de colunas de UPDATE liberadas ao cliente (ver seção 8 dos GRANTS
-- abaixo) — igual a setor_atual_id/status hoje.

-- Seção 7: setor/gerência não pode ser desativado com localização ATIVA
-- vinculada (além da regra já existente de patrimônio não baixado).
-- Reaplica a função inteira (mesma trigger já existente passa a usar este
-- corpo).
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
-- 6. ALTERAÇÃO: public.movimentacoes (seções 11/12)
-- =============================================================================
-- Nullable: histórico já existente continua válido com null (seção 41).
-- ON DELETE RESTRICT, nunca CASCADE — e localizacoes nunca é apagada de
-- fato (exclusão lógica).
--
-- IMPORTANTE sobre o que a FK realmente preserva (seção 6 da correção): ela
-- preserva a IDENTIDADE da localização (o id), não um retrato textual do
-- nome no momento da movimentação. localizacao_origem_id/destino_id
-- continuam válidos e consultáveis mesmo depois de a localização ser
-- desativada (ela nunca é apagada), mas se ela for RENOMEADA, uma consulta
-- futura do histórico (join por id) mostra o nome ATUAL da entidade, não o
-- nome que existia quando a movimentação foi registrada. Esta migration não
-- implementa snapshot textual (ex.: gravar o nome como string solta na
-- movimentação) — se isso vier a ser necessário, é uma etapa futura
-- separada, não faz parte desta correção.

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

  -- Localização de destino (seção 9/13 da spec de localizações): opcional,
  -- mas quando informada precisa estar ativa e pertencer ao MESMO setor de
  -- destino — nunca uma localização "solta" de outra gerência. FOR SHARE
  -- trava contra desativação concorrente (seção 20), igual ao setor.
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
  -- faz sentido junto de uma origem, e precisa pertencer a ELA — carga
  -- inicial com origem totalmente desconhecida usa as duas como null
  -- (ver perfil GETEC no importador).
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

  -- 5 e 7. patrimônio: setor = destino, responsável = responsável de destino
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

  -- 6. movimentação inicial
  insert into public.movimentacoes (
    patrimonio_id, tipo, origem_id, localizacao_origem_id, responsavel_origem,
    destino_id, localizacao_destino_id, responsavel_destino, motivo, observacao,
    realizado_por, data_movimentacao
  ) values (
    v_patrimonio.id, 'ENTRADA', p_origem_id, p_localizacao_origem_id, public.normalize_text(p_responsavel_origem),
    p_destino_id, p_localizacao_destino_id, v_responsavel_destino, p_motivo, p_observacao_movimentacao,
    auth.uid(), v_data
  );

  -- 8.
  return v_patrimonio;
end;
$$;

revoke all on function public.cadastrar_patrimonio from public, anon, authenticated;
grant execute on function public.cadastrar_patrimonio to authenticated;

-- =============================================================================
-- 8. RPC: public.registrar_movimentacao — nova assinatura
-- =============================================================================
-- DROP visa a assinatura REALMENTE aplicada em produção (9 parâmetros) —
-- esta migration nunca foi aplicada, então não existe uma versão
-- intermediária de 10 parâmetros a se preocupar em remover; vai direto da
-- assinatura de produção para a final abaixo (11 parâmetros).
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
  -- Seção 2/3 da correção: null NÃO significa "limpar" — significa
  -- "preservar o valor atual" (semântica já usada por todos os outros
  -- campos opcionais desta função). Para representar "gerência mantida,
  -- localização passa a Não informada" é preciso um sinal explícito e
  -- inequívoco, daí este booleano dedicado em vez de sobrecarregar
  -- p_localizacao_destino_id com um terceiro estado.
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

  -- Seção 3 da correção: p_limpar_localizacao só existe para representar
  -- "localização passa a Não informada" em AJUSTE_INVENTARIO — checagem
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
  -- Matriz de transição (status atual → tipos permitidos) — inalterada.
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
    -- do setor atual — regra INALTERADA (estes tipos não ganharam o
    -- conceito de "movimentação interna"; só TRANSFERENCIA, abaixo).
    if p_destino_id is null then
      raise exception 'O tipo % exige destino_id', p_tipo
        using errcode = 'P0001';
    end if;
    if p_destino_id = v_patrimonio.setor_atual_id then
      raise exception 'Destino igual ao setor atual do patrimônio não é permitido para %', p_tipo
        using errcode = 'P0001';
    end if;
  elsif p_tipo = 'TRANSFERENCIA' then
    -- Seções 17/18: TRANSFERENCIA agora cobre dois cenários sem novo enum.
    -- destino_id é sempre obrigatório: para "movimentação interna" o
    -- cliente envia explicitamente o MESMO setor atual (nunca null), para
    -- deixar a intenção inequívoca — quem decide o rótulo (Transferência
    -- entre gerências vs. Movimentação interna) é a UI, comparando
    -- origem/destino.
    if p_destino_id is null then
      raise exception 'TRANSFERENCIA exige destino_id (o mesmo setor atual para movimentação interna, ou outro setor para transferência entre gerências)'
        using errcode = 'P0001';
    end if;

    if p_destino_id = v_patrimonio.setor_atual_id then
      -- movimentação interna: setor não muda, então TEM que mudar a
      -- localização — senão a "transferência" não faz nada (seção 18).
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
    -- Seção 4 da correção: BAIXADO pode registrar AJUSTE_INVENTARIO (ex.:
    -- só para documentar motivo/observação), mas o ajuste NUNCA pode
    -- alterar o estado operacional preservado pela BAIXA — nem setor, nem
    -- localização (trocar OU limpar). Responsável já é rejeitado acima
    -- incondicionalmente, para qualquer status.
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

  -- Localização de destino (quando informada, para qualquer tipo que a
  -- aceite): precisa estar ativa e pertencer ao setor-alvo calculado
  -- acima. BAIXA/ALTERACAO_RESPONSAVEL já garantiram acima que este
  -- parâmetro chega null, então este bloco não afeta esses dois tipos.
  -- FOR SHARE: mesma proteção de concorrência do setor (seção 20).
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
      -- muda (sem reativação por ajuste, seção 19).
      v_novo_setor := coalesce(p_destino_id, v_patrimonio.setor_atual_id);
      -- Seção 3 da correção — regras (a)-(d), nesta ordem de prioridade:
      v_novo_localizacao := case
        -- (c) localização nova explícita: usa (já validada acima; e
        -- limpar/localizacao_destino_id são mutuamente exclusivos, então
        -- p_limpar_localizacao é sempre false aqui)
        when p_localizacao_destino_id is not null then p_localizacao_destino_id
        -- (a) limpeza explícita: "Não informada", mesmo sem trocar de setor
        when p_limpar_localizacao is true then null
        -- (b) setor mudou sem localização nova nem limpeza explícita: limpa
        -- de qualquer forma, para não deixar uma referência órfã de outra
        -- gerência (a trigger de consistência rejeitaria mesmo assim, mas
        -- de forma confusa)
        when p_destino_id is not null and p_destino_id <> v_patrimonio.setor_atual_id then null
        -- (d) nada mudou e limpar=false: preserva a localização atual
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
-- 9. GRANTS E RLS: public.localizacoes (seções 21/22)
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
-- Não precisa repetir aqui: a migration inicial já rodou
-- `alter default privileges for role postgres in schema public/private
-- revoke ...` para TODOS os objetos futuros criados pelo role `postgres`
-- (o role usado para aplicar migrations no Supabase) — isso já cobre a
-- tabela e as funções criadas por ESTA migration automaticamente. Os
-- GRANTs explícitos das seções 7-9 acima é que liberam o necessário.

-- =============================================================================
-- 11. TESTES CONCEITUAIS (revisão pós-entrega)
-- =============================================================================
-- Este ambiente não tem CLI/psql/pgTAP conectados a um Postgres real (nem
-- local nem remoto) — não há como rodar testes de integração de fato sem
-- violar a restrição de "não aplicar a migration, não escrever no Supabase
-- real". Os cenários abaixo documentam explicitamente o comportamento
-- esperado de cada regra desta migration, para serem executados como teste
-- de integração (ex.: pgTAP, ou script manual via SQL Editor) assim que a
-- migration for aplicada em um ambiente de staging/local — antes disso,
-- servem como especificação executável em prosa e já orientaram a
-- implementação acima.
--
-- --- Seção 1 — gerência inativa × localização ativa -------------------------
-- 1a. insert em localizacoes(setor_id = <setor ativo>, ativo = true)
--     → permitido.
-- 1b. insert em localizacoes(setor_id = <setor INATIVO>, ativo = true)
--     → rejeitado com "Não é possível criar ou reativar uma localização em
--       uma gerência inexistente ou inativa" (P0001).
-- 1c. update localizacoes set ativo = true where id = <localização
--     desativada de um setor ATIVO> → permitido.
-- 1d. update localizacoes set ativo = true where id = <localização
--     desativada de um setor INATIVO> → rejeitado, mesma mensagem de 1b.
-- 1e. corrida conceitual: sessão A abre transação e faz
--     `update setores set ativo = false where id = :setor` sem dar commit
--     ainda; sessão B tenta `insert into localizacoes (setor_id, ativo, ...)
--     values (:setor, true, ...)` nesse meio-tempo → B bloqueia no `for
--     share` até A terminar; se A der commit, B falha com a mensagem de 1b;
--     se A der rollback, B prossegue normalmente. Em nenhum caminho o
--     estado final tem setor inativo + localização ativa simultâneos.
--
-- --- Seções 2/3 — p_limpar_localizacao --------------------------------------
-- 2a. registrar_movimentacao(..., p_tipo => 'TRANSFERENCIA', ...,
--     p_limpar_localizacao => true) → rejeitado: "limpar_localizacao só é
--     permitido em AJUSTE_INVENTARIO".
-- 2b. registrar_movimentacao(..., p_tipo => 'AJUSTE_INVENTARIO',
--     p_localizacao_destino_id => <alguma localização>,
--     p_limpar_localizacao => true) → rejeitado: "limpar_localizacao e
--     localizacao_destino_id não podem ser usados juntos".
-- 3a. AJUSTE_INVENTARIO, patrimônio em GETEC/Home Office, p_destino_id =>
--     null, p_limpar_localizacao => true → patrimônio fica em
--     GETEC/localizacao_atual_id = null.
-- 3b. AJUSTE_INVENTARIO, p_destino_id => <outro setor>,
--     p_localizacao_destino_id => null, p_limpar_localizacao => false →
--     setor muda, localizacao_atual_id vira null (regra pré-existente,
--     evita referência órfã entre gerências).
-- 3c. AJUSTE_INVENTARIO, p_destino_id => null, p_localizacao_destino_id =>
--     <nova localização da mesma gerência> → troca só a localização,
--     mantém o setor.
-- 3d. AJUSTE_INVENTARIO, p_destino_id => null, p_localizacao_destino_id =>
--     null, p_limpar_localizacao => false → localizacao_atual_id
--     inalterada (preserva).
--
-- --- Seção 4 — patrimônio BAIXADO -------------------------------------------
-- 4a. patrimônio BAIXADO, AJUSTE_INVENTARIO com p_destino_id => <setor
--     diferente do atual> → rejeitado: "Patrimônio baixado não pode mudar
--     de setor" (já existia antes desta correção).
-- 4b. patrimônio BAIXADO, AJUSTE_INVENTARIO com p_localizacao_destino_id =>
--     <localização diferente da atual> → rejeitado: "Patrimônio baixado
--     não pode mudar de localização".
-- 4c. patrimônio BAIXADO, AJUSTE_INVENTARIO com p_limpar_localizacao =>
--     true → rejeitado: "Patrimônio baixado não pode limpar a
--     localização".
-- 4d. patrimônio BAIXADO, AJUSTE_INVENTARIO só com p_motivo/p_observacao
--     preenchidos (sem destino/localização/limpar) → permitido; setor,
--     localização, responsável e status do patrimônio permanecem
--     idênticos depois da chamada.
-- 4e. BAIXA em qualquer patrimônio não baixado → confere que o registro
--     resultante em patrimonios preserva setor_atual_id,
--     localizacao_atual_id e responsavel_atual do estado imediatamente
--     anterior (comportamento pré-existente, reconfirmado nesta revisão).
-- =============================================================================

-- =============================================================================
-- PARTE 2 — BATERIA DE TESTES (dentro da MESMA transação da PARTE 1)
-- =============================================================================
-- Convenção de saída: cada teste imprime UMA linha via RAISE NOTICE
-- 'OK - ...' em caso de sucesso, ou interrompe com RAISE EXCEPTION
-- 'FALHA - ...' em caso de comportamento inesperado. Um FALHA não deixa
-- nada gravado (a transação inteira ainda termina em ROLLBACK — ver rodapé
-- do arquivo), mas interrompe os testes seguintes: reporte a última linha
-- "OK" impressa antes do erro.

-- -----------------------------------------------------------------------------
-- Item 4 — validar estrutura (ainda como dono/postgres — introspecção pura)
-- -----------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.localizacoes') is null then
    raise exception 'FALHA - item 4: public.localizacoes não existe depois da migration';
  end if;
  raise notice 'OK - item 4: public.localizacoes existe';

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'patrimonios'
      and column_name = 'localizacao_atual_id'
  ) then
    raise exception 'FALHA - item 4: patrimonios.localizacao_atual_id não existe';
  end if;
  raise notice 'OK - item 4: patrimonios.localizacao_atual_id existe';

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'movimentacoes'
      and column_name = 'localizacao_origem_id'
  ) then
    raise exception 'FALHA - item 4: movimentacoes.localizacao_origem_id não existe';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'movimentacoes'
      and column_name = 'localizacao_destino_id'
  ) then
    raise exception 'FALHA - item 4: movimentacoes.localizacao_destino_id não existe';
  end if;
  raise notice 'OK - item 4: movimentacoes.localizacao_origem_id/destino_id existem';

  if (select count(*) from pg_constraint
      where conrelid = 'public.localizacoes'::regclass and contype = 'f'
        and confrelid = 'public.setores'::regclass) <> 1 then
    raise exception 'FALHA - item 4: localizacoes.setor_id não tem FK única para setores';
  end if;
  if (select count(*) from pg_constraint
      where conrelid = 'public.patrimonios'::regclass and contype = 'f'
        and confrelid = 'public.localizacoes'::regclass) <> 1 then
    raise exception 'FALHA - item 4: patrimonios.localizacao_atual_id não tem FK para localizacoes';
  end if;
  if (select count(*) from pg_constraint
      where conrelid = 'public.movimentacoes'::regclass and contype = 'f'
        and confrelid = 'public.localizacoes'::regclass) <> 2 then
    raise exception 'FALHA - item 4: movimentacoes deveria ter 2 FKs para localizacoes (origem e destino)';
  end if;
  raise notice 'OK - item 4: FKs apontam corretamente (localizacoes->setores, patrimonios->localizacoes, 2x movimentacoes->localizacoes)';

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'localizacoes'
      and indexname = 'localizacoes_setor_nome_key'
  ) then
    raise exception 'FALHA - item 4: índice único localizacoes_setor_nome_key não existe';
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'localizacoes'
      and indexname = 'localizacoes_setor_sigla_key'
  ) then
    raise exception 'FALHA - item 4: índice único localizacoes_setor_sigla_key não existe';
  end if;
  raise notice 'OK - item 4: índices únicos por gerência existem';
end $$;

-- -----------------------------------------------------------------------------
-- SETUP — localizar profile ADMIN ativo real (sem imprimir seu UUID) e
-- simular auth.uid() via GUC de sessão (set_config com is_local=true,
-- equivalente a SET LOCAL — revertido automaticamente no ROLLBACK).
-- -----------------------------------------------------------------------------
do $$
declare
  v_admin_id uuid;
  v_tipo_id uuid;
begin
  select id into v_admin_id
  from public.profiles
  where perfil = 'ADMIN' and ativo is true
  limit 1;

  if v_admin_id is null then
    raise exception 'FALHA - SETUP: nenhum profile ADMIN ativo encontrado neste projeto. Não é possível simular auth.uid() para testar as RPCs. Crie/ative um ADMIN antes de rodar este dry-run, ou reporte esta limitação.';
  end if;

  select id into v_tipo_id from public.tipos_patrimonio where nome = 'Notebook' limit 1;
  if v_tipo_id is null then
    raise exception 'FALHA - SETUP: tipo de patrimônio seed "Notebook" não encontrado (esperado pela migration inicial)';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::text, true);
  perform set_config('dryrun.admin_id', v_admin_id::text, true);
  perform set_config('dryrun.tipo_notebook', v_tipo_id::text, true);

  raise notice 'OK - SETUP: profile ADMIN ativo localizado internamente (id não impresso) e claim JWT simulado';
end $$;

-- Troca para o role authenticated — a partir daqui, RLS é de fato avaliada
-- (postgres, dono das tabelas, é isento de RLS por padrão). Se este comando
-- falhar, PARE: significa que o role usado pelo SQL Editor não é membro de
-- authenticated neste projeto, e nenhuma das seções abaixo que dependem de
-- RLS pode ser validada de forma confiável.
set local role authenticated;

do $$
begin
  if current_setting('request.jwt.claim.sub', true) is distinct from current_setting('dryrun.admin_id', true) then
    raise exception 'FALHA - SETUP: auth.uid() não resolveu para o ADMIN simulado depois de SET LOCAL ROLE authenticated';
  end if;
  if (select private.has_perfil('ADMIN', 'GESTOR')) is not true then
    raise exception 'FALHA - SETUP: private.has_perfil não reconheceu o ADMIN simulado como authenticated';
  end if;
  raise notice 'OK - SETUP: role authenticated ativo e has_perfil(ADMIN) confirma o contexto simulado';
end $$;

-- -----------------------------------------------------------------------------
-- Item 5 — gerência / localização: criar fixtures e testar unicidade
-- (a partir daqui, tudo roda como authenticated + ADMIN real, nunca como
-- postgres — item 3 do pedido)
-- -----------------------------------------------------------------------------
do $$
declare
  v_setor_a uuid;
  v_setor_b uuid;
  v_local_a1 uuid;
  v_local_a2 uuid;
  v_local_b1 uuid;
  v_erro text;
begin
  insert into public.setores (nome, sigla) values ('ZZ_DRYRUN_GERENCIA_A', 'ZZDA')
    returning id into v_setor_a;
  insert into public.setores (nome, sigla) values ('ZZ_DRYRUN_GERENCIA_B', 'ZZDB')
    returning id into v_setor_b;

  insert into public.localizacoes (setor_id, nome, sigla) values (v_setor_a, 'ZZ_DRYRUN_LOCAL_A1', 'ZZLA1')
    returning id into v_local_a1;
  insert into public.localizacoes (setor_id, nome) values (v_setor_a, 'ZZ_DRYRUN_LOCAL_A2')
    returning id into v_local_a2;
  insert into public.localizacoes (setor_id, nome) values (v_setor_b, 'ZZ_DRYRUN_LOCAL_B1')
    returning id into v_local_b1;

  perform set_config('dryrun.setor_a', v_setor_a::text, true);
  perform set_config('dryrun.setor_b', v_setor_b::text, true);
  perform set_config('dryrun.local_a1', v_local_a1::text, true);
  perform set_config('dryrun.local_a2', v_local_a2::text, true);
  perform set_config('dryrun.local_b1', v_local_b1::text, true);

  raise notice 'OK - item 5: fixtures criadas (2 gerências, 3 localizações) como authenticated+ADMIN';

  -- A / Local1 duplicado (mesmo nome, mesma gerência) → deve falhar
  begin
    insert into public.localizacoes (setor_id, nome) values (v_setor_a, 'ZZ_DRYRUN_LOCAL_A1');
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 5: nome duplicado na mesma gerência foi aceito (esperava violação de unicidade)';
  elsif v_erro not ilike '%localizacoes_setor_nome_key%' then
    raise exception 'FALHA - item 5: erro inesperado ao testar nome duplicado: %', v_erro;
  else
    raise notice 'OK - item 5: nome duplicado na mesma gerência rejeitado (%)', v_erro;
  end if;

  -- A / sigla ZZLA1 duplicada → deve falhar
  begin
    insert into public.localizacoes (setor_id, nome, sigla) values (v_setor_a, 'ZZ_DRYRUN_LOCAL_A1_OUTRO_NOME', 'ZZLA1');
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 5: sigla duplicada na mesma gerência foi aceita (esperava violação de unicidade)';
  elsif v_erro not ilike '%localizacoes_setor_sigla_key%' then
    raise exception 'FALHA - item 5: erro inesperado ao testar sigla duplicada: %', v_erro;
  else
    raise notice 'OK - item 5: sigla duplicada na mesma gerência rejeitada (%)', v_erro;
  end if;

  -- B / Local1 (mesmo nome "ZZ_DRYRUN_LOCAL_A1" já usado em A) → permitido
  begin
    insert into public.localizacoes (setor_id, nome) values (v_setor_b, 'ZZ_DRYRUN_LOCAL_A1');
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is not null then
    raise exception 'FALHA - item 5: mesmo nome em gerências diferentes foi rejeitado (deveria ser permitido): %', v_erro;
  end if;
  raise notice 'OK - item 5: mesmo nome de localização em gerências diferentes é permitido';
end $$;

-- -----------------------------------------------------------------------------
-- Item 6 — gerência imutável, em DUAS camadas independentes
--
-- Camada 1 (GRANT por coluna): o GRANT de UPDATE em localizacoes libera só
-- (nome, sigla, ativo) para authenticated — setor_id nunca está nessa
-- lista. Como authenticated+ADMIN, a tentativa de UPDATE de setor_id é
-- barrada pelo próprio motor de privilégios ANTES de qualquer trigger
-- rodar — o erro esperado aqui é "permission denied" (SQLSTATE 42501 /
-- insufficient_privilege), não a mensagem da trigger.
--
-- Camada 2 (trigger protect_localizacao_setor): para provar que a
-- integridade não depende só do GRANT — e continua valendo mesmo para uma
-- operação privilegiada que já passou pela checagem de coluna —, o mesmo
-- UPDATE é repetido como owner/postgres (RESET ROLE), que não está sujeito
-- a GRANT por coluna nos próprios objetos. Nesse caminho o UPDATE alcança
-- a trigger, que deve rejeitar com sua mensagem de negócio específica.
-- -----------------------------------------------------------------------------

-- Item 6A — camada de GRANT (como authenticated+ADMIN)
do $$
declare
  v_setor_b uuid := current_setting('dryrun.setor_b')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_sqlstate text;
begin
  begin
    update public.localizacoes set setor_id = v_setor_b where id = v_local_a1;
    v_sqlstate := null;
  exception
    when insufficient_privilege then
      get stacked diagnostics v_sqlstate = returned_sqlstate;
    when others then
      get stacked diagnostics v_sqlstate = returned_sqlstate;
      raise exception 'FALHA - item 6A: erro inesperado (esperava insufficient_privilege/42501): sqlstate=%, %', v_sqlstate, sqlerrm;
  end;
  if v_sqlstate is null then
    raise exception 'FALHA - item 6A: UPDATE de setor_id por authenticated foi aceito (o GRANT não deveria liberar essa coluna)';
  elsif v_sqlstate <> '42501' then
    raise exception 'FALHA - item 6A: SQLSTATE inesperado ao tentar alterar setor_id: %', v_sqlstate;
  else
    raise notice 'OK - item 6A: authenticated não possui permissão para alterar setor_id (SQLSTATE %)', v_sqlstate;
  end if;
end $$;

-- volta ao role administrativo do SQL Editor — GRANT por coluna não se
-- aplica a ele nos próprios objetos, então o UPDATE alcança a trigger.
reset role;

-- Item 6B — camada de trigger (como owner/postgres)
do $$
declare
  v_setor_b uuid := current_setting('dryrun.setor_b')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_erro text;
  v_sqlstate text;
begin
  begin
    update public.localizacoes set setor_id = v_setor_b where id = v_local_a1;
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
    get stacked diagnostics v_sqlstate = returned_sqlstate;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 6B: UPDATE de setor_id por owner/postgres foi aceito (a trigger deveria bloquear mesmo assim)';
  elsif v_sqlstate = '42501' and v_erro ilike '%gerência de uma localização não pode ser alterada%' then
    raise notice 'OK - item 6B: trigger impede alteração de setor_id mesmo por operação privilegiada (%)', v_erro;
  else
    raise exception 'FALHA - item 6B: erro inesperado ao tentar alterar setor_id como owner (esperava a mensagem da trigger protect_localizacao_setor): sqlstate=%, %', v_sqlstate, v_erro;
  end if;
end $$;

-- volta a authenticated+ADMIN para o restante da bateria de testes — o
-- claim JWT (GUC de sessão, independente de role) não se perde com
-- RESET ROLE / SET LOCAL ROLE, só o role muda.
set local role authenticated;

do $$
begin
  if current_setting('request.jwt.claim.sub', true) is distinct from current_setting('dryrun.admin_id', true) then
    raise exception 'FALHA - item 6: claim JWT do ADMIN simulado foi perdido depois de RESET ROLE / SET LOCAL ROLE authenticated';
  end if;
  if (select private.has_perfil('ADMIN', 'GESTOR')) is not true then
    raise exception 'FALHA - item 6: private.has_perfil não reconhece mais o ADMIN simulado depois da troca de role do item 6';
  end if;
  raise notice 'OK - item 6: de volta a authenticated+ADMIN, claim JWT preservado e has_perfil(ADMIN) confirmado';
end $$;

-- -----------------------------------------------------------------------------
-- Item 7 — gerência inativa: criação bloqueada; e fluxo
-- criar → desativar localização → desativar gerência → reativar (deve falhar)
-- -----------------------------------------------------------------------------
do $$
declare
  v_setor_inativa uuid;
  v_setor_c uuid;
  v_local_c1 uuid;
  v_erro text;
begin
  -- O GRANT de INSERT em setores libera só (nome, sigla, descricao) —
  -- ativo nunca é gravável no INSERT (nasce true por default; só muda via
  -- UPDATE). Criar já como ativo=false no INSERT violaria esse GRANT e
  -- falharia com "permission denied for table setores" por coluna, o que
  -- não testaria o cenário pretendido. Fluxo correto, que também é o único
  -- caminho real disponível para o app: criar ativa (default) e depois
  -- desativar via UPDATE — exatamente como qualquer gerência real seria
  -- desativada.
  insert into public.setores (nome, sigla) values ('ZZ_DRYRUN_GERENCIA_INATIVA', 'ZZDI')
    returning id into v_setor_inativa;

  update public.setores set ativo = false where id = v_setor_inativa;

  if exists (select 1 from public.setores where id = v_setor_inativa and ativo is true) then
    raise exception 'FALHA - item 7: ZZ_DRYRUN_GERENCIA_INATIVA deveria estar inativa antes do teste de criação de localização';
  end if;
  raise notice 'OK - item 7: ZZ_DRYRUN_GERENCIA_INATIVA criada ativa (default) e desativada via UPDATE, confirmada inativa';

  begin
    insert into public.localizacoes (setor_id, nome) values (v_setor_inativa, 'ZZ_DRYRUN_LOCAL_INATIVA_1');
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 7: criar localização ativa em gerência inativa foi aceito';
  elsif v_erro not ilike '%gerência inexistente ou inativa%' then
    raise exception 'FALHA - item 7: erro inesperado ao criar localização em gerência inativa: %', v_erro;
  else
    raise notice 'OK - item 7: criar localização ativa em gerência inativa é rejeitado (%)', v_erro;
  end if;

  -- fluxo: gerência C ativa -> localização C1 ativa -> desativar C1 ->
  -- desativar gerência C -> tentar reativar C1 (deve falhar)
  insert into public.setores (nome, sigla) values ('ZZ_DRYRUN_GERENCIA_C', 'ZZDC')
    returning id into v_setor_c;
  insert into public.localizacoes (setor_id, nome) values (v_setor_c, 'ZZ_DRYRUN_LOCAL_C1')
    returning id into v_local_c1;

  update public.localizacoes set ativo = false where id = v_local_c1;
  raise notice 'OK - item 7: localização C1 desativada (sem uso, permitido)';

  update public.setores set ativo = false where id = v_setor_c;
  raise notice 'OK - item 7: gerência C desativada (sem patrimônio nem localização ativa, permitido)';

  begin
    update public.localizacoes set ativo = true where id = v_local_c1;
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 7: reativar localização em gerência agora inativa foi aceito';
  elsif v_erro not ilike '%gerência inexistente ou inativa%' then
    raise exception 'FALHA - item 7: erro inesperado ao reativar localização em gerência inativa: %', v_erro;
  else
    raise notice 'OK - item 7: reativar localização em gerência inativa é rejeitado (%)', v_erro;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Itens 8 e 9 — cadastrar_patrimonio (RPC, como authenticated+ADMIN real):
-- cria o patrimônio 0001 em A/Local1, valida campos, valida a ENTRADA
-- gravada, valida rejeição de localização de outra gerência, e então usa
-- esse mesmo patrimônio para provar que desativar Local1/Gerência A falha
-- enquanto ele estiver ativo e vinculado (item 8).
-- -----------------------------------------------------------------------------
do $$
declare
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_setor_b uuid := current_setting('dryrun.setor_b')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_local_b1 uuid := current_setting('dryrun.local_b1')::uuid;
  v_tipo uuid := current_setting('dryrun.tipo_notebook')::uuid;
  v_patrimonio public.patrimonios;
  v_entrada public.movimentacoes;
  v_erro text;
begin
  v_patrimonio := public.cadastrar_patrimonio(
    p_tipo_id => v_tipo,
    p_destino_id => v_setor_a,
    p_numero_patrimonio => 'ZZDRYRUN-0001',
    p_localizacao_destino_id => v_local_a1
  );

  perform set_config('dryrun.patrimonio_0001', v_patrimonio.id::text, true);

  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id <> v_local_a1 then
    raise exception 'FALHA - item 9: cadastrar_patrimonio não gravou setor/localização de destino corretamente';
  end if;
  raise notice 'OK - item 9: cadastrar_patrimonio grava setor_atual_id e localizacao_atual_id corretos';

  select * into v_entrada
  from public.movimentacoes
  where patrimonio_id = v_patrimonio.id and tipo = 'ENTRADA';

  if v_entrada.origem_id is not null or v_entrada.localizacao_origem_id is not null then
    raise exception 'FALHA - item 9: ENTRADA sem origem informada deveria gravar origem_id e localizacao_origem_id nulos';
  end if;
  if v_entrada.destino_id <> v_setor_a or v_entrada.localizacao_destino_id <> v_local_a1 then
    raise exception 'FALHA - item 9: ENTRADA gravou destino_id/localizacao_destino_id incorretos';
  end if;
  raise notice 'OK - item 9: movimentação ENTRADA gravada com origem null e destino=A/Local1 corretos';

  -- localização de OUTRA gerência (B) usada como destino em A → rejeitado
  begin
    perform public.cadastrar_patrimonio(
      p_tipo_id => v_tipo,
      p_destino_id => v_setor_a,
      p_numero_patrimonio => 'ZZDRYRUN-9999-SHOULDFAIL',
      p_localizacao_destino_id => v_local_b1
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 9: localização de outra gerência como destino foi aceita';
  elsif v_erro not ilike '%não pertence ao setor de destino%' then
    raise exception 'FALHA - item 9: erro inesperado ao testar localização de outra gerência: %', v_erro;
  else
    raise notice 'OK - item 9: localização pertencente a outra gerência é rejeitada como destino (%)', v_erro;
  end if;
  if exists (select 1 from public.patrimonios where numero_patrimonio = 'ZZDRYRUN-9999-SHOULDFAIL') then
    raise exception 'FALHA - item 9: chamada rejeitada não deveria ter criado nenhuma linha em patrimonios';
  end if;

  -- item 8: desativar Local1 (em uso pelo patrimônio 0001, não baixado) → falha
  begin
    update public.localizacoes set ativo = false where id = v_local_a1;
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 8: desativar localização em uso (patrimônio não baixado) foi aceito';
  elsif v_erro not ilike '%não é possível desativar a localização%' then
    raise exception 'FALHA - item 8: erro inesperado ao desativar Local1 em uso: %', v_erro;
  else
    raise notice 'OK - item 8: desativar localização em uso por patrimônio não baixado é rejeitado (%)', v_erro;
  end if;

  -- item 8: desativar Gerência A (patrimônio ativo + localização ativa nela) → falha
  begin
    update public.setores set ativo = false where id = v_setor_a;
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 8: desativar gerência em uso foi aceito';
  elsif v_erro not ilike '%não é possível desativar o setor%' then
    raise exception 'FALHA - item 8: erro inesperado ao desativar Gerência A em uso: %', v_erro;
  else
    raise notice 'OK - item 8: desativar gerência em uso (patrimônio e/ou localização ativa) é rejeitado (%)', v_erro;
  end if;

  if not exists (select 1 from public.setores where id = v_setor_a and ativo is true) then
    raise exception 'FALHA - item 8: Gerência A não deveria ter sido desativada';
  end if;
  if not exists (select 1 from public.localizacoes where id = v_local_a1 and ativo is true) then
    raise exception 'FALHA - item 8: Local1 não deveria ter sido desativado';
  end if;
  raise notice 'OK - item 8: estado de Gerência A e Local1 permanece ativo depois das tentativas rejeitadas';
end $$;

-- -----------------------------------------------------------------------------
-- Item 10 — transferência interna (mesma gerência)
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0001')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_local_a2 uuid := current_setting('dryrun.local_a2')::uuid;
  v_mov public.movimentacoes;
  v_patrimonio public.patrimonios;
  v_erro text;
begin
  v_mov := public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'TRANSFERENCIA',
    p_destino_id => v_setor_a,
    p_localizacao_destino_id => v_local_a2
  );

  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;

  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id <> v_local_a2 then
    raise exception 'FALHA - item 10: transferência interna não resultou em gerência=A / localização=Local2';
  end if;
  if v_mov.destino_id <> v_setor_a or v_mov.localizacao_destino_id <> v_local_a2 then
    raise exception 'FALHA - item 10: movimentação de transferência interna não gravou destino/localização corretos';
  end if;
  raise notice 'OK - item 10: transferência interna move A/Local1 -> A/Local2, gerência inalterada';

  -- "A/Local2 -> A/Local2" (mesmo destino, mesma localização) → transferência vazia, deve falhar
  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'TRANSFERENCIA',
      p_destino_id => v_setor_a,
      p_localizacao_destino_id => v_local_a2
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 10: transferência interna vazia (mesmo destino/localização) foi aceita';
  elsif v_erro not ilike '%precisa ser diferente da localização atual%' then
    raise exception 'FALHA - item 10: erro inesperado ao testar transferência interna vazia: %', v_erro;
  else
    raise notice 'OK - item 10: transferência interna vazia (mesma localização) é rejeitada (%)', v_erro;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Item 11 — transferência entre gerências
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0001')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_setor_b uuid := current_setting('dryrun.setor_b')::uuid;
  v_local_a2 uuid := current_setting('dryrun.local_a2')::uuid;
  v_local_b1 uuid := current_setting('dryrun.local_b1')::uuid;
  v_mov public.movimentacoes;
  v_patrimonio public.patrimonios;
begin
  v_mov := public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'TRANSFERENCIA',
    p_destino_id => v_setor_b,
    p_localizacao_destino_id => v_local_b1
  );

  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;

  if v_patrimonio.setor_atual_id <> v_setor_b or v_patrimonio.localizacao_atual_id <> v_local_b1 then
    raise exception 'FALHA - item 11: transferência entre gerências não resultou em gerência=B / localização=B/Local1';
  end if;
  if v_mov.origem_id <> v_setor_a or v_mov.localizacao_origem_id <> v_local_a2
     or v_mov.destino_id <> v_setor_b or v_mov.localizacao_destino_id <> v_local_b1 then
    raise exception 'FALHA - item 11: histórico da transferência entre gerências não gravou origem/destino corretos';
  end if;
  raise notice 'OK - item 11: transferência entre gerências move A/Local2 -> B/Local1, histórico correto';

  -- B/Local1 -> A sem localização informada
  v_mov := public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'TRANSFERENCIA',
    p_destino_id => v_setor_a
  );

  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;

  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id is not null then
    raise exception 'FALHA - item 11: transferência entre gerências sem localização de destino deveria resultar em localizacao_atual_id = null';
  end if;
  raise notice 'OK - item 11: transferência entre gerências sem localização informada resulta em gerência=A / localização=null';
end $$;

-- -----------------------------------------------------------------------------
-- Itens 13/12/14 — AJUSTE_INVENTARIO: trocar, depois preservar, depois
-- limpar. Executados nesta ordem (13 antes de 12) para que exista uma
-- localização não nula a preservar no teste do item 12 — o rótulo de cada
-- bloco abaixo continua correspondendo ao número do pedido original.
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0001')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_patrimonio public.patrimonios;
begin
  -- item 13: AJUSTE troca localização (patrimônio está em A/null neste ponto)
  perform public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'AJUSTE_INVENTARIO',
    p_localizacao_destino_id => v_local_a1
  );
  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;
  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id <> v_local_a1 then
    raise exception 'FALHA - item 13: AJUSTE_INVENTARIO não trocou a localização para Local1 mantendo a gerência';
  end if;
  raise notice 'OK - item 13: AJUSTE_INVENTARIO troca a localização (gerência inalterada)';

  -- item 12: AJUSTE sem nada informado preserva a localização atual (Local1)
  perform public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'AJUSTE_INVENTARIO'
  );
  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;
  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id <> v_local_a1 then
    raise exception 'FALHA - item 12: AJUSTE_INVENTARIO sem parâmetros de localização deveria preservar Local1';
  end if;
  raise notice 'OK - item 12: AJUSTE_INVENTARIO sem localizacao_destino_id nem limpar preserva a localização atual';

  -- item 14: AJUSTE com limpar=true zera a localização
  perform public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'AJUSTE_INVENTARIO',
    p_limpar_localizacao => true
  );
  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;
  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id is not null then
    raise exception 'FALHA - item 14: AJUSTE_INVENTARIO com limpar_localizacao=true deveria zerar a localização mantendo a gerência';
  end if;
  raise notice 'OK - item 14: AJUSTE_INVENTARIO com limpar_localizacao=true zera a localização (gerência inalterada)';
end $$;

-- -----------------------------------------------------------------------------
-- Item 15 — ambiguidade
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0001')::uuid;
  v_setor_b uuid := current_setting('dryrun.setor_b')::uuid;
  v_local_a2 uuid := current_setting('dryrun.local_a2')::uuid;
  v_erro text;
begin
  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'AJUSTE_INVENTARIO',
      p_localizacao_destino_id => v_local_a2,
      p_limpar_localizacao => true
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 15: AJUSTE com localizacao_destino_id e limpar_localizacao=true juntos foi aceito';
  elsif v_erro not ilike '%não podem ser usados juntos%' then
    raise exception 'FALHA - item 15: erro inesperado no teste de ambiguidade (localização+limpar): %', v_erro;
  else
    raise notice 'OK - item 15: localizacao_destino_id + limpar_localizacao=true juntos é rejeitado (%)', v_erro;
  end if;

  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'TRANSFERENCIA',
      p_destino_id => v_setor_b,
      p_limpar_localizacao => true
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 15: limpar_localizacao=true em TRANSFERENCIA foi aceito';
  elsif v_erro not ilike '%só é permitido em AJUSTE_INVENTARIO%' then
    raise exception 'FALHA - item 15: erro inesperado ao testar limpar_localizacao fora de AJUSTE_INVENTARIO: %', v_erro;
  else
    raise notice 'OK - item 15: limpar_localizacao=true em tipo diferente de AJUSTE_INVENTARIO é rejeitado (%)', v_erro;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Item 16 — BAIXA (patrimônio 0002, dedicado)
-- -----------------------------------------------------------------------------
do $$
declare
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_tipo uuid := current_setting('dryrun.tipo_notebook')::uuid;
  v_patrimonio public.patrimonios;
  v_mov public.movimentacoes;
begin
  v_patrimonio := public.cadastrar_patrimonio(
    p_tipo_id => v_tipo,
    p_destino_id => v_setor_a,
    p_numero_patrimonio => 'ZZDRYRUN-0002',
    p_localizacao_destino_id => v_local_a1
  );
  perform set_config('dryrun.patrimonio_0002', v_patrimonio.id::text, true);

  v_mov := public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio.id,
    p_tipo => 'BAIXA'
  );

  select * into v_patrimonio from public.patrimonios where id = v_patrimonio.id;

  if v_patrimonio.status <> 'BAIXADO' then
    raise exception 'FALHA - item 16: BAIXA não resultou em status BAIXADO';
  end if;
  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id <> v_local_a1
     or v_patrimonio.responsavel_atual is not null then
    raise exception 'FALHA - item 16: BAIXA deveria preservar setor_atual_id, localizacao_atual_id e responsavel_atual';
  end if;
  raise notice 'OK - item 16: BAIXA preserva setor/localização/responsável e resulta em status BAIXADO';

  if v_mov.destino_id is not null or v_mov.localizacao_destino_id is not null or v_mov.responsavel_destino is not null then
    raise exception 'FALHA - item 16: movimentação BAIXA deveria gravar destino_id/localizacao_destino_id/responsavel_destino nulos';
  end if;
  raise notice 'OK - item 16: movimentação BAIXA grava destino_id/localizacao_destino_id/responsavel_destino nulos';
end $$;

-- -----------------------------------------------------------------------------
-- Item 17 — BAIXADO + AJUSTE_INVENTARIO
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0002')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_setor_b uuid := current_setting('dryrun.setor_b')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_local_a2 uuid := current_setting('dryrun.local_a2')::uuid;
  v_patrimonio public.patrimonios;
  v_erro text;
begin
  -- só motivo/observação -> permitido, sem mudança operacional
  perform public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'AJUSTE_INVENTARIO',
    p_motivo => 'ZZ_DRYRUN conferência de inventário',
    p_observacao => 'ZZ_DRYRUN sem alteração de estado'
  );
  raise notice 'OK - item 17: AJUSTE_INVENTARIO só com motivo/observação em patrimônio BAIXADO é permitido';

  -- tentar outro setor -> rejeitado
  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'AJUSTE_INVENTARIO',
      p_destino_id => v_setor_b
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 17: AJUSTE_INVENTARIO mudando o setor de um patrimônio BAIXADO foi aceito';
  elsif v_erro not ilike '%baixado não pode mudar de setor%' then
    raise exception 'FALHA - item 17: erro inesperado ao tentar mudar setor de BAIXADO: %', v_erro;
  else
    raise notice 'OK - item 17: AJUSTE_INVENTARIO não pode mudar o setor de um patrimônio BAIXADO (%)', v_erro;
  end if;

  -- tentar outra localização -> rejeitado
  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'AJUSTE_INVENTARIO',
      p_localizacao_destino_id => v_local_a2
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 17: AJUSTE_INVENTARIO mudando a localização de um patrimônio BAIXADO foi aceito';
  elsif v_erro not ilike '%baixado não pode mudar de localização%' then
    raise exception 'FALHA - item 17: erro inesperado ao tentar mudar localização de BAIXADO: %', v_erro;
  else
    raise notice 'OK - item 17: AJUSTE_INVENTARIO não pode mudar a localização de um patrimônio BAIXADO (%)', v_erro;
  end if;

  -- tentar limpar localização -> rejeitado
  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'AJUSTE_INVENTARIO',
      p_limpar_localizacao => true
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 17: AJUSTE_INVENTARIO limpando a localização de um patrimônio BAIXADO foi aceito';
  elsif v_erro not ilike '%baixado não pode limpar a localização%' then
    raise exception 'FALHA - item 17: erro inesperado ao tentar limpar localização de BAIXADO: %', v_erro;
  else
    raise notice 'OK - item 17: AJUSTE_INVENTARIO não pode limpar a localização de um patrimônio BAIXADO (%)', v_erro;
  end if;

  select * into v_patrimonio from public.patrimonios where id = v_patrimonio_id;
  if v_patrimonio.setor_atual_id <> v_setor_a or v_patrimonio.localizacao_atual_id <> v_local_a1
     or v_patrimonio.responsavel_atual is not null or v_patrimonio.status <> 'BAIXADO' then
    raise exception 'FALHA - item 17: estado operacional do patrimônio BAIXADO mudou depois das tentativas rejeitadas';
  end if;
  raise notice 'OK - item 17: estado operacional do patrimônio BAIXADO permanece idêntico depois de todas as tentativas rejeitadas';
end $$;

-- -----------------------------------------------------------------------------
-- Item 18 — ALTERACAO_RESPONSAVEL
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0001')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_patrimonio_antes public.patrimonios;
  v_patrimonio_depois public.patrimonios;
  v_erro text;
begin
  select * into v_patrimonio_antes from public.patrimonios where id = v_patrimonio_id;

  perform public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio_id,
    p_tipo => 'ALTERACAO_RESPONSAVEL',
    p_responsavel_destino => 'ZZ DRYRUN RESPONSAVEL'
  );

  select * into v_patrimonio_depois from public.patrimonios where id = v_patrimonio_id;

  if v_patrimonio_depois.setor_atual_id <> v_patrimonio_antes.setor_atual_id
     or v_patrimonio_depois.localizacao_atual_id is distinct from v_patrimonio_antes.localizacao_atual_id then
    raise exception 'FALHA - item 18: ALTERACAO_RESPONSAVEL alterou setor ou localização (deveria preservar ambos)';
  end if;
  if v_patrimonio_depois.responsavel_atual <> 'ZZ DRYRUN RESPONSAVEL' or v_patrimonio_depois.status <> 'EM_USO' then
    raise exception 'FALHA - item 18: ALTERACAO_RESPONSAVEL não resultou em responsável novo + status EM_USO';
  end if;
  raise notice 'OK - item 18: ALTERACAO_RESPONSAVEL preserva setor/localização, muda só o responsável, resulta em EM_USO';

  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'ALTERACAO_RESPONSAVEL',
      p_responsavel_destino => 'ZZ DRYRUN OUTRO RESPONSAVEL',
      p_localizacao_destino_id => v_local_a1
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 18: ALTERACAO_RESPONSAVEL com localizacao_destino_id foi aceito';
  elsif v_erro not ilike '%não aceita localizacao_destino_id%' then
    raise exception 'FALHA - item 18: erro inesperado ao passar localização em ALTERACAO_RESPONSAVEL: %', v_erro;
  else
    raise notice 'OK - item 18: ALTERACAO_RESPONSAVEL com localizacao_destino_id é rejeitado (%)', v_erro;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Item 19 — localização inativa como novo destino; referências históricas
-- -----------------------------------------------------------------------------
do $$
declare
  v_patrimonio_id uuid := current_setting('dryrun.patrimonio_0001')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_local_a2 uuid := current_setting('dryrun.local_a2')::uuid;
  v_local_inativa uuid;
  v_erro text;
  v_hist_ok boolean;
begin
  insert into public.localizacoes (setor_id, nome) values (v_setor_a, 'ZZ_DRYRUN_LOCAL_A_INATIVA')
    returning id into v_local_inativa;
  update public.localizacoes set ativo = false where id = v_local_inativa;

  begin
    perform public.registrar_movimentacao(
      p_patrimonio_id => v_patrimonio_id,
      p_tipo => 'TRANSFERENCIA',
      p_destino_id => v_setor_a,
      p_localizacao_destino_id => v_local_inativa
    );
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 19: usar localização inativa como novo destino foi aceito';
  elsif v_erro not ilike '%localização de destino inativa%' then
    raise exception 'FALHA - item 19: erro inesperado ao usar localização inativa como destino: %', v_erro;
  else
    raise notice 'OK - item 19: localização inativa como novo destino é rejeitada (%)', v_erro;
  end if;

  -- A2 não é mais o destino atual de nenhum patrimônio (patrimônio 0001
  -- passou por ela e seguiu adiante nas seções 10/11) — desativar deve
  -- funcionar, e o histórico antigo que a referencia continua válido.
  update public.localizacoes set ativo = false where id = v_local_a2;

  select exists (
    select 1
    from public.movimentacoes m
    join public.localizacoes l on l.id = m.localizacao_destino_id
    where m.patrimonio_id = v_patrimonio_id
      and m.localizacao_destino_id = v_local_a2
      and l.ativo is false
  ) into v_hist_ok;

  if not v_hist_ok then
    raise exception 'FALHA - item 19: histórico antigo referenciando Local2 deveria continuar consultável/joinável mesmo depois dela ser desativada';
  end if;
  raise notice 'OK - item 19: referência histórica a uma localização já desativada continua válida e consultável';
end $$;

-- -----------------------------------------------------------------------------
-- Item 20 — RLS por perfil (OPERADOR/CONSULTA/anon)
-- -----------------------------------------------------------------------------
do $$
declare
  v_operador_id uuid;
  v_consulta_id uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
begin
  select id into v_operador_id from public.profiles where perfil = 'OPERADOR' and ativo is true limit 1;
  select id into v_consulta_id from public.profiles where perfil = 'CONSULTA' and ativo is true limit 1;

  -- set_config com valor NULL não grava nada (current_setting continuaria
  -- "não definido") — usamos '' como sentinela explícita de "não
  -- encontrado" em vez de depender desse comportamento por acaso.
  perform set_config('dryrun.operador_id', coalesce(v_operador_id::text, ''), true);
  perform set_config('dryrun.consulta_id', coalesce(v_consulta_id::text, ''), true);

  if v_operador_id is null then
    raise notice 'LIMITACAO - item 20: nenhum profile OPERADOR ativo encontrado neste projeto; teste de RLS ao vivo para OPERADOR pulado (ver checagem de policies abaixo)';
  end if;
  if v_consulta_id is null then
    raise notice 'LIMITACAO - item 20: nenhum profile CONSULTA ativo encontrado neste projeto; teste de RLS ao vivo para CONSULTA pulado (ver checagem de policies abaixo)';
  end if;
end $$;

do $$
declare
  v_operador_id uuid := nullif(current_setting('dryrun.operador_id', true), '')::uuid;
  v_setor_a uuid := current_setting('dryrun.setor_a')::uuid;
  v_erro text;
begin
  if v_operador_id is null then
    return;
  end if;

  perform set_config('request.jwt.claim.sub', v_operador_id::text, true);

  begin
    insert into public.localizacoes (setor_id, nome) values (v_setor_a, 'ZZ_DRYRUN_LOCAL_OPERADOR_SHOULDFAIL');
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 20: OPERADOR conseguiu INSERT em localizacoes (deveria ser somente leitura)';
  else
    raise notice 'OK - item 20: OPERADOR não consegue INSERT em localizacoes (%)', v_erro;
  end if;

  -- restaura o claim ADMIN para o restante do script
  perform set_config('request.jwt.claim.sub', current_setting('dryrun.admin_id'), true);
end $$;

do $$
declare
  v_consulta_id uuid := nullif(current_setting('dryrun.consulta_id', true), '')::uuid;
  v_local_a1 uuid := current_setting('dryrun.local_a1')::uuid;
  v_erro text;
begin
  if v_consulta_id is null then
    return;
  end if;

  perform set_config('request.jwt.claim.sub', v_consulta_id::text, true);

  begin
    update public.localizacoes set ativo = false where id = v_local_a1;
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 20: CONSULTA conseguiu UPDATE em localizacoes (deveria ser somente leitura)';
  else
    raise notice 'OK - item 20: CONSULTA não consegue UPDATE em localizacoes (%)', v_erro;
  end if;

  perform set_config('request.jwt.claim.sub', current_setting('dryrun.admin_id'), true);
end $$;

-- anon: sem GRANT nenhum na tabela — deve falhar antes mesmo de avaliar RLS
set local role anon;

do $$
declare
  v_erro text;
begin
  begin
    perform 1 from public.localizacoes limit 1;
    v_erro := null;
  exception when others then
    v_erro := sqlerrm;
  end;
  if v_erro is null then
    raise exception 'FALHA - item 20: anon conseguiu SELECT em localizacoes (deveria não ter nenhum acesso)';
  else
    raise notice 'OK - item 20: anon não consegue SELECT em localizacoes (%)', v_erro;
  end if;
end $$;

reset role;

-- fallback/documentação via catálogo, independente de haver profiles reais
-- de cada perfil (pedido explícito do item 20 quando faltar fixture real)
do $$
declare
  r record;
begin
  raise notice 'INFO - item 20: policies de RLS cadastradas em public.localizacoes (para conferência manual):';
  for r in
    select policyname, cmd, roles::text as roles, qual::text as using_expr, with_check::text as with_check_expr
    from pg_policies
    where schemaname = 'public' and tablename = 'localizacoes'
    order by policyname
  loop
    raise notice '  policy=% cmd=% roles=% using=% with_check=%',
      r.policyname, r.cmd, r.roles, coalesce(r.using_expr, '-'), coalesce(r.with_check_expr, '-');
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Item 21 — assinaturas das RPCs (sem exceções: to_regprocedure retorna
-- null em vez de lançar erro quando a assinatura não existe)
-- -----------------------------------------------------------------------------
do $$
declare
  v_old_cadastrar regprocedure;
  v_new_cadastrar regprocedure;
  v_old_registrar regprocedure;
  v_new_registrar regprocedure;
  v_count_cadastrar integer;
  v_count_registrar integer;
begin
  v_old_cadastrar := to_regprocedure(
    'public.cadastrar_patrimonio(uuid, uuid, text, text, text, text, text, text, date, uuid, text, text, text, text, timestamptz)'
  );
  v_new_cadastrar := to_regprocedure(
    'public.cadastrar_patrimonio(uuid, uuid, text, text, text, text, text, text, date, uuid, text, text, text, text, timestamptz, uuid, uuid)'
  );
  v_old_registrar := to_regprocedure(
    'public.registrar_movimentacao(uuid, public.movimentacao_tipo, uuid, text, text, text, text, text, timestamptz)'
  );
  v_new_registrar := to_regprocedure(
    'public.registrar_movimentacao(uuid, public.movimentacao_tipo, uuid, text, text, text, text, text, timestamptz, uuid, boolean)'
  );

  select count(*) into v_count_cadastrar from pg_proc where proname = 'cadastrar_patrimonio' and pronamespace = 'public'::regnamespace;
  select count(*) into v_count_registrar from pg_proc where proname = 'registrar_movimentacao' and pronamespace = 'public'::regnamespace;

  if v_new_cadastrar is null then
    raise exception 'FALHA - item 21: assinatura nova de cadastrar_patrimonio (17 parâmetros) não existe';
  end if;
  if v_old_cadastrar is not null then
    raise exception 'FALHA - item 21: assinatura antiga de cadastrar_patrimonio (15 parâmetros) ainda existe (overload não removido)';
  end if;
  if v_count_cadastrar <> 1 then
    raise exception 'FALHA - item 21: esperava exatamente 1 overload de cadastrar_patrimonio em public, encontrou %', v_count_cadastrar;
  end if;
  raise notice 'OK - item 21: existe exatamente 1 public.cadastrar_patrimonio, com a assinatura nova de 17 parâmetros, e a antiga de 15 não existe';

  if v_new_registrar is null then
    raise exception 'FALHA - item 21: assinatura nova de registrar_movimentacao (11 parâmetros) não existe';
  end if;
  if v_old_registrar is not null then
    raise exception 'FALHA - item 21: assinatura antiga de registrar_movimentacao (9 parâmetros) ainda existe (overload não removido)';
  end if;
  if v_count_registrar <> 1 then
    raise exception 'FALHA - item 21: esperava exatamente 1 overload de registrar_movimentacao em public, encontrou %', v_count_registrar;
  end if;
  raise notice 'OK - item 21: existe exatamente 1 public.registrar_movimentacao, com a assinatura final de 11 parâmetros, e a antiga de 9 não existe';

  perform set_config('dryrun.new_cadastrar', v_new_cadastrar::oid::text, true);
  perform set_config('dryrun.new_registrar', v_new_registrar::oid::text, true);
end $$;

-- -----------------------------------------------------------------------------
-- Item 22 — grants / security
-- -----------------------------------------------------------------------------
do $$
declare
  v_new_cadastrar oid := current_setting('dryrun.new_cadastrar')::oid;
  v_new_registrar oid := current_setting('dryrun.new_registrar')::oid;
begin
  if not has_function_privilege('authenticated', v_new_cadastrar, 'EXECUTE') then
    raise exception 'FALHA - item 22: authenticated não tem EXECUTE em cadastrar_patrimonio (assinatura nova)';
  end if;
  if has_function_privilege('anon', v_new_cadastrar, 'EXECUTE') then
    raise exception 'FALHA - item 22: anon NÃO deveria ter EXECUTE em cadastrar_patrimonio';
  end if;
  if not has_function_privilege('authenticated', v_new_registrar, 'EXECUTE') then
    raise exception 'FALHA - item 22: authenticated não tem EXECUTE em registrar_movimentacao (assinatura nova)';
  end if;
  if has_function_privilege('anon', v_new_registrar, 'EXECUTE') then
    raise exception 'FALHA - item 22: anon NÃO deveria ter EXECUTE em registrar_movimentacao';
  end if;
  raise notice 'OK - item 22: authenticated tem EXECUTE nas duas RPCs novas; anon não tem em nenhuma das duas';

  if has_table_privilege('authenticated', 'public.localizacoes', 'DELETE') then
    raise exception 'FALHA - item 22: authenticated NÃO deveria ter DELETE em localizacoes';
  end if;
  if has_table_privilege('anon', 'public.localizacoes', 'SELECT') then
    raise exception 'FALHA - item 22: anon NÃO deveria ter SELECT em localizacoes';
  end if;
  if has_table_privilege('anon', 'public.localizacoes', 'INSERT') then
    raise exception 'FALHA - item 22: anon NÃO deveria ter INSERT em localizacoes';
  end if;
  raise notice 'OK - item 22: localizacoes sem DELETE para authenticated e sem nenhum acesso para anon';

  if not (select relrowsecurity from pg_class where oid = 'public.localizacoes'::regclass) then
    raise exception 'FALHA - item 22: RLS não está habilitada em public.localizacoes';
  end if;
  raise notice 'OK - item 22: RLS habilitada em public.localizacoes';

  if not (select prosecdef from pg_proc where oid = v_new_cadastrar) then
    raise exception 'FALHA - item 22: cadastrar_patrimonio não é SECURITY DEFINER';
  end if;
  if not (select prosecdef from pg_proc where oid = v_new_registrar) then
    raise exception 'FALHA - item 22: registrar_movimentacao não é SECURITY DEFINER';
  end if;
  raise notice 'OK - item 22: as duas RPCs são SECURITY DEFINER';

  if not exists (
    select 1 from pg_proc where oid = v_new_cadastrar
      and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')
  ) then
    raise exception 'FALHA - item 22: cadastrar_patrimonio não tem search_path fixado';
  end if;
  if not exists (
    select 1 from pg_proc where oid = v_new_registrar
      and exists (select 1 from unnest(proconfig) cfg where cfg like 'search_path=%')
  ) then
    raise exception 'FALHA - item 22: registrar_movimentacao não tem search_path fixado';
  end if;
  raise notice 'OK - item 22: as duas RPCs têm search_path explicitamente fixado (defesa contra search_path hijacking)';
end $$;

-- =============================================================================
-- ITEM 23 — ROLLBACK (nada do que foi feito acima permanece gravado)
-- =============================================================================

rollback;

-- =============================================================================
-- PARTE 3 — VERIFICAÇÃO PÓS-ROLLBACK (fora da transação, somente leitura)
-- =============================================================================

do $$
begin
  if to_regclass('public.localizacoes') is not null then
    raise exception 'FALHA - pós-ROLLBACK: public.localizacoes ainda existe';
  end if;
  raise notice 'OK - pós-ROLLBACK: public.localizacoes não existe mais';

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'patrimonios' and column_name = 'localizacao_atual_id'
  ) then
    raise exception 'FALHA - pós-ROLLBACK: patrimonios.localizacao_atual_id ainda existe';
  end if;
  raise notice 'OK - pós-ROLLBACK: patrimonios.localizacao_atual_id não existe mais';

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'movimentacoes'
      and column_name in ('localizacao_origem_id', 'localizacao_destino_id')
  ) then
    raise exception 'FALHA - pós-ROLLBACK: movimentacoes.localizacao_origem_id/destino_id ainda existem';
  end if;
  raise notice 'OK - pós-ROLLBACK: movimentacoes.localizacao_origem_id/destino_id não existem mais';

  if to_regprocedure(
    'public.cadastrar_patrimonio(uuid, uuid, text, text, text, text, text, text, date, uuid, text, text, text, text, timestamptz)'
  ) is null then
    raise exception 'FALHA - pós-ROLLBACK: assinatura antiga de cadastrar_patrimonio (15 parâmetros, produção) não voltou a existir';
  end if;
  raise notice 'OK - pós-ROLLBACK: assinatura de produção de cadastrar_patrimonio (15 parâmetros) voltou a existir';

  if to_regprocedure(
    'public.registrar_movimentacao(uuid, public.movimentacao_tipo, uuid, text, text, text, text, text, timestamptz)'
  ) is null then
    raise exception 'FALHA - pós-ROLLBACK: assinatura antiga de registrar_movimentacao (9 parâmetros, produção) não voltou a existir';
  end if;
  raise notice 'OK - pós-ROLLBACK: assinatura de produção de registrar_movimentacao (9 parâmetros) voltou a existir';

  if exists (select 1 from public.setores where nome like 'ZZ_DRYRUN%') then
    raise exception 'FALHA - pós-ROLLBACK: ainda existe gerência ZZ_DRYRUN em public.setores';
  end if;
  raise notice 'OK - pós-ROLLBACK: nenhuma gerência ZZ_DRYRUN permanece';

  if exists (select 1 from public.patrimonios where numero_patrimonio like 'ZZDRYRUN-%') then
    raise exception 'FALHA - pós-ROLLBACK: ainda existe patrimônio ZZDRYRUN em public.patrimonios';
  end if;
  raise notice 'OK - pós-ROLLBACK: nenhum patrimônio ZZDRYRUN permanece';

  raise notice 'DRY-RUN CONCLUÍDO: nenhuma alteração permanece no banco.';
end $$;

-- Confirmação final (item 24 — migration de tipos já aplicada permanece intacta):
select count(*) as tipos_patrimonio_total, count(*) filter (where ativo) as tipos_patrimonio_ativos
from public.tipos_patrimonio;
