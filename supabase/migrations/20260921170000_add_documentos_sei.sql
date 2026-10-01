-- =============================================================================
-- InvTec — Documentos SEI / Pendências (PROMPT 11.3)
--
-- IMPORTANTE: esta migration é uma PROPOSTA. Ela NÃO foi aplicada no
-- Supabase remoto e NÃO foi executada em nenhum PostgreSQL local. Revisar
-- antes de aplicar — em especial as seções 6 (funções), 8 (GRANTS) e 9
-- (RLS), e o comentário da seção 11 sobre a conclusão futura.
--
-- CONTEXTO DE NEGÓCIO: importar e salvar um despacho SEI cria uma
-- SOLICITAÇÃO PENDENTE — nunca altera um patrimônio. Só uma etapa FUTURA
-- (não implementada aqui), quando a GETEC confirmar que um item foi
-- efetivamente concluído, poderia vir a registrar uma movimentação real
-- (via `public.registrar_movimentacao`, já existente) e vinculá-la ao item.
-- Nenhuma função desta migration chama `registrar_movimentacao`.
--
-- Estas tabelas são SEPARADAS de `public.movimentacoes`: um documento
-- pendente nunca aparece no histórico de movimentações efetivas, mesmo
-- depois de concluído (o que aparece lá, nesse caso futuro, é a
-- movimentação em si, referenciada por `documentos_sei_itens.
-- movimentacao_id`).
-- =============================================================================

-- =============================================================================
-- 1. ENUMS
-- =============================================================================

create type public.documento_sei_item_status as enum (
  'PENDENTE',
  'CONCLUIDO',
  'CANCELADO'
);

-- Mesma semântica de `SeiDecisaoCampo` no Flutter (PROMPT 11.2.1): o
-- documento SEI nunca informa localização/responsável de destino, então
-- "ausência no PDF" nunca pode ser confundida com "decisão de deixar sem
-- informação" — a segunda exige uma ação humana explícita.
create type public.documento_sei_decisao_campo as enum (
  'PENDENTE',
  'DEFINIDO',
  'CONFIRMADO_SEM_INFORMACAO'
);

-- =============================================================================
-- 2. TABELAS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- documentos_sei
-- ---------------------------------------------------------------------------
-- Seção 5 da especificação: NENHUMA coluna aqui é usada sozinha como chave
-- de deduplicação. `numero_documento_sei` NÃO tem índice único — o mesmo
-- despacho pode legitimamente ser reimportado (nova sessão de análise,
-- versão corrigida) e o hash muda a cada exportação do SEI. A
-- deduplicação é uma checagem de LEITURA (`buscarPossivelDuplicata`, ver
-- `DocumentosSeiRepository`) com confirmação humana explícita — nunca uma
-- constraint que bloqueie silenciosamente um caso legítimo.
create table public.documentos_sei (
  id uuid primary key default gen_random_uuid(),
  numero_documento_sei text,
  numero_processo text,
  numero_documento_formatado text,
  assunto text,
  tipo_operacao_pretendida public.movimentacao_tipo not null,
  nome_arquivo text not null,
  -- metadado de auditoria/diagnóstico (seção 2); NUNCA a identidade do
  -- documento nem critério de deduplicação (ver comentário acima).
  hash_sha256 text not null,
  -- controle de concorrência otimista (seção 14): toda edição exige o
  -- cliente enviar a versão que leu; ver `editar_documento_sei_pendente`.
  versao integer not null default 1,
  criado_em timestamptz not null default now(),
  criado_por uuid not null references public.profiles (id) on delete restrict,
  atualizado_em timestamptz not null default now(),
  constraint documentos_sei_numero_documento_normalizado check (
    numero_documento_sei is null
    or numero_documento_sei is not distinct from public.normalize_text(numero_documento_sei)
  ),
  constraint documentos_sei_numero_processo_normalizado check (
    numero_processo is null
    or numero_processo is not distinct from public.normalize_text(numero_processo)
  )
);

-- ---------------------------------------------------------------------------
-- documentos_sei_itens
-- ---------------------------------------------------------------------------
-- Seção 5/13: guarda o valor ORIGINAL do parser e o valor CORRIGIDO
-- manualmente separadamente — nunca sobrescreve um com o outro. Quem/quando
-- corrigiu é rastreado uma vez por item (a correção mais recente); o
-- histórico completo de cada correção (inclusive correções anteriores,
-- substituídas por uma nova) fica em `documentos_sei_eventos.dados_antes/
-- dados_depois` (append-only, nunca editável).
--
-- `patrimonio_id`/`origem_setor_id`/`destino_setor_id` são NULLABLE: um
-- item cujo patrimônio não foi encontrado no InvTec, ou cujo destino não
-- foi resolvido, ainda vira um item da pendência (a solicitação existe
-- mesmo que precise de correção manual antes de poder ser concluída) —
-- nunca descartado silenciosamente.
create table public.documentos_sei_itens (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos_sei (id) on delete restrict,
  linha integer not null,

  patrimonio_id uuid references public.patrimonios (id) on delete restrict,

  numero_patrimonio_original text,
  numero_patrimonio_corrigido text,

  origem_texto_original text,
  origem_setor_id uuid references public.setores (id) on delete restrict,

  destino_texto_original text,
  destino_texto_corrigido text,
  destino_setor_id uuid references public.setores (id) on delete restrict,

  numero_chamado_original text,
  numero_chamado_corrigido text,

  equipamento_texto_original text,
  equipamento_texto_corrigido text,

  -- decisão humana de destino (PROMPT 11.2.1) — nunca preenchida pelo
  -- parser; ver `public.documento_sei_decisao_campo`.
  localizacao_destino_id uuid references public.localizacoes (id) on delete restrict,
  decisao_localizacao public.documento_sei_decisao_campo not null default 'PENDENTE',
  responsavel_destino text,
  decisao_responsavel public.documento_sei_decisao_campo not null default 'PENDENTE',

  status public.documento_sei_item_status not null default 'PENDENTE',
  motivo_cancelamento text,

  -- Seção 15: o vínculo INEQUÍVOCO com a movimentação efetiva — só uma
  -- etapa futura preenche isto. `documentos_sei_itens_movimentacao_unica`
  -- (seção 3, índices) garante que uma movimentação nunca é reclamada por
  -- dois itens diferentes.
  movimentacao_id uuid references public.movimentacoes (id) on delete restrict,

  -- rastreio da correção mais recente (seção 13) — `null` quando nenhum
  -- campo deste item jamais foi corrigido.
  corrigido_por uuid references public.profiles (id) on delete restrict,
  corrigido_em timestamptz,
  motivo_correcao text,

  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),

  constraint documentos_sei_itens_documento_linha_unica unique (documento_id, linha),

  -- Seção 6: nenhum estado contraditório — CONCLUIDO exige movimentação
  -- vinculada; CANCELADO exige motivo; PENDENTE não tem nenhum dos dois.
  constraint documentos_sei_itens_status_coerente check (
    (status = 'PENDENTE' and movimentacao_id is null and motivo_cancelamento is null)
    or (status = 'CONCLUIDO' and movimentacao_id is not null and motivo_cancelamento is null)
    or (status = 'CANCELADO' and movimentacao_id is null and motivo_cancelamento is not null)
  ),

  -- PROMPT 11.3.1, seção 2/5 — auditoria encontrou: nada impedia
  -- `decisao_localizacao = 'DEFINIDO'` sem `localizacao_destino_id`, nem
  -- `decisao_localizacao = 'CONFIRMADO_SEM_INFORMACAO'` COM um id presente
  -- (contradição: "decidi que fica sem informação" + um valor definido ao
  -- mesmo tempo). Mesma lógica do lado responsável, usando texto vazio
  -- normalizado como NULL (ver `trg_documentos_sei_itens_normalize`).
  constraint documentos_sei_itens_decisao_localizacao_coerente check (
    (decisao_localizacao = 'PENDENTE' and localizacao_destino_id is null)
    or (decisao_localizacao = 'DEFINIDO' and localizacao_destino_id is not null)
    or (decisao_localizacao = 'CONFIRMADO_SEM_INFORMACAO' and localizacao_destino_id is null)
  ),
  constraint documentos_sei_itens_decisao_responsavel_coerente check (
    (decisao_responsavel = 'PENDENTE' and responsavel_destino is null)
    or (decisao_responsavel = 'DEFINIDO' and responsavel_destino is not null)
    or (decisao_responsavel = 'CONFIRMADO_SEM_INFORMACAO' and responsavel_destino is null)
  )
);

-- ---------------------------------------------------------------------------
-- documentos_sei_eventos: trilha de auditoria IMUTÁVEL (seção 5)
-- ---------------------------------------------------------------------------
-- Sem UPDATE/DELETE concedido a ninguém além do dono do banco (nem sequer
-- às funções SECURITY DEFINER desta migration, que só fazem INSERT) — ver
-- GRANTS (seção 8). "Não permitir edição retroativa dos eventos" (seção 5)
-- é impositivo, não só uma convenção de código.
create table public.documentos_sei_eventos (
  id uuid primary key default gen_random_uuid(),
  documento_id uuid not null references public.documentos_sei (id) on delete restrict,
  item_id uuid references public.documentos_sei_itens (id) on delete restrict,
  tipo text not null,
  descricao text not null,
  dados_antes jsonb,
  dados_depois jsonb,
  autor_id uuid not null references public.profiles (id) on delete restrict,
  criado_em timestamptz not null default now(),
  -- PROMPT 11.3.2, seção 3 — 'TENTATIVA_BLOQUEADA' permanece um tipo
  -- válido (reservado para uma eventual estratégia futura fora desta
  -- transação de negócio), mas NENHUMA função desta migration o produz
  -- hoje: gravá-lo dentro da mesma transação que está prestes a ser
  -- desfeita por `raise exception` era uma promessa de auditoria que nunca
  -- se cumpria (ver `editar_documento_sei_pendente`).
  constraint documentos_sei_eventos_tipo_valido check (
    tipo in (
      'CRIACAO', 'EDICAO', 'DECISAO_ALTERADA', 'ITEM_CONCLUIDO',
      'ITEM_CANCELADO', 'DOCUMENTO_CANCELADO', 'TENTATIVA_BLOQUEADA'
    )
  )
);

-- =============================================================================
-- 3. ÍNDICES
-- =============================================================================

-- Busca por documento (nunca única — seção 5) e por processo, para a
-- listagem de pendências e para `buscarPossivelDuplicata`.
create index documentos_sei_numero_documento_idx on public.documentos_sei (numero_documento_sei);
create index documentos_sei_numero_processo_idx on public.documentos_sei (numero_processo);
create index documentos_sei_tipo_idx on public.documentos_sei (tipo_operacao_pretendida);
create index documentos_sei_criado_em_idx on public.documentos_sei (criado_em desc);

create index documentos_sei_itens_documento_idx on public.documentos_sei_itens (documento_id);
create index documentos_sei_itens_patrimonio_idx on public.documentos_sei_itens (patrimonio_id) where patrimonio_id is not null;
create index documentos_sei_itens_status_idx on public.documentos_sei_itens (status);

-- Seção 15: garantia estrutural (não depende de uma futura RPC) — uma
-- movimentação efetiva nunca pode ser reclamada por dois itens diferentes.
create unique index documentos_sei_itens_movimentacao_unica
  on public.documentos_sei_itens (movimentacao_id)
  where movimentacao_id is not null;

create index documentos_sei_eventos_documento_idx on public.documentos_sei_eventos (documento_id, criado_em desc);
create index documentos_sei_eventos_item_idx on public.documentos_sei_eventos (item_id) where item_id is not null;

-- =============================================================================
-- 4. TRIGGERS DE NORMALIZAÇÃO
-- =============================================================================

create or replace function public.normalize_documento_sei()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.numero_documento_sei := public.normalize_text(new.numero_documento_sei);
  new.numero_processo := public.normalize_text(new.numero_processo);
  new.numero_documento_formatado := public.normalize_text(new.numero_documento_formatado);
  new.assunto := public.normalize_text(new.assunto);
  return new;
end;
$$;

create trigger trg_documentos_sei_normalize
  before insert or update on public.documentos_sei
  for each row execute function public.normalize_documento_sei();

-- PROMPT 11.3.1, seção 2 — auditoria encontrou: `documentos_sei_itens` era
-- a ÚNICA tabela de todo o schema sem nenhuma normalização de texto (toda
-- outra tabela — setores, tipos_patrimonio, patrimonios, localizacoes,
-- documentos_sei acima — tem uma trigger equivalente). Sem isto, "" e
-- espaços em branco não viravam NULL, e as novas constraints de coerência
-- de decisão (abaixo) poderiam ser burladas mandando `responsavel_destino
-- = '   '` como se fosse um valor "definido". O nome da trigger
-- (`..._normalize`) precisa ficar alfabeticamente ANTES de
-- `..._protect_columns`/`..._set_updated_at`/`..._validate_*` — Postgres
-- dispara triggers BEFORE da mesma tabela/evento em ordem alfabética de
-- nome — para que as constraints de coerência avaliem o valor já
-- normalizado.
create or replace function public.normalize_documento_sei_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.numero_patrimonio_original := public.normalize_text(new.numero_patrimonio_original);
  new.numero_patrimonio_corrigido := public.normalize_text(new.numero_patrimonio_corrigido);
  new.origem_texto_original := public.normalize_text(new.origem_texto_original);
  new.destino_texto_original := public.normalize_text(new.destino_texto_original);
  new.destino_texto_corrigido := public.normalize_text(new.destino_texto_corrigido);
  new.numero_chamado_original := public.normalize_text(new.numero_chamado_original);
  new.numero_chamado_corrigido := public.normalize_text(new.numero_chamado_corrigido);
  new.equipamento_texto_original := public.normalize_text(new.equipamento_texto_original);
  new.equipamento_texto_corrigido := public.normalize_text(new.equipamento_texto_corrigido);
  new.responsavel_destino := public.normalize_text(new.responsavel_destino);
  new.motivo_cancelamento := public.normalize_text(new.motivo_cancelamento);
  new.motivo_correcao := public.normalize_text(new.motivo_correcao);
  return new;
end;
$$;

create trigger trg_documentos_sei_itens_normalize
  before insert or update on public.documentos_sei_itens
  for each row execute function public.normalize_documento_sei_item();

-- Seção 4 (localizacoes): a localização de destino de um item, quando
-- informada, precisa pertencer ao MESMO setor resolvido como destino do
-- item — nunca uma localização "solta" de outra gerência. Mesma filosofia
-- de `private.validate_localizacao_pertence_ao_setor` (patrimonios).
create or replace function private.validate_pendencia_localizacao_pertence_ao_setor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_setor_da_localizacao uuid;
begin
  if new.localizacao_destino_id is not null then
    if new.destino_setor_id is null then
      raise exception 'localizacao_destino_id informado sem destino_setor_id resolvido'
        using errcode = 'P0001';
    end if;

    select l.setor_id into v_setor_da_localizacao
    from public.localizacoes l
    where l.id = new.localizacao_destino_id
    for share;

    if v_setor_da_localizacao is null then
      raise exception 'Localização de destino não encontrada'
        using errcode = 'P0002';
    end if;
    if v_setor_da_localizacao <> new.destino_setor_id then
      raise exception 'A localização de destino informada não pertence ao setor de destino do item'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_documentos_sei_itens_validate_localizacao
  before insert or update of localizacao_destino_id, destino_setor_id on public.documentos_sei_itens
  for each row execute function private.validate_pendencia_localizacao_pertence_ao_setor();

-- PROMPT 11.3.1, seção 5 — auditoria encontrou: a FK
-- `documentos_sei_itens.movimentacao_id → movimentacoes.id` só garante que
-- a linha referenciada EXISTE, nunca que ela pertence ao MESMO patrimônio
-- do item. Sem esta trigger, essa correspondência dependeria inteiramente
-- da futura RPC de conclusão nunca ter um bug — uma garantia de disciplina
-- de código, não uma garantia de banco. Com a trigger, mesmo uma chamada
-- direta (fora da futura RPC) que tentasse vincular a movimentação errada
-- é rejeitada pelo próprio banco.
--
-- PROMPT 11.3.2, seção 5 — auditoria encontrou: `before insert or update of
-- movimentacao_id` faz o `of movimentacao_id` restringir SÓ o disparo em
-- UPDATE — em INSERT a trigger dispara sempre, e ali `old` não existe
-- (nenhum registro anterior). A condição original (`new.movimentacao_id is
-- not null and new.movimentacao_id is distinct from old.movimentacao_id`)
-- só não quebrava hoje porque toda linha nasce com `movimentacao_id` nulo
-- (nenhuma das 4 funções de escrita o define na criação) — o AND
-- curto-circuita em `new.movimentacao_id is not null = false` e nunca
-- chega a avaliar `old`. Mas isso dependia de disciplina externa, não de
-- garantia da própria trigger: um INSERT hipotético que já viesse com
-- `movimentacao_id` preenchido acessaria `old.movimentacao_id` sem "old"
-- estar atribuído, e o Postgres lançaria o erro genérico "record \"old\" is
-- not assigned yet" em vez da mensagem de validação de negócio pretendida.
-- Corrigido checando `tg_op` explicitamente ANTES de tocar `old`.
create or replace function private.validate_pendencia_movimentacao_patrimonio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_patrimonio_da_movimentacao uuid;
begin
  if new.movimentacao_id is not null
     and (tg_op = 'INSERT' or new.movimentacao_id is distinct from old.movimentacao_id) then
    select m.patrimonio_id into v_patrimonio_da_movimentacao
    from public.movimentacoes m
    where m.id = new.movimentacao_id;

    if v_patrimonio_da_movimentacao is null then
      raise exception 'Movimentação vinculada não encontrada' using errcode = 'P0002';
    end if;
    if new.patrimonio_id is null or v_patrimonio_da_movimentacao <> new.patrimonio_id then
      raise exception 'A movimentação vinculada não corresponde ao patrimônio deste item'
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_documentos_sei_itens_validate_movimentacao
  before insert or update of movimentacao_id on public.documentos_sei_itens
  for each row execute function private.validate_pendencia_movimentacao_patrimonio();

create or replace function public.set_updated_at_documento_sei_item()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

create trigger trg_documentos_sei_itens_set_updated_at
  before update on public.documentos_sei_itens
  for each row execute function public.set_updated_at_documento_sei_item();

-- =============================================================================
-- 5. VIEW: situação geral derivada (seção 7)
-- =============================================================================
-- Nunca uma coluna gravável em `documentos_sei` (evitaria estado
-- contraditório entre a situação exibida e os itens reais) — sempre
-- calculada a partir de `documentos_sei_itens`, com a MESMA lógica de
-- `calcularSituacaoDocumento` no Flutter.
-- PROMPT 11.3.2, seção 2 — auditoria encontrou um caso real classificado
-- errado: 0 concluídos + 10 pendentes + 23 cancelados caía no `else`
-- (PARCIALMENTE_CONCLUIDO) porque nenhum dos ramos anteriores cobria
-- "ainda há pendente, mas nada foi concluído" separadamente de "ainda há
-- pendente E algo foi concluído" — mas PARCIALMENTE_CONCLUIDO precisa,
-- pelo nome, de ao menos UMA conclusão real; sem nenhuma movimentação
-- efetiva, o documento continua simplesmente PENDENTE, não importa quantos
-- itens já foram cancelados. Regra corrigida, verificada nas 8 combinações
-- possíveis (nenhuma fica sem classificação):
--   0 itens                                   → PENDENTE
--   0 concluídos + ao menos 1 pendente         → PENDENTE (mesmo com cancelados)
--   todos concluídos                           → CONCLUIDO
--   todos cancelados (nada concluído/pendente) → CANCELADO
--   ao menos 1 concluído + 0 pendentes         → ENCERRADO_PARCIALMENTE
--   ao menos 1 concluído + ao menos 1 pendente → PARCIALMENTE_CONCLUIDO
create or replace view public.documentos_sei_com_situacao as
select
  d.*,
  count(i.id) as total_itens,
  count(i.id) filter (where i.status = 'PENDENTE') as total_pendentes,
  count(i.id) filter (where i.status = 'CONCLUIDO') as total_concluidos,
  count(i.id) filter (where i.status = 'CANCELADO') as total_cancelados,
  case
    when count(i.id) = 0 then 'PENDENTE'
    when count(i.id) filter (where i.status = 'CONCLUIDO') = 0
      and count(i.id) filter (where i.status = 'PENDENTE') > 0 then 'PENDENTE'
    when count(i.id) filter (where i.status = 'CONCLUIDO') = count(i.id) then 'CONCLUIDO'
    when count(i.id) filter (where i.status = 'CANCELADO') = count(i.id) then 'CANCELADO'
    when count(i.id) filter (where i.status = 'PENDENTE') = 0 then 'ENCERRADO_PARCIALMENTE'
    else 'PARCIALMENTE_CONCLUIDO'
  end as situacao
from public.documentos_sei d
left join public.documentos_sei_itens i on i.documento_id = d.id
group by d.id;

-- Views herdam RLS das tabelas base quando criadas com `security_invoker`
-- (padrão do PostgreSQL 15+ é `security_invoker = false`; fixamos
-- explicitamente para que a RLS de `documentos_sei`/`documentos_sei_itens`
-- seja sempre aplicada com o papel de quem consulta a view, nunca do dono).
alter view public.documentos_sei_com_situacao set (security_invoker = true);

-- =============================================================================
-- 6. FUNÇÕES DE ESCRITA (SECURITY DEFINER — únicos caminhos de mutação)
-- =============================================================================
-- Mesmo padrão de `cadastrar_patrimonio`/`registrar_movimentacao`: o
-- cliente não recebe INSERT/UPDATE direto nestas três tabelas (seção 8:
-- "a proibição deve ser aplicada no banco/serviço transacional, não
-- apenas na UI") — toda escrita passa por uma destas funções, que também
-- é onde a trilha de auditoria é gravada.

-- ---------------------------------------------------------------------------
-- criar_documento_sei_pendente: cria a solicitação PENDENTE + seus itens.
-- NUNCA altera um patrimônio, nunca grava em `movimentacoes`.
-- ---------------------------------------------------------------------------
-- p_itens: array jsonb, cada elemento com as chaves (todas opcionais exceto
-- "linha"): linha, patrimonio_id, numero_patrimonio_original,
-- origem_texto_original, origem_setor_id, destino_texto_original,
-- destino_setor_id, numero_chamado_original, equipamento_texto_original,
-- localizacao_destino_id, decisao_localizacao ('PENDENTE'/'DEFINIDO'/
-- 'CONFIRMADO_SEM_INFORMACAO'), responsavel_destino, decisao_responsavel.
-- PROMPT 11.3.1, seção 8 — auditoria encontrou: a checagem de duplicidade
-- (`buscarPossivelDuplicata`) era 100% responsabilidade do cliente
-- Flutter — uma chamada direta a esta RPC (curl/Postman/outro cliente),
-- por um usuário autenticado com perfil válido, criava uma pendência
-- duplicada sem nenhuma resistência do banco. `p_confirmar_duplicata`
-- fecha essa lacuna: por padrão (`false`), a função REJEITA criar um novo
-- documento quando já existe outro, ATIVO (nenhum item cancelado sozinho
-- não conta — só quando TODOS os itens do existente já estão cancelados é
-- que ele deixa de contar como "ativo"), com o MESMO número de documento
-- SEI (e, se informado, o mesmo processo). Nunca usa o hash como critério
-- (o mesmo despacho pode ser reexportado com bytes diferentes — seção 2 da
-- tabela). Um reimport legítimo (nova versão, correção) continua possível
-- enviando `p_confirmar_duplicata = true` — mesma decisão que hoje só o
-- Flutter tomava, agora também exigida de qualquer chamador direto.
--
-- PROMPT 11.3.2, seção 1 — auditoria encontrou: a versão acima (`exists (
-- select ...)` seguido de `insert`) NÃO impedia duas transações
-- concorrentes de ambas lerem "não existe" antes de qualquer uma inserir —
-- um `EXISTS` não é uma trava; só delimita o que a transação enxerga NO
-- MOMENTO da leitura. Corrigido com `pg_advisory_xact_lock`: antes de
-- checar/decidir qualquer coisa sobre duplicidade, a transação adquire uma
-- trava consultiva de escopo de TRANSAÇÃO (liberada automaticamente no
-- commit ou rollback — nunca precisa de `unlock` explícito) chaveada pela
-- CHAVE DE NEGÓCIO NORMALIZADA (número do documento SEI + número do
-- processo, quando informado) — nunca pelo hash (seção 2 da tabela). Uma
-- segunda transação tentando criar/verificar para a MESMA chave BLOQUEIA
-- nesta linha até a primeira commitar ou abortar; ao ser liberada, ela
-- reavalia o `exists` já vendo o documento da primeira transação
-- (commitado) e é corretamente rejeitada (ou aceita, se
-- `p_confirmar_duplicata = true`). Isso fecha a corrida real: não é mais
-- possível duas criações simultâneas do mesmo documento passarem
-- silenciosamente.
--
-- Documentos SEM número de documento SEI (`v_numero_normalizado is null`):
-- POLÍTICA EXPLÍCITA — não há chave de negócio para travar nem comparar,
-- então NENHUMA checagem de duplicidade é feita e NENHUMA trava é
-- adquirida; cada envio cria um novo documento. Isto é intencional (não um
-- descuido): não existe forma correta de deduplicar sem um identificador,
-- e a ausência de número já fica visível para quem revisa a lista de
-- pendências.
create or replace function public.criar_documento_sei_pendente(
  p_tipo_operacao_pretendida public.movimentacao_tipo,
  p_nome_arquivo text,
  p_hash_sha256 text,
  p_itens jsonb,
  p_numero_documento_sei text default null,
  p_numero_processo text default null,
  p_numero_documento_formatado text default null,
  p_assunto text default null,
  p_confirmar_duplicata boolean default false
)
returns public.documentos_sei
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_documento public.documentos_sei;
  v_item jsonb;
  v_numero_normalizado text := public.normalize_text(p_numero_documento_sei);
  v_processo_normalizado text := public.normalize_text(p_numero_processo);
  v_lock_key bigint;
  v_duplicata_existente boolean := false;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para registrar documento SEI pendente'
      using errcode = '42501';
  end if;

  if p_nome_arquivo is null or btrim(p_nome_arquivo) = '' then
    raise exception 'nome_arquivo é obrigatório' using errcode = 'P0001';
  end if;
  if p_hash_sha256 is null or btrim(p_hash_sha256) = '' then
    raise exception 'hash_sha256 é obrigatório' using errcode = 'P0001';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'p_itens precisa ser um array jsonb' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_itens) = 0 then
    raise exception 'Um documento SEI pendente precisa de ao menos um item' using errcode = 'P0001';
  end if;

  -- PROMPT 11.3.3, seção 3 — auditoria encontrou DUAS falhas ligadas,
  -- reproduzindo o cenário do prompt (SEI=95955192 com processo NULO numa
  -- sessão, e o MESMO SEI com processo informado noutra):
  --
  --   (a) CHAVE DE TRAVA assimétrica: a versão anterior incluía o processo
  --   na chave (`numero_documento_sei || ':' || coalesce(processo, '')`).
  --   Sessão A (processo nulo) e sessão B (processo informado) geravam
  --   strings DIFERENTES → hashes DIFERENTES → `pg_advisory_xact_lock`
  --   NUNCA as serializava entre si — a "trava" simplesmente não cobria
  --   esse par, e a corrida que o PROMPT 11.3.2 achava ter fechado
  --   continuava aberta exatamente neste caso.
  --
  --   (b) O PRÓPRIO PREDICADO do `exists` já era assimétrico, independente
  --   de concorrência: se A criasse primeiro (processo nulo) e B
  --   verificasse depois (processo informado), a condição exigia
  --   `d.numero_processo is not distinct from v_processo_normalizado` — com
  --   `d.numero_processo` NULO (de A) e `v_processo_normalizado` não-nulo
  --   (de B), o teste falha, e o documento de A nunca é encontrado como
  --   duplicata por B. Mesmo em uso puramente SEQUENCIAL (sem nenhuma
  --   concorrência), essa dupla não seria pega.
  --
  -- Corrigido travando por `numero_documento_sei` SOZINHO — nunca incluindo
  -- o processo na CHAVE DE TRAVA (que precisa ser mais ABRANGENTE que a
  -- chave de negócio: cobre TODA combinação que o predicado abaixo possa
  -- vir a considerar correspondente, mesmo com processos diferentes ou
  -- ausentes de cada lado) — e tornando o predicado SIMÉTRICO: dois
  -- registros com o mesmo número SEI são considerados o MESMO documento
  -- quando pelo menos um dos dois lados não tem processo informado (não há
  -- informação suficiente para diferenciar) OU quando os processos batem
  -- exatamente. A decisão não depende mais de qual lado "pergunta" primeiro.
  if v_numero_normalizado is not null then
    v_lock_key := hashtextextended('documentos_sei:' || v_numero_normalizado, 0);
    -- Trava de transação (não de sessão): serializa qualquer outra chamada
    -- concorrente a esta função para o MESMO número de documento SEI,
    -- independentemente do processo informado em cada chamada. Liberada
    -- automaticamente no fim desta transação.
    perform pg_advisory_xact_lock(v_lock_key);

    v_duplicata_existente := exists (
      select 1
      from public.documentos_sei_com_situacao d
      where d.numero_documento_sei is not distinct from v_numero_normalizado
        and (
          v_processo_normalizado is null
          or d.numero_processo is null
          or d.numero_processo is not distinct from v_processo_normalizado
        )
        and d.situacao <> 'CANCELADO'
    );

    if v_duplicata_existente and p_confirmar_duplicata is not true then
      raise exception 'Já existe documento SEI pendente ativo com este número — envie p_confirmar_duplicata = true para salvar mesmo assim'
        using errcode = 'P0020';
    end if;
  end if;

  insert into public.documentos_sei (
    numero_documento_sei, numero_processo, numero_documento_formatado, assunto,
    tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por
  ) values (
    p_numero_documento_sei, p_numero_processo, p_numero_documento_formatado, p_assunto,
    p_tipo_operacao_pretendida, p_nome_arquivo, p_hash_sha256, auth.uid()
  )
  returning * into v_documento;

  for v_item in select * from jsonb_array_elements(p_itens)
  loop
    insert into public.documentos_sei_itens (
      documento_id, linha, patrimonio_id,
      numero_patrimonio_original, origem_texto_original, origem_setor_id,
      destino_texto_original, destino_setor_id,
      numero_chamado_original, equipamento_texto_original,
      localizacao_destino_id, decisao_localizacao,
      responsavel_destino, decisao_responsavel
    ) values (
      v_documento.id,
      (v_item ->> 'linha')::integer,
      nullif(v_item ->> 'patrimonio_id', '')::uuid,
      v_item ->> 'numero_patrimonio_original',
      v_item ->> 'origem_texto_original',
      nullif(v_item ->> 'origem_setor_id', '')::uuid,
      v_item ->> 'destino_texto_original',
      nullif(v_item ->> 'destino_setor_id', '')::uuid,
      v_item ->> 'numero_chamado_original',
      v_item ->> 'equipamento_texto_original',
      nullif(v_item ->> 'localizacao_destino_id', '')::uuid,
      coalesce((v_item ->> 'decisao_localizacao')::public.documento_sei_decisao_campo, 'PENDENTE'),
      v_item ->> 'responsavel_destino',
      coalesce((v_item ->> 'decisao_responsavel')::public.documento_sei_decisao_campo, 'PENDENTE')
    );
  end loop;

  -- Seção 1: quando a criação prossegue apesar de uma duplicata ativa
  -- existir (`v_duplicata_existente and p_confirmar_duplicata`), isso fica
  -- registrado no próprio evento de criação — nunca só implícito no fato de
  -- `p_confirmar_duplicata` ter sido `true` numa chamada que o cliente não
  -- guarda.
  insert into public.documentos_sei_eventos (documento_id, tipo, descricao, dados_depois, autor_id)
  values (
    v_documento.id, 'CRIACAO',
    format('Documento SEI pendente criado com %s item(ns)', jsonb_array_length(p_itens)),
    jsonb_build_object(
      'numero_documento_sei', p_numero_documento_sei,
      'numero_processo', p_numero_processo,
      'duplicata_ativa_confirmada', (v_duplicata_existente and p_confirmar_duplicata is true)
    ),
    auth.uid()
  );

  return v_documento;
end;
$$;

-- ---------------------------------------------------------------------------
-- editar_documento_sei_pendente: edição dos dados principais + correções de
-- itens — só aceito com a versão esperada correta E nenhum item concluído.
-- ---------------------------------------------------------------------------
-- p_alteracoes: jsonb com só as chaves que devem mudar (presença de chave =
-- intenção de alterar; valor pode ser null para limpar o campo). Chaves
-- aceitas: numero_documento_sei, numero_processo, numero_documento_formatado,
-- assunto.
-- p_itens_alterados: array jsonb, cada elemento com "item_id" (obrigatório)
-- e as chaves de correção que devem mudar: numero_patrimonio_corrigido,
-- destino_texto_corrigido, numero_chamado_corrigido, equipamento_texto_corrigido
-- (textos extraídos do PDF, sempre preservando o "_original" — seção 13),
-- e — PROMPT 11.3.1, seção 3: auditoria encontrou que a versão original
-- não deixava editar destino/localização/responsável, só texto — MESMO o
-- documento estando desbloqueado, contrariando a seção 8 do PROMPT 11.3
-- ("Isso inclui editar: ... destino; ... localização prevista; responsável
-- previsto") — destino_setor_id, localizacao_destino_id,
-- decisao_localizacao, responsavel_destino, decisao_responsavel (estes
-- cinco são valores RESOLVIDOS/decisões, não têm "_original": a correção
-- simplesmente substitui o valor atual, com histórico completo em
-- `documentos_sei_eventos.dados_antes/dados_depois.itens`, nunca em pares
-- de coluna).
create or replace function public.editar_documento_sei_pendente(
  p_documento_id uuid,
  p_versao_esperada integer,
  p_motivo text,
  p_alteracoes jsonb default '{}'::jsonb,
  p_itens_alterados jsonb default '[]'::jsonb
)
returns public.documentos_sei
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_documento public.documentos_sei;
  v_item_edicao jsonb;
  v_qtd_concluidos integer;
  v_dados_antes jsonb;
  v_itens_antes jsonb;
  v_itens_depois jsonb;
  v_ids_itens_alterados uuid[];
  v_item_id uuid;
  v_item_check public.documentos_sei_itens;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para editar documento SEI pendente'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo é obrigatório para editar um documento SEI pendente'
      using errcode = 'P0001';
  end if;

  -- trava o documento: edições concorrentes sobre o mesmo documento são
  -- serializadas (seção 14) — a segunda espera a primeira terminar e então
  -- vê a versão já incrementada, falhando na checagem abaixo.
  select * into v_documento
  from public.documentos_sei
  where id = p_documento_id
  for update;

  if not found then
    raise exception 'Documento SEI pendente % não encontrado', p_documento_id
      using errcode = 'P0002';
  end if;

  if v_documento.versao <> p_versao_esperada then
    raise exception 'Conflito de edição: versão % informada, versão atual % — releia o documento antes de tentar novamente',
      p_versao_esperada, v_documento.versao
      using errcode = 'P0010';
  end if;

  -- Seção 8: REGRA DEFINITIVA — bloqueado para sempre após a primeira
  -- conclusão, independentemente da versão informada estar correta.
  --
  -- PROMPT 11.3.2, seção 3 — auditoria encontrou: a versão anterior gravava
  -- um evento 'TENTATIVA_BLOQUEADA' IMEDIATAMENTE ANTES do `raise
  -- exception` abaixo. Uma exceção desfaz TODA a transação corrente,
  -- inclusive esse INSERT — o evento nunca era commitado, então a função
  -- prometia uma trilha de auditoria que na prática nunca existia. Não é
  -- resolvido "engolindo" a exceção e retornando sucesso (inverteria a
  -- regra da seção 8) nem criando um serviço externo de auditoria (fora do
  -- escopo desta etapa) — a correção é simplesmente NÃO fingir que este
  -- evento persiste: a tentativa bloqueada é reportada ao cliente só pelo
  -- próprio erro (que o Flutter já traduz em
  -- `SeiDocumentoBloqueadoParaEdicaoException`), sem gravação alguma.
  -- 'TENTATIVA_BLOQUEADA' permanece um tipo válido em
  -- `documentos_sei_eventos_tipo_valido` para uma eventual estratégia
  -- futura (ex.: log em tabela própria fora da transação de negócio), mas
  -- NENHUMA função desta migration o produz hoje.
  select count(*) into v_qtd_concluidos
  from public.documentos_sei_itens
  where documento_id = p_documento_id and status = 'CONCLUIDO';

  if v_qtd_concluidos > 0 then
    raise exception 'Documento % está bloqueado para edição: já tem item concluído', p_documento_id
      using errcode = '42501';
  end if;

  if jsonb_typeof(p_alteracoes) <> 'object' then
    raise exception 'p_alteracoes precisa ser um objeto jsonb' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_itens_alterados) <> 'array' then
    raise exception 'p_itens_alterados precisa ser um array jsonb' using errcode = 'P0001';
  end if;

  -- PROMPT 11.3.2, seção 4 — auditoria encontrou: o loop de UPDATE mais
  -- abaixo filtrava por `id = ... and documento_id = ... and status =
  -- 'PENDENTE'` sem NUNCA conferir se o UPDATE realmente afetou alguma
  -- linha — um item_id inexistente, de outro documento, ou que já não
  -- estava mais PENDENTE simplesmente não batia com o WHERE, e a função
  -- retornava sucesso do mesmo jeito, gravando um evento 'EDICAO' como se
  -- toda correção solicitada tivesse sido aplicada (falha silenciosa).
  -- Corrigido com uma validação PRÉVIA, ANTES de qualquer escrita: cada
  -- item_id precisa existir, pertencer a ESTE documento, estar PENDENTE, e
  -- não pode se repetir no payload (tratado explicitamente como erro, não
  -- como "a última correção do mesmo id vence" — ambíguo demais para
  -- aceitar silenciosamente). Qualquer violação rejeita a operação
  -- INTEIRA: a exceção desfaz também a atualização dos campos do documento
  -- feita mais abaixo, já que tudo roda na mesma transação — nada fica
  -- parcialmente aplicado. `for update` aqui trava cada item validado (na
  -- mesma ordem documento→item já estabelecida) até o fim da função.
  v_ids_itens_alterados := array[]::uuid[];
  for v_item_edicao in select * from jsonb_array_elements(p_itens_alterados)
  loop
    if not (v_item_edicao ? 'item_id') or nullif(v_item_edicao ->> 'item_id', '') is null then
      raise exception 'Cada elemento de p_itens_alterados precisa de item_id' using errcode = 'P0001';
    end if;
    v_item_id := (v_item_edicao ->> 'item_id')::uuid;

    if v_item_id = any (v_ids_itens_alterados) then
      raise exception 'item_id % repetido em p_itens_alterados', v_item_id using errcode = 'P0001';
    end if;
    v_ids_itens_alterados := array_append(v_ids_itens_alterados, v_item_id);

    select * into v_item_check from public.documentos_sei_itens where id = v_item_id for update;
    if not found then
      raise exception 'Item % não encontrado', v_item_id using errcode = 'P0002';
    end if;
    if v_item_check.documento_id <> p_documento_id then
      raise exception 'Item % não pertence ao documento %', v_item_id, p_documento_id using errcode = 'P0001';
    end if;
    if v_item_check.status <> 'PENDENTE' then
      raise exception 'Item % não está PENDENTE (está %) — não pode ser editado', v_item_id, v_item_check.status
        using errcode = 'P0001';
    end if;
  end loop;

  v_dados_antes := jsonb_build_object(
    'numero_documento_sei', v_documento.numero_documento_sei,
    'numero_processo', v_documento.numero_processo,
    'numero_documento_formatado', v_documento.numero_documento_formatado,
    'assunto', v_documento.assunto
  );

  -- PROMPT 11.3.1, seção 7: retrato "antes" dos itens que serão tocados —
  -- capturado ANTES do loop de correção, para o evento de auditoria
  -- registrar o antes/depois real (não só dos campos do documento).
  select coalesce(jsonb_agg(to_jsonb(i.*)), '[]'::jsonb) into v_itens_antes
  from public.documentos_sei_itens i
  where i.documento_id = p_documento_id and i.id = any (coalesce(v_ids_itens_alterados, array[]::uuid[]));

  update public.documentos_sei set
    numero_documento_sei = case when p_alteracoes ? 'numero_documento_sei'
      then p_alteracoes ->> 'numero_documento_sei' else numero_documento_sei end,
    numero_processo = case when p_alteracoes ? 'numero_processo'
      then p_alteracoes ->> 'numero_processo' else numero_processo end,
    numero_documento_formatado = case when p_alteracoes ? 'numero_documento_formatado'
      then p_alteracoes ->> 'numero_documento_formatado' else numero_documento_formatado end,
    assunto = case when p_alteracoes ? 'assunto' then p_alteracoes ->> 'assunto' else assunto end,
    versao = versao + 1,
    atualizado_em = now()
  where id = p_documento_id
  returning * into v_documento;

  for v_item_edicao in select * from jsonb_array_elements(p_itens_alterados)
  loop
    update public.documentos_sei_itens set
      numero_patrimonio_corrigido = case when v_item_edicao ? 'numero_patrimonio_corrigido'
        then v_item_edicao ->> 'numero_patrimonio_corrigido' else numero_patrimonio_corrigido end,
      destino_texto_corrigido = case when v_item_edicao ? 'destino_texto_corrigido'
        then v_item_edicao ->> 'destino_texto_corrigido' else destino_texto_corrigido end,
      numero_chamado_corrigido = case when v_item_edicao ? 'numero_chamado_corrigido'
        then v_item_edicao ->> 'numero_chamado_corrigido' else numero_chamado_corrigido end,
      equipamento_texto_corrigido = case when v_item_edicao ? 'equipamento_texto_corrigido'
        then v_item_edicao ->> 'equipamento_texto_corrigido' else equipamento_texto_corrigido end,
      -- Seção 3 desta auditoria: agora também editáveis enquanto o
      -- documento não tiver item concluído — destino resolvido,
      -- localização e responsável de destino (decisão + valor sempre
      -- juntos, para nunca violar as constraints de coerência da seção 2).
      destino_setor_id = case when v_item_edicao ? 'destino_setor_id'
        then nullif(v_item_edicao ->> 'destino_setor_id', '')::uuid else destino_setor_id end,
      localizacao_destino_id = case when v_item_edicao ? 'localizacao_destino_id'
        then nullif(v_item_edicao ->> 'localizacao_destino_id', '')::uuid else localizacao_destino_id end,
      decisao_localizacao = case when v_item_edicao ? 'decisao_localizacao'
        then (v_item_edicao ->> 'decisao_localizacao')::public.documento_sei_decisao_campo else decisao_localizacao end,
      responsavel_destino = case when v_item_edicao ? 'responsavel_destino'
        then v_item_edicao ->> 'responsavel_destino' else responsavel_destino end,
      decisao_responsavel = case when v_item_edicao ? 'decisao_responsavel'
        then (v_item_edicao ->> 'decisao_responsavel')::public.documento_sei_decisao_campo else decisao_responsavel end,
      corrigido_por = auth.uid(),
      corrigido_em = now(),
      motivo_correcao = p_motivo
    where id = (v_item_edicao ->> 'item_id')::uuid
      and documento_id = p_documento_id
      and status = 'PENDENTE'; -- defesa extra: nunca corrige item concluído/cancelado
  end loop;

  select coalesce(jsonb_agg(to_jsonb(i.*)), '[]'::jsonb) into v_itens_depois
  from public.documentos_sei_itens i
  where i.documento_id = p_documento_id and i.id = any (coalesce(v_ids_itens_alterados, array[]::uuid[]));

  insert into public.documentos_sei_eventos (documento_id, tipo, descricao, dados_antes, dados_depois, autor_id)
  values (
    p_documento_id, 'EDICAO', p_motivo,
    jsonb_build_object('documento', v_dados_antes, 'itens', v_itens_antes),
    jsonb_build_object(
      'documento', jsonb_build_object(
        'numero_documento_sei', v_documento.numero_documento_sei,
        'numero_processo', v_documento.numero_processo,
        'numero_documento_formatado', v_documento.numero_documento_formatado,
        'assunto', v_documento.assunto
      ),
      'itens', v_itens_depois
    ),
    auth.uid()
  );

  return v_documento;
end;
$$;

-- ---------------------------------------------------------------------------
-- cancelar_item_sei_pendente: cancela UM item PENDENTE.
-- ---------------------------------------------------------------------------
-- PROMPT 11.3.1, seção 3 — auditoria encontrou um DEADLOCK real: a versão
-- original travava o ITEM primeiro (`for update`) e só depois tentava
-- travar o DOCUMENTO (no `update documentos_sei set versao = ...`),
-- enquanto `editar_documento_sei_pendente` trava o DOCUMENTO primeiro e só
-- depois os itens. Duas transações concorrentes — uma editando o
-- documento, outra cancelando um item dele — podiam travar em ordem
-- cruzada e o PostgreSQL abortaria uma delas com `deadlock_detected`
-- (40P01). Corrigido travando SEMPRE o documento primeiro, depois o item —
-- mesma ordem em TODAS as funções de escrita desta migration (ver também
-- `cancelar_pendentes_documento_sei` e a proposta da seção 11 para a
-- futura função de conclusão, que precisa seguir a mesma ordem).
create or replace function public.cancelar_item_sei_pendente(
  p_item_id uuid,
  p_motivo text
)
returns public.documentos_sei_itens
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_documento_id uuid;
  v_item public.documentos_sei_itens;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para cancelar item de documento SEI pendente'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo é obrigatório para cancelar um item' using errcode = 'P0001';
  end if;

  select documento_id into v_documento_id from public.documentos_sei_itens where id = p_item_id;
  if not found then
    raise exception 'Item % não encontrado', p_item_id using errcode = 'P0002';
  end if;

  -- Trava o DOCUMENTO primeiro (ordem consistente — ver comentário acima).
  perform 1 from public.documentos_sei where id = v_documento_id for update;

  select * into v_item from public.documentos_sei_itens where id = p_item_id for update;

  if v_item.status <> 'PENDENTE' then
    raise exception 'Item % não está PENDENTE (está %) — não pode ser cancelado', p_item_id, v_item.status
      using errcode = 'P0001';
  end if;

  update public.documentos_sei_itens
  set status = 'CANCELADO', motivo_cancelamento = public.normalize_text(p_motivo)
  where id = p_item_id
  returning * into v_item;

  update public.documentos_sei set versao = versao + 1, atualizado_em = now() where id = v_item.documento_id;

  insert into public.documentos_sei_eventos (documento_id, item_id, tipo, descricao, autor_id)
  values (v_item.documento_id, v_item.id, 'ITEM_CANCELADO', p_motivo, auth.uid());

  return v_item;
end;
$$;

-- ---------------------------------------------------------------------------
-- cancelar_pendentes_documento_sei: cancela TODOS os itens ainda PENDENTES
-- do documento — "Cancelar documento" (seção 10). NUNCA toca itens já
-- concluídos ou já cancelados: um cancelamento parcial nunca desfaz uma
-- entrega anterior.
-- ---------------------------------------------------------------------------
-- PROMPT 11.3.1, seção 3 — mesma correção de ordem de lock de
-- `cancelar_item_sei_pendente`: trava o DOCUMENTO (`for update`) ANTES do
-- `update` em lote nos itens, nunca depois — evita o mesmo deadlock
-- potencial contra `editar_documento_sei_pendente`/
-- `cancelar_item_sei_pendente` concorrentes sobre o mesmo documento.
create or replace function public.cancelar_pendentes_documento_sei(
  p_documento_id uuid,
  p_motivo text
)
returns setof public.documentos_sei_itens
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qtd integer;
begin
  if private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR') is not true then
    raise exception 'Usuário sem permissão para cancelar documento SEI pendente'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo é obrigatório para cancelar um documento' using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.documentos_sei where id = p_documento_id) then
    raise exception 'Documento % não encontrado', p_documento_id using errcode = 'P0002';
  end if;

  -- Trava o DOCUMENTO primeiro (ordem consistente — ver comentário acima),
  -- antes de tocar qualquer linha de `documentos_sei_itens`.
  perform 1 from public.documentos_sei where id = p_documento_id for update;

  create temporary table if not exists tmp_itens_cancelados (like public.documentos_sei_itens) on commit drop;
  delete from tmp_itens_cancelados;

  with atualizados as (
    update public.documentos_sei_itens
    set status = 'CANCELADO', motivo_cancelamento = public.normalize_text(p_motivo)
    where documento_id = p_documento_id and status = 'PENDENTE'
    returning *
  )
  insert into tmp_itens_cancelados select * from atualizados;

  select count(*) into v_qtd from tmp_itens_cancelados;

  if v_qtd > 0 then
    update public.documentos_sei set versao = versao + 1, atualizado_em = now() where id = p_documento_id;

    insert into public.documentos_sei_eventos (documento_id, tipo, descricao, autor_id)
    values (p_documento_id, 'DOCUMENTO_CANCELADO', format('%s item(ns) pendente(s) cancelado(s): %s', v_qtd, p_motivo), auth.uid());
  end if;

  return query select * from tmp_itens_cancelados;
end;
$$;

-- =============================================================================
-- 7. TRIGGER: proteção contra escrita direta nas colunas de estado
-- =============================================================================
-- Defesa em profundidade além dos GRANTs da seção 8: mesmo que um GRANT
-- amplo seja aplicado por engano no futuro, status/movimentacao_id/versao
-- só podem mudar pelas funções acima (que rodam como dono do banco).

create or replace function public.protect_documento_sei_item_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated')
     and (
       new.status is distinct from old.status
       or new.movimentacao_id is distinct from old.movimentacao_id
       or new.documento_id is distinct from old.documento_id
     ) then
    raise exception 'status, movimentacao_id e documento_id de um item só podem mudar pelas funções de escrita'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger trg_documentos_sei_itens_protect_columns
  before update on public.documentos_sei_itens
  for each row execute function public.protect_documento_sei_item_columns();

create or replace function public.protect_documento_sei_columns()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated')
     and (
       new.versao is distinct from old.versao
       or new.criado_por is distinct from old.criado_por
       or new.criado_em is distinct from old.criado_em
     ) then
    raise exception 'versao, criado_por e criado_em só podem mudar pelas funções de escrita'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger trg_documentos_sei_protect_columns
  before update on public.documentos_sei
  for each row execute function public.protect_documento_sei_columns();

-- =============================================================================
-- 8. GRANTS
-- =============================================================================
-- Mesmo padrão de `movimentacoes`/`patrimonios`: revoga tudo primeiro,
-- concede só SELECT nas tabelas (a escrita é 100% via função SECURITY
-- DEFINER) e EXECUTE só nas 4 funções de escrita, todas para authenticated.
-- CONSULTA nunca recebe EXECUTE nestas 4 (a checagem de perfil está dentro
-- de cada função, mas o GRANT é a primeira camada).

revoke all on table
  public.documentos_sei,
  public.documentos_sei_itens,
  public.documentos_sei_eventos
from public, anon, authenticated;

revoke all on function
  public.criar_documento_sei_pendente,
  public.editar_documento_sei_pendente,
  public.cancelar_item_sei_pendente,
  public.cancelar_pendentes_documento_sei
from public, anon, authenticated;

grant select on public.documentos_sei to authenticated;
grant select on public.documentos_sei_itens to authenticated;
grant select on public.documentos_sei_eventos to authenticated;
grant select on public.documentos_sei_com_situacao to authenticated;

-- Sem INSERT/UPDATE/DELETE direto em nenhuma das 3 tabelas — só as funções
-- abaixo (que rodam como dono do banco) escrevem.
grant execute on function public.criar_documento_sei_pendente to authenticated;
grant execute on function public.editar_documento_sei_pendente to authenticated;
grant execute on function public.cancelar_item_sei_pendente to authenticated;
grant execute on function public.cancelar_pendentes_documento_sei to authenticated;

-- =============================================================================
-- 9. ROW LEVEL SECURITY
-- =============================================================================
-- Leitura: mesmo público de `movimentacoes` (ADMIN/GESTOR/OPERADOR/
-- CONSULTA) — transparência total sobre pendências para quem já tem
-- qualquer acesso real ao InvTec. CONSULTA NUNCA ganha policy de escrita
-- (não há nenhuma abaixo) nem GRANT de EXECUTE nas 4 funções (seção 8).

alter table public.documentos_sei enable row level security;
alter table public.documentos_sei_itens enable row level security;
alter table public.documentos_sei_eventos enable row level security;

create policy documentos_sei_select on public.documentos_sei
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

create policy documentos_sei_itens_select on public.documentos_sei_itens
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

create policy documentos_sei_eventos_select on public.documentos_sei_eventos
  for select to authenticated
  using ((select private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR', 'CONSULTA')));

-- Sem INSERT/UPDATE/DELETE policy em nenhuma das 3: toda escrita passa
-- pelas funções SECURITY DEFINER da seção 6, que rodam como dono do banco
-- e portanto não dependem de (nem são limitadas por) policy de RLS —
-- mesma técnica já usada por `registrar_movimentacao` em `patrimonios`.

-- =============================================================================
-- 10. DEFAULT PRIVILEGES
-- =============================================================================
-- Já coberto pela migration inicial (`alter default privileges for role
-- postgres in schema public/private revoke ...`, seção 11 de
-- 20260910120000_initial_schema.sql) — aplica-se automaticamente a
-- qualquer objeto novo criado pelo role `postgres` em `public`/`private`,
-- inclusive os desta migration. Nenhuma repetição necessária.

-- =============================================================================
-- 11. PROPOSTA FUTURA (NÃO CRIADA NESTA MIGRATION): conclusão atômica
-- =============================================================================
-- PROMPT 11.3, seção 15: a conclusão de um item precisa, numa etapa
-- FUTURA e com aprovação própria, de uma função SECURITY DEFINER dedicada
-- que faça TUDO isto dentro de uma única transação (nunca duas escritas
-- independentes do cliente):
--
--   1. travar o DOCUMENTO (`for update`) — PRIMEIRO, na MESMA ordem usada
--      por `editar_documento_sei_pendente`/`cancelar_item_sei_pendente`/
--      `cancelar_pendentes_documento_sei` (PROMPT 11.3.1, seção 3: as três
--      foram corrigidas para travar sempre o documento antes do item,
--      depois que a auditoria encontrou um deadlock real entre duas delas
--      com ordens cruzadas — esta futura função PRECISA seguir a mesma
--      ordem, ou reintroduz o mesmo risco);
--   2. travar o item (`for update`) e verificar que continua PENDENTE;
--   3. reconferir o estado atual do documento (ex.: ninguém cancelou o
--      item entretanto);
--   4. reverificar duplicidade (mesma lógica de
--      `classificarDuplicidade`/`listarPorNumeroDocumento`, mas dentro da
--      transação, contra o estado mais atual possível);
--   5. chamar a lógica de `registrar_movimentacao` (idealmente por
--      chamada SQL direta à função existente, dentro da mesma transação —
--      nunca uma segunda viagem de rede separada do cliente);
--   6. vincular `documentos_sei_itens.movimentacao_id` ao id retornado;
--   7. marcar o item CONCLUIDO;
--   8. gravar o evento ITEM_CONCLUIDO.
--
-- Por que não um índice único simples (ex.: em
-- `patrimonio_id + numero_documento + tipo + destino_id`)? Porque:
--   * operações legítimas repetidas existem (o mesmo patrimônio pode
--     legitimamente precisar de duas transferências distintas citando o
--     mesmo despacho, em momentos diferentes, se o despacho autorizar
--     mais de um movimento);
--   * `destino_id` pode ser NULL para alguns tipos (ex. BAIXA), e NULL
--     nunca é igual a NULL em um índice único do PostgreSQL — duas baixas
--     "duplicadas" citando o mesmo documento não seriam pegas por esse
--     índice de qualquer forma;
--   * a garantia de não-duplicação real que faz sentido aqui é por
--     IDENTIDADE DO ITEM DA SOLICITAÇÃO, não por uma tupla de campos de
--     negócio: `documentos_sei_itens_movimentacao_unica` (seção 3, já
--     criado nesta migration) já impede que uma movimentação seja
--     reclamada por dois itens; falta simetricamente impedir que o MESMO
--     item seja concluído duas vezes — o que um `update ...
--     where id = :item_id and status = 'PENDENTE'` dentro da transação
--     acima já resolve de forma atômica (a segunda tentativa concorrente
--     encontra `status <> 'PENDENTE'` e falha).
--
-- Esta função NÃO existe nesta migration. Nenhum código Flutter desta
-- versão a chama.

-- =============================================================================
-- 12. DECISÃO DE PRODUTO PENDENTE: PDF original
-- =============================================================================
-- Seção 17: esta primeira versão persiste APENAS metadados + itens
-- extraídos — o arquivo PDF em si NÃO é armazenado (nem em Storage, nem
-- como base64 no banco, que é proibido pela especificação de qualquer
-- forma). Guardar o PDF original em um bucket privado do Supabase Storage
-- é uma decisão de produto que precisa de alinhamento da GETEC (retenção,
-- limites de tamanho, política de acesso por perfil, tratamento de falha
-- entre upload e criação do documento) — registrada aqui como PENDÊNCIA,
-- não presumida. Nenhuma tabela ou coluna desta migration referencia
-- Storage.
