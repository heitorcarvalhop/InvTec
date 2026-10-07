-- InvTec — migra autorização de NEGÓCIO de private.has_perfil(...) para
-- private.has_permission(...) (Etapa 3)
--
-- Depende de 20261006100000 (catálogo + presets) e 20261006110000
-- (private.has_permission). A partir desta migration:
--   * policies/RPCs de CAPACIDADE DE NEGÓCIO (patrimônio, movimentação,
--     setor, localização, tipo de patrimônio, SEI) usam has_permission;
--   * policies/RPCs de ADMINISTRAÇÃO DE IDENTIDADE/ACESSO (profiles,
--     admin_audit_log, as 7 RPCs de usuários da Etapa 2, as 5 RPCs de
--     override de permissões da seção anterior) CONTINUAM em has_perfil —
--     não são escopo de granularização nesta etapa (seção 5/13/22 do
--     pedido) e por isso NENHUM arquivo dessas é tocado aqui.
--
-- `aplicar_decisao_comparacao_patrimonio` é a única exceção híbrida: a
-- operação já tinha defesa em profundidade restrita a ADMIN puro (a
-- importação/comparação administrativa de planilha, "Comparar e
-- Atualizar"), e o pedido (seção 16) exige preservar essa trava além da
-- nova permission_key — por isso ela mantém has_perfil('ADMIN') E passa a
-- exigir também has_permission('patrimonio.compare_update'). Nenhum
-- OPERADOR pode ganhar esta capacidade só por override: ele nunca passa do
-- primeiro gate (has_perfil('ADMIN')), que não é afetado por
-- user_permissions.
--
-- Cada `create or replace function` abaixo reproduz o corpo ATUAL da
-- função (mesma assinatura — nenhum DROP necessário) com uma única mudança
-- por função: a linha de autorização. Nenhuma outra regra de negócio foi
-- alterada.

-- =============================================================================
-- 1. RLS — patrimonios
-- =============================================================================
drop policy if exists patrimonios_select on public.patrimonios;
create policy patrimonios_select on public.patrimonios
  for select to authenticated
  using ((select private.has_permission('patrimonio.view')));

drop policy if exists patrimonios_update on public.patrimonios;
create policy patrimonios_update on public.patrimonios
  for update to authenticated
  using ((select private.has_permission('patrimonio.edit')))
  with check ((select private.has_permission('patrimonio.edit')));

-- =============================================================================
-- 2. RLS — movimentacoes
-- =============================================================================
drop policy if exists movimentacoes_select on public.movimentacoes;
create policy movimentacoes_select on public.movimentacoes
  for select to authenticated
  using ((select private.has_permission('movimentacao.view')));

-- =============================================================================
-- 3. RLS — setores
-- =============================================================================
drop policy if exists setores_select on public.setores;
create policy setores_select on public.setores
  for select to authenticated
  using ((select private.has_permission('setor.view')));

drop policy if exists setores_insert on public.setores;
create policy setores_insert on public.setores
  for insert to authenticated
  with check ((select private.has_permission('setor.manage')));

drop policy if exists setores_update on public.setores;
create policy setores_update on public.setores
  for update to authenticated
  using ((select private.has_permission('setor.manage')))
  with check ((select private.has_permission('setor.manage')));

-- =============================================================================
-- 4. RLS — tipos_patrimonio
-- =============================================================================
drop policy if exists tipos_patrimonio_select on public.tipos_patrimonio;
create policy tipos_patrimonio_select on public.tipos_patrimonio
  for select to authenticated
  using ((select private.has_permission('tipo_patrimonio.view')));

drop policy if exists tipos_patrimonio_insert on public.tipos_patrimonio;
create policy tipos_patrimonio_insert on public.tipos_patrimonio
  for insert to authenticated
  with check ((select private.has_permission('tipo_patrimonio.manage')));

drop policy if exists tipos_patrimonio_update on public.tipos_patrimonio;
create policy tipos_patrimonio_update on public.tipos_patrimonio
  for update to authenticated
  using ((select private.has_permission('tipo_patrimonio.manage')))
  with check ((select private.has_permission('tipo_patrimonio.manage')));

-- =============================================================================
-- 5. RLS — localizacoes
-- =============================================================================
drop policy if exists localizacoes_select on public.localizacoes;
create policy localizacoes_select on public.localizacoes
  for select to authenticated
  using ((select private.has_permission('localizacao.view')));

drop policy if exists localizacoes_insert on public.localizacoes;
create policy localizacoes_insert on public.localizacoes
  for insert to authenticated
  with check ((select private.has_permission('localizacao.manage')));

drop policy if exists localizacoes_update on public.localizacoes;
create policy localizacoes_update on public.localizacoes
  for update to authenticated
  using ((select private.has_permission('localizacao.manage')))
  with check ((select private.has_permission('localizacao.manage')));

-- =============================================================================
-- 6. RLS — documentos_sei / documentos_sei_itens / documentos_sei_eventos /
--    documentos_sei_lotes_conclusao
-- =============================================================================
drop policy if exists documentos_sei_select on public.documentos_sei;
create policy documentos_sei_select on public.documentos_sei
  for select to authenticated
  using ((select private.has_permission('sei.view')));

drop policy if exists documentos_sei_itens_select on public.documentos_sei_itens;
create policy documentos_sei_itens_select on public.documentos_sei_itens
  for select to authenticated
  using ((select private.has_permission('sei.view')));

drop policy if exists documentos_sei_eventos_select on public.documentos_sei_eventos;
create policy documentos_sei_eventos_select on public.documentos_sei_eventos
  for select to authenticated
  using ((select private.has_permission('sei.view')));

drop policy if exists documentos_sei_lotes_conclusao_select on public.documentos_sei_lotes_conclusao;
create policy documentos_sei_lotes_conclusao_select on public.documentos_sei_lotes_conclusao
  for select to authenticated
  using ((select private.has_permission('sei.view')));

-- NOTA: patrimonio_comparacao_execucoes_select NÃO é tocada aqui — continua
-- `has_perfil('ADMIN')` (ver cabeçalho do arquivo). É a tabela de controle
-- da própria operação crítica "Comparar e Atualizar", não uma tela de
-- visualização de negócio comum.

-- =============================================================================
-- 7. RPC — cadastrar_patrimonio (patrimonio.create)
-- =============================================================================
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
  if private.has_permission('patrimonio.create') is not true then
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

-- =============================================================================
-- 8. RPC — registrar_movimentacao (movimentacao.create)
-- =============================================================================
create or replace function public.registrar_movimentacao(
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
  if private.has_permission('movimentacao.create') is not true then
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

-- =============================================================================
-- 9. RPC — criar_documento_sei_pendente (sei.manage)
-- =============================================================================
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
  if private.has_permission('sei.manage') is not true then
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

  -- A trava usa `numero_documento_sei` SOZINHO — nunca incluindo o
  -- processo: a CHAVE DE TRAVA precisa ser mais ABRANGENTE que a chave de
  -- negócio, cobrindo toda combinação que o predicado abaixo possa vir a
  -- considerar correspondente, mesmo com processos diferentes ou ausentes
  -- de cada lado. O predicado é SIMÉTRICO: dois registros com o mesmo
  -- número SEI são o MESMO documento quando pelo menos um dos dois lados
  -- não tem processo informado (não há informação suficiente para
  -- diferenciar) OU quando os processos batem exatamente.
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

  -- Quando a criação prossegue apesar de uma duplicata ativa existir, isso
  -- fica registrado no próprio evento de criação — nunca só implícito no
  -- fato de `p_confirmar_duplicata` ter sido `true`.
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

-- =============================================================================
-- 10. RPC — editar_documento_sei_pendente (sei.manage)
-- =============================================================================
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
  v_vinculos jsonb := '{}'::jsonb;
  v_corrigido_novo text;
  v_numero_efetivo text;
  v_ids_encontrados uuid[];
  v_patrimonio_resolvido uuid;
begin
  if private.has_permission('sei.manage') is not true then
    raise exception 'Usuário sem permissão para editar documento SEI pendente'
      using errcode = '42501';
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'motivo é obrigatório para editar um documento SEI pendente'
      using errcode = 'P0001';
  end if;

  -- trava o documento: edições concorrentes sobre o mesmo documento são
  -- serializadas — a segunda espera a primeira terminar e então vê a
  -- versão já incrementada, falhando na checagem abaixo.
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

  -- REGRA DEFINITIVA: bloqueado para sempre após a primeira conclusão,
  -- independentemente da versão informada estar correta.
  --
  -- Não grava um evento 'TENTATIVA_BLOQUEADA' aqui: `raise exception`
  -- desfaz TODA a transação corrente, então um INSERT de auditoria antes
  -- dele nunca seria commitado. A tentativa bloqueada é reportada ao
  -- cliente só pelo próprio erro (que o Flutter traduz em
  -- `SeiDocumentoBloqueadoParaEdicaoException`). 'TENTATIVA_BLOQUEADA'
  -- permanece um tipo válido em `documentos_sei_eventos_tipo_valido` para
  -- uma eventual estratégia futura fora desta transação.
  select count(*) into v_qtd_concluidos
  from public.documentos_sei_itens
  where documento_id = p_documento_id and status = 'CONCLUIDO';

  if v_qtd_concluidos > 0 then
    raise exception 'Documento % está bloqueado para edição: já tem item concluído', p_documento_id
      using errcode = '42501';
  end if;

  -- Documento ENCERRADO (nenhum item PENDENTE: todos cancelados e/ou
  -- concluídos) também não pode mais ser editado. Roda DEPOIS do lock do
  -- documento acima — como todas as funções de escrita SEI travam o
  -- documento ANTES dos itens, nenhum cancelamento/conclusão concorrente
  -- muda o conjunto de itens PENDENTES entre esta leitura e o fim da função.
  --
  -- A mensagem contém "bloqueado" e o errcode é 42501: o Flutter já traduz
  -- essa combinação em `SeiDocumentoBloqueadoParaEdicaoException`.
  if not exists (
    select 1
    from public.documentos_sei_itens
    where documento_id = p_documento_id
      and status = 'PENDENTE'
  ) then
    raise exception 'Documento % está bloqueado para edição: encerrado (nenhum item pendente)', p_documento_id
      using errcode = '42501';
  end if;

  if jsonb_typeof(p_alteracoes) <> 'object' then
    raise exception 'p_alteracoes precisa ser um objeto jsonb' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_itens_alterados) <> 'array' then
    raise exception 'p_itens_alterados precisa ser um array jsonb' using errcode = 'P0001';
  end if;

  -- Validação PRÉVIA, ANTES de qualquer escrita: cada item_id precisa
  -- existir, pertencer a ESTE documento, estar PENDENTE, e não pode se
  -- repetir no payload — senão um UPDATE filtrado por WHERE simplesmente
  -- não bateria em nenhuma linha e a função gravaria um evento 'EDICAO'
  -- como se a correção tivesse sido aplicada (falha silenciosa). Qualquer
  -- violação rejeita a operação INTEIRA (mesma transação, nada fica
  -- parcialmente aplicado). `for update` trava cada item validado (na
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

    -- Re-resolução do vínculo com o patrimônio: sempre que o payload traz
    -- `numero_patrimonio_corrigido` (inclusive para REMOVER a correção), o
    -- número efetivo é recalculado (`corrigido`, ou `original` quando a
    -- correção é removida) e buscado em `public.patrimonios` com a MESMA
    -- normalização do banco (`upper(normalize_text(...))`).
    --   * correção informada e patrimônio inexistente -> rejeita a operação
    --     INTEIRA (nada é gravado; a exceção desfaz a transação);
    --   * correção removida e o número original não existe -> `patrimonio_id`
    --     volta a nulo (nunca um vínculo falso);
    --   * `origem_setor_id` NÃO é tocado: uma divergência de origem continua
    --     visível e é barrada na conclusão, nunca mascarada aqui.
    -- Só lê (sem lock novo). O resultado fica em `v_vinculos` e é aplicado
    -- no UPDATE abaixo.
    if v_item_edicao ? 'numero_patrimonio_corrigido' then
      v_corrigido_novo := public.normalize_text(v_item_edicao ->> 'numero_patrimonio_corrigido');
      v_numero_efetivo := upper(public.normalize_text(coalesce(v_corrigido_novo, v_item_check.numero_patrimonio_original)));
      v_ids_encontrados := null;
      v_patrimonio_resolvido := null;

      if v_numero_efetivo is not null then
        select array_agg(p.id) into v_ids_encontrados
        from public.patrimonios p
        where p.numero_patrimonio = v_numero_efetivo;

        if cardinality(v_ids_encontrados) > 1 then
          raise exception 'Mais de um patrimônio com o número % — inconsistência de dados', v_numero_efetivo
            using errcode = 'P0001';
        end if;
        v_patrimonio_resolvido := v_ids_encontrados[1];
      end if;

      if v_patrimonio_resolvido is null and v_corrigido_novo is not null then
        raise exception 'Patrimônio % não encontrado no InvTec — a correção do item % não foi aplicada', v_numero_efetivo, v_item_id
          using errcode = 'P0002';
      end if;

      v_vinculos := v_vinculos || jsonb_build_object(v_item_id::text, v_patrimonio_resolvido);
    end if;
  end loop;

  v_dados_antes := jsonb_build_object(
    'numero_documento_sei', v_documento.numero_documento_sei,
    'numero_processo', v_documento.numero_processo,
    'numero_documento_formatado', v_documento.numero_documento_formatado,
    'assunto', v_documento.assunto
  );

  -- Retrato "antes" dos itens que serão tocados — capturado ANTES do loop
  -- de correção, para o evento de auditoria registrar o antes/depois real
  -- (não só dos campos do documento).
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
      patrimonio_id = case when v_vinculos ? ((v_item_edicao ->> 'item_id')::uuid)::text
        then nullif(v_vinculos ->> ((v_item_edicao ->> 'item_id')::uuid)::text, '')::uuid else patrimonio_id end,
      destino_texto_corrigido = case when v_item_edicao ? 'destino_texto_corrigido'
        then v_item_edicao ->> 'destino_texto_corrigido' else destino_texto_corrigido end,
      numero_chamado_corrigido = case when v_item_edicao ? 'numero_chamado_corrigido'
        then v_item_edicao ->> 'numero_chamado_corrigido' else numero_chamado_corrigido end,
      equipamento_texto_corrigido = case when v_item_edicao ? 'equipamento_texto_corrigido'
        then v_item_edicao ->> 'equipamento_texto_corrigido' else equipamento_texto_corrigido end,
      -- Também editáveis enquanto o documento não tiver item concluído:
      -- destino resolvido, localização e responsável de destino (decisão +
      -- valor sempre juntos, para nunca violar as constraints de coerência).
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

-- =============================================================================
-- 11. RPC — cancelar_item_sei_pendente (sei.manage)
-- =============================================================================
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
  if private.has_permission('sei.manage') is not true then
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

-- =============================================================================
-- 12. RPC — cancelar_pendentes_documento_sei (sei.manage)
-- =============================================================================
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
  if private.has_permission('sei.manage') is not true then
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
-- 13. RPC — concluir_item_documento_sei (sei.manage)
-- =============================================================================
create or replace function public.concluir_item_documento_sei(
  p_documento_id uuid,
  p_item_id uuid,
  p_versao_esperada integer,
  p_observacao text default null,
  p_confirmar_limpeza_destino boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_documento public.documentos_sei;
  v_item public.documentos_sei_itens;
  v_item_antes jsonb;
  v_patrimonio public.patrimonios;
  v_patrimonio_depois public.patrimonios;
  v_movimentacao public.movimentacoes;
  v_numero_efetivo text;
  v_outro_patrimonio uuid;
  v_numero_documento text;
  v_numero_chamado text;
  v_motivo text;
  v_observacao text := public.normalize_text(p_observacao);
  v_localizacao_destino uuid;
  v_responsavel_destino text;
  v_limpa_localizacao boolean;
  v_limpa_responsavel boolean;
begin
  if private.has_permission('sei.manage') is not true then
    raise exception 'Usuário sem permissão para concluir item de documento SEI'
      using errcode = '42501';
  end if;

  if p_documento_id is null or p_item_id is null or p_versao_esperada is null then
    raise exception 'p_documento_id, p_item_id e p_versao_esperada são obrigatórios'
      using errcode = 'P0001';
  end if;

  -- trava o DOCUMENTO primeiro (mesma ordem de editar/cancelar)
  select * into v_documento
  from public.documentos_sei
  where id = p_documento_id
  for update;

  if not found then
    raise exception 'Documento SEI pendente % não encontrado', p_documento_id
      using errcode = 'P0002';
  end if;

  -- trava o ITEM depois do documento; confere que pertence a ele. A busca
  -- já filtra por documento_id: nunca travamos um item de outro documento
  -- enquanto seguramos este.
  select * into v_item
  from public.documentos_sei_itens
  where id = p_item_id and documento_id = p_documento_id
  for update;

  if not found then
    if exists (select 1 from public.documentos_sei_itens where id = p_item_id) then
      raise exception 'Item % não pertence ao documento %', p_item_id, p_documento_id
        using errcode = 'P0001';
    end if;
    raise exception 'Item % não encontrado', p_item_id using errcode = 'P0002';
  end if;

  -- IDEMPOTÊNCIA — item já concluído: devolve o estado existente, sem
  -- escrever nada. Fica ANTES da checagem de versão de propósito: quem repete
  -- a chamada (clique duplo, timeout) ainda envia a versão antiga, e um
  -- conflito de versão esconderia o fato de que a conclusão já aconteceu.
  if v_item.status = 'CONCLUIDO' then
    if v_item.movimentacao_id is null then
      raise exception 'Item % está CONCLUIDO sem movimentação vinculada — estado inconsistente, revisão manual necessária', p_item_id
        using errcode = 'P0030';
    end if;

    select * into v_movimentacao
    from public.movimentacoes
    where id = v_item.movimentacao_id;

    if not found then
      raise exception 'Movimentação % vinculada ao item % não encontrada — estado inconsistente', v_item.movimentacao_id, p_item_id
        using errcode = 'P0030';
    end if;

    -- O retry nunca pode devolver a movimentação de OUTRO patrimônio: ela precisa
    -- ser do patrimônio vinculado ao item (a trigger
    -- `validate_pendencia_movimentacao_patrimonio` já impede gravar o contrário,
    -- mas aqui conferimos de novo antes de expor o resultado).
    if v_item.patrimonio_id is null or v_movimentacao.patrimonio_id is distinct from v_item.patrimonio_id then
      raise exception 'Movimentação % não pertence ao patrimônio vinculado ao item % — estado inconsistente, revisão manual necessária', v_item.movimentacao_id, p_item_id
        using errcode = 'P0030';
    end if;

    return jsonb_build_object(
      'ja_concluido', true,
      'documento', to_jsonb(v_documento),
      'item', to_jsonb(v_item),
      'movimentacao', to_jsonb(v_movimentacao)
    );
  end if;

  -- conclusão NOVA: PENDENTE e sem movimentação
  if v_item.status = 'PENDENTE' and v_item.movimentacao_id is not null then
    raise exception 'Item % está PENDENTE mas já tem movimentação vinculada — estado inconsistente, revisão manual necessária', p_item_id
      using errcode = 'P0030';
  end if;

  if v_item.status <> 'PENDENTE' then
    raise exception 'Item % não está PENDENTE (está %) — não pode ser concluído', p_item_id, v_item.status
      using errcode = 'P0001';
  end if;

  -- versão (só para conclusão nova — ver comentário da idempotência acima)
  if v_documento.versao <> p_versao_esperada then
    raise exception 'Conflito de edição: versão % informada, versão atual % — releia o documento antes de tentar novamente',
      p_versao_esperada, v_documento.versao
      using errcode = 'P0010';
  end if;

  -- V1: somente TRANSFERENCIA
  if v_documento.tipo_operacao_pretendida <> 'TRANSFERENCIA' then
    raise exception 'A conclusão de entrega só suporta TRANSFERENCIA nesta versão (documento é %)', v_documento.tipo_operacao_pretendida
      using errcode = 'P0001';
  end if;

  -- destino e decisões explícitas (PENDENTE nunca vira null sozinho)
  if v_item.destino_setor_id is null then
    raise exception 'Item % não tem setor de destino resolvido', p_item_id
      using errcode = 'P0001';
  end if;
  if v_item.decisao_localizacao = 'PENDENTE' then
    raise exception 'Item %: a decisão sobre a localização de destino ainda está PENDENTE', p_item_id
      using errcode = 'P0001';
  end if;
  if v_item.decisao_responsavel = 'PENDENTE' then
    raise exception 'Item %: a decisão sobre o responsável de destino ainda está PENDENTE', p_item_id
      using errcode = 'P0001';
  end if;

  -- número efetivo, normalizado como `patrimonios.numero_patrimonio`
  -- (`upper(normalize_text(...))`, ver CHECK patrimonios_numero_patrimonio_normalizado).
  v_numero_efetivo := upper(public.normalize_text(
    coalesce(v_item.numero_patrimonio_corrigido, v_item.numero_patrimonio_original)
  ));
  if v_numero_efetivo is null then
    raise exception 'Item % não tem número de patrimônio', p_item_id
      using errcode = 'P0031';
  end if;
  if v_item.patrimonio_id is null then
    raise exception 'Item % não está vinculado a um patrimônio — corrija o número do patrimônio pela edição do documento', p_item_id
      using errcode = 'P0031';
  end if;

  -- trava o PATRIMÔNIO vinculado e exige que o número efetivo do item ainda
  -- seja o dele. Travar pelo `patrimonio_id` (e não pelo número) evita
  -- segurar a linha de um patrimônio que nada tem a ver com o item; como
  -- `numero_patrimonio` é ÚNICO, "número efetivo = número deste patrimônio"
  -- equivale a "o UUID encontrado pelo número é o `patrimonio_id`". O número
  -- também pode ter sido editado no patrimônio depois da importação
  -- (`authenticated` tem UPDATE em numero_patrimonio) — daí reconferir aqui,
  -- já sob lock.
  select * into v_patrimonio
  from public.patrimonios
  where id = v_item.patrimonio_id
  for update;

  if not found then
    raise exception 'Patrimônio % não encontrado', v_item.patrimonio_id
      using errcode = 'P0002';
  end if;

  if v_patrimonio.numero_patrimonio is distinct from v_numero_efetivo then
    select id into v_outro_patrimonio
    from public.patrimonios
    where numero_patrimonio = v_numero_efetivo;

    if v_outro_patrimonio is null then
      raise exception 'Patrimônio % não encontrado no InvTec — o patrimônio vinculado ao item agora tem outro número', v_numero_efetivo
        using errcode = 'P0002';
    end if;

    raise exception 'Vínculo incoerente: o número efetivo do item (%) pertence a outro patrimônio que o vinculado (%) — revalide o item pela edição do documento', v_numero_efetivo, v_item.patrimonio_id
      using errcode = 'P0031';
  end if;

  -- estado ATUAL do patrimônio contra o que o documento esperava
  if v_item.origem_setor_id is null then
    raise exception 'Item % não tem origem resolvida — não é possível confirmar o estado do patrimônio', p_item_id
      using errcode = 'P0032';
  end if;
  if v_patrimonio.setor_atual_id <> v_item.origem_setor_id then
    raise exception 'Origem divergente: o setor atual do patrimônio % não é o setor de origem do item — revisão humana necessária', v_numero_efetivo
      using errcode = 'P0032';
  end if;
  if v_patrimonio.status not in ('DISPONIVEL', 'EM_USO') then
    raise exception 'Patrimônio % está % — não pode ser transferido', v_numero_efetivo, v_patrimonio.status
      using errcode = 'P0032';
  end if;

  -- QUALQUER movimentação posterior à criação do item bloqueia — basta UMA
  -- das duas condições:
  --   * `m.criado_em > item.criado_em`: registro criado depois. `criado_em` é
  --     `now()`, o INÍCIO da transação de quem registrou;
  --   * `m.data_movimentacao > item.criado_em`: horário efetivo depois.
  --     `registrar_movimentacao` grava `clock_timestamp()` (o momento da
  --     execução, mais tarde que o início da transação), então isto fecha a
  --     janela de uma movimentação cuja transação COMEÇOU antes do item mas
  --     executou depois dele.
  -- LIMITE CONHECIDO: isto NÃO é uma ordenação absoluta por commit do
  -- PostgreSQL. Uma movimentação RETRODATADA manualmente (data informada antes
  -- da criação do item) cuja transação também começou antes do item, mas só foi
  -- commitada depois, escapa das duas condições; nesse caso a defesa restante é
  -- a validação do estado atual abaixo/acima (setor atual = origem do item,
  -- status compatível, vínculo UUID/número coerente), que continua obrigatória.
  -- Como o patrimônio está travado, nenhuma outra movimentação surge entre esta
  -- leitura e o fim da função.
  if exists (
    select 1
    from public.movimentacoes m
    where m.patrimonio_id = v_patrimonio.id
      and (
        m.criado_em > v_item.criado_em
        or m.data_movimentacao > v_item.criado_em
      )
  ) then
    raise exception 'O patrimônio % foi movimentado depois da criação desta pendência — revisão humana necessária', v_numero_efetivo
      using errcode = 'P0033';
  end if;

  -- movimentação prévia do mesmo patrimônio com o mesmo documento SEI
  v_numero_documento := coalesce(
    public.normalize_text(v_documento.numero_documento_sei),
    public.normalize_text(v_documento.numero_documento_formatado)
  );
  if v_numero_documento is not null and exists (
    select 1
    from public.movimentacoes m
    where m.patrimonio_id = v_patrimonio.id
      and public.normalize_text(m.numero_documento) = v_numero_documento
  ) then
    raise exception 'Já existe movimentação do patrimônio % com o documento % — revisão humana necessária', v_numero_efetivo, v_numero_documento
      using errcode = 'P0034';
  end if;

  -- parâmetros EXPLÍCITOS de localização e responsável. Em TRANSFERENCIA,
  -- `registrar_movimentacao` grava exatamente o que recebe:
  -- localização nula LIMPA a atual; responsável nulo LIMPA o atual e o status
  -- passa a DISPONIVEL. Nunca deixamos isso acontecer por acidente: DEFINIDO
  -- envia o valor; CONFIRMADO_SEM_INFORMACAO envia null DE PROPÓSITO.
  if v_item.decisao_localizacao = 'DEFINIDO' then
    v_localizacao_destino := v_item.localizacao_destino_id;
  else
    v_localizacao_destino := null;
  end if;

  if v_item.decisao_responsavel = 'DEFINIDO' then
    v_responsavel_destino := v_item.responsavel_destino;
  else
    v_responsavel_destino := null;
  end if;

  -- Movimentação interna (mesmo setor): `registrar_movimentacao` exige uma
  -- localização de destino diferente da atual — logo CONFIRMADO_SEM_INFORMACAO
  -- para a localização não é aceito aqui (mensagem clara em vez do erro dela).
  if v_item.destino_setor_id = v_patrimonio.setor_atual_id then
    if v_item.decisao_localizacao <> 'DEFINIDO' or v_localizacao_destino is null then
      raise exception 'Movimentação interna (mesmo setor) exige localização de destino DEFINIDA — CONFIRMADO_SEM_INFORMACAO não é aceito'
        using errcode = 'P0001';
    end if;
    if v_localizacao_destino is not distinct from v_patrimonio.localizacao_atual_id then
      raise exception 'A localização de destino precisa ser diferente da localização atual do patrimônio'
        using errcode = 'P0001';
    end if;
  end if;

  -- limpeza destrutiva exige confirmação explícita
  v_limpa_localizacao := v_localizacao_destino is null and v_patrimonio.localizacao_atual_id is not null;
  v_limpa_responsavel := v_responsavel_destino is null and v_patrimonio.responsavel_atual is not null;

  if (v_limpa_localizacao or v_limpa_responsavel) and p_confirmar_limpeza_destino is not true then
    raise exception 'A conclusão limparia % — confirme explicitamente a limpeza (p_confirmar_limpeza_destino) para prosseguir',
      concat_ws(' e ',
        case when v_limpa_localizacao then 'a localização atual' end,
        case when v_limpa_responsavel then 'o responsável atual (o patrimônio ficará DISPONIVEL)' end
      )
      using errcode = 'P0035';
  end if;

  v_numero_chamado := coalesce(v_item.numero_chamado_corrigido, v_item.numero_chamado_original);
  v_motivo := case
    when public.normalize_text(v_documento.numero_documento_formatado) is not null
      then 'Despacho SEI ' || public.normalize_text(v_documento.numero_documento_formatado)
    when v_numero_documento is not null
      then 'Despacho SEI ' || v_numero_documento
    else null
  end;

  v_item_antes := to_jsonb(v_item);

  -- registra a movimentação (mesma transação; se falhar, NADA foi escrito
  -- antes e nada fica depois — não há bloco EXCEPTION que engula o erro).
  select * into v_movimentacao
  from public.registrar_movimentacao(
    p_patrimonio_id => v_patrimonio.id,
    p_tipo => 'TRANSFERENCIA',
    p_destino_id => v_item.destino_setor_id,
    p_responsavel_destino => v_responsavel_destino,
    p_motivo => v_motivo,
    p_observacao => v_observacao,
    p_numero_documento => v_numero_documento,
    p_numero_chamado => v_numero_chamado,
    p_data_movimentacao => null,
    p_localizacao_destino_id => v_localizacao_destino,
    p_limpar_localizacao => false
  );

  -- item CONCLUIDO + movimentacao_id. O check `status_coerente` e a trigger
  -- `validate_pendencia_movimentacao_patrimonio` conferem, no banco, que a
  -- movimentação pertence ao patrimônio do item.
  update public.documentos_sei_itens
  set status = 'CONCLUIDO',
      movimentacao_id = v_movimentacao.id
  where id = v_item.id
  returning * into v_item;

  -- versão do documento
  update public.documentos_sei
  set versao = versao + 1,
      atualizado_em = now()
  where id = p_documento_id
  returning * into v_documento;

  select * into v_patrimonio_depois
  from public.patrimonios
  where id = v_patrimonio.id;

  -- auditoria: quem, quando (criado_em), qual movimentação e o resultado
  -- patrimonial. `movimentacao_id` também fica em documentos_sei_itens.
  insert into public.documentos_sei_eventos (documento_id, item_id, tipo, descricao, dados_antes, dados_depois, autor_id)
  values (
    p_documento_id,
    v_item.id,
    'ITEM_CONCLUIDO',
    format('Entrega concluída: patrimônio %s transferido (movimentação %s)%s',
      v_numero_efetivo, v_movimentacao.id,
      case when v_observacao is not null then ' — ' || v_observacao else '' end),
    jsonb_build_object(
      'item', v_item_antes,
      'patrimonio', jsonb_build_object(
        'setor_atual_id', v_patrimonio.setor_atual_id,
        'localizacao_atual_id', v_patrimonio.localizacao_atual_id,
        'responsavel_atual', v_patrimonio.responsavel_atual,
        'status', v_patrimonio.status
      )
    ),
    jsonb_build_object(
      'movimentacao_id', v_movimentacao.id,
      'numero_patrimonio_efetivo', v_numero_efetivo,
      'limpeza_confirmada', (v_limpa_localizacao or v_limpa_responsavel),
      'item', jsonb_build_object(
        'status', v_item.status,
        'movimentacao_id', v_item.movimentacao_id
      ),
      'movimentacao', jsonb_build_object(
        'tipo', v_movimentacao.tipo,
        'origem_id', v_movimentacao.origem_id,
        'destino_id', v_movimentacao.destino_id,
        'localizacao_origem_id', v_movimentacao.localizacao_origem_id,
        'localizacao_destino_id', v_movimentacao.localizacao_destino_id,
        'responsavel_origem', v_movimentacao.responsavel_origem,
        'responsavel_destino', v_movimentacao.responsavel_destino,
        'data_movimentacao', v_movimentacao.data_movimentacao
      ),
      'patrimonio', jsonb_build_object(
        'setor_atual_id', v_patrimonio_depois.setor_atual_id,
        'localizacao_atual_id', v_patrimonio_depois.localizacao_atual_id,
        'responsavel_atual', v_patrimonio_depois.responsavel_atual,
        'status', v_patrimonio_depois.status
      )
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'ja_concluido', false,
    'documento', to_jsonb(v_documento),
    'item', to_jsonb(v_item),
    'movimentacao', to_jsonb(v_movimentacao)
  );
end;
$$;

-- =============================================================================
-- 14. RPC — concluir_itens_documento_sei_lote (sei.manage)
-- =============================================================================
create or replace function public.concluir_itens_documento_sei_lote(
  p_documento_id uuid,
  p_item_ids uuid[],
  p_versao_esperada integer,
  p_lote_id uuid,
  p_observacao text default null,
  p_confirmar_limpeza_destino boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limite_itens constant integer := 200;
  -- MESMA normalização que `concluir_item_documento_sei`
  -- já aplica internamente (`v_observacao text := public.normalize_text(
  -- p_observacao);`, repassada a `registrar_movimentacao`): aparar
  -- espaço/tab/CR/LF nas pontas e transformar "" em `null`. `normalize_text`
  -- é `strict`, então `null` continua `null`. É este valor NORMALIZADO —
  -- nunca o texto cru de `p_observacao` — que fica gravado em
  -- `documentos_sei_lotes_conclusao.observacao` e que entra na comparação
  -- de retry (`is not distinct from`, mais abaixo): duas chamadas cujo
  -- texto bruto difere só em espaço nas pontas, ou "" vs. omitido, contam
  -- como a MESMA observação para fins de idempotência.
  v_observacao text := public.normalize_text(p_observacao);
  v_item_ids uuid[];
  v_lote public.documentos_sei_lotes_conclusao;
  v_documento public.documentos_sei;
  v_qtd_encontrados integer;
  v_qtd_nao_pendente integer;
  v_itens_nao_pendente text;
  v_item_id uuid;
  v_resultado_item jsonb;
  v_itens_resultado jsonb := '[]'::jsonb;
  v_versao_atual integer;
  v_resultado jsonb;
begin
  -- 1. perfil e parâmetros -----------------------------------------------
  if private.has_permission('sei.manage') is not true then
    raise exception 'Usuário sem permissão para concluir itens de documento SEI em lote'
      using errcode = '42501';
  end if;

  if p_documento_id is null or p_item_ids is null or p_versao_esperada is null or p_lote_id is null then
    raise exception 'p_documento_id, p_item_ids, p_versao_esperada e p_lote_id são obrigatórios'
      using errcode = 'P0001';
  end if;

  -- `p_confirmar_limpeza_destino` tem default `false`,
  -- mas um cliente pode enviar `null` explicitamente (ex.: JSON `null`),
  -- que sobrescreve o default. `null` é ambíguo (nem confirma nem nega a
  -- limpeza) e, sem esta checagem, só seria percebido tarde: na comparação
  -- de retry (a coluna é NOT NULL — nunca igual a `null` — gerando um
  -- P0037 confuso em vez de um erro claro) ou no INSERT final (violação de
  -- NOT NULL, depois de já ter concluído itens de verdade). Rejeitado
  -- aqui, antes de qualquer trabalho.
  if p_confirmar_limpeza_destino is null then
    raise exception 'p_confirmar_limpeza_destino não pode ser nulo (use true ou false)'
      using errcode = 'P0001';
  end if;

  if cardinality(p_item_ids) = 0 then
    raise exception 'p_item_ids não pode ser vazio' using errcode = 'P0001';
  end if;

  if cardinality(p_item_ids) > v_limite_itens then
    raise exception 'O lote excede o limite de % itens (recebeu %)', v_limite_itens, cardinality(p_item_ids)
      using errcode = 'P0001';
  end if;

  if exists (select 1 from unnest(p_item_ids) as x(id) where x.id is null) then
    raise exception 'p_item_ids não pode conter um elemento nulo' using errcode = 'P0001';
  end if;

  -- 2. canonicaliza (distinto + ordenado) e recusa duplicata explícita -----
  -- nunca deduplica silenciosamente: um array com item repetido é rejeitado
  -- (P0001), não corrigido nos bastidores.
  select array_agg(x.id order by x.id) into v_item_ids from unnest(p_item_ids) as x(id);
  if cardinality(v_item_ids) <> (select count(distinct x.id) from unnest(p_item_ids) as x(id)) then
    raise exception 'p_item_ids não pode conter o mesmo item repetido' using errcode = 'P0001';
  end if;

  -- 3. serializa qualquer outra chamada concorrente com o MESMO lote_id,
  -- mesmo que aponte para outro documento — antes de tomar qualquer lock
  -- de linha, para nunca duas transações processarem o mesmo lote_id ao
  -- mesmo tempo (mesmo padrão de `criar_documento_sei_pendente`, seção 6
  -- da migration 20260921170000).
  perform pg_advisory_xact_lock(hashtextextended('lote_sei:' || p_lote_id::text, 0));

  -- 4/5/6. já existe um registro para este lote_id? -------------------------
  select * into v_lote from public.documentos_sei_lotes_conclusao where lote_id = p_lote_id;

  if found then
    if v_lote.documento_id = p_documento_id
       and v_lote.item_ids = v_item_ids
       and v_lote.versao_esperada = p_versao_esperada
       and v_lote.observacao is not distinct from v_observacao
       and v_lote.confirmar_limpeza_destino = p_confirmar_limpeza_destino
       and v_lote.criado_por = auth.uid()
    then
      -- RETRY IDÊNTICO: devolve o resultado já registrado. Nenhum lock em
      -- documento/item/patrimônio, nenhuma escrita, nenhuma movimentação
      -- nova, nenhum evento novo.
      return v_lote.resultado || jsonb_build_object('ja_executado', true);
    end if;

    raise exception
      'lote_id % já foi usado para uma operação com parâmetros diferentes '
      '(documento, itens, versão esperada, observação, confirmação de limpeza ou usuário)',
      p_lote_id
      using errcode = 'P0037';
  end if;

  -- 7. trava DOCUMENTO -> ITENS, nessa ordem --------------------------------
  select * into v_documento from public.documentos_sei where id = p_documento_id for update;
  if not found then
    raise exception 'Documento SEI pendente % não encontrado', p_documento_id using errcode = 'P0002';
  end if;

  -- trava os N itens em ordem determinística (por id) — `FOR UPDATE` com
  -- `ORDER BY` trava as linhas na ordem em que são lidas do nó de
  -- ordenação, então a ordem de travamento é sempre a mesma entre chamadas
  -- concorrentes que compartilhem algum item.
  perform 1
  from public.documentos_sei_itens
  where id = any (v_item_ids) and documento_id = p_documento_id
  order by id
  for update;

  select count(*) into v_qtd_encontrados
  from public.documentos_sei_itens
  where id = any (v_item_ids) and documento_id = p_documento_id;

  if v_qtd_encontrados <> cardinality(v_item_ids) then
    raise exception 'Um ou mais itens do lote não existem ou não pertencem ao documento %', p_documento_id
      using errcode = 'P0002';
  end if;

  -- 8. consistência do conjunto ANTES de concluir qualquer item ------------
  -- como o passo 4/5/6 já garantiu que isto não é um retry bem-sucedido
  -- deste lote_id, qualquer item que não esteja PENDENTE aqui só pode ser
  -- interferência de outra operação (conclusão individual, outro lote,
  -- cancelamento) — o lote inteiro é recusado, nunca conclui só o restante.
  select count(*) into v_qtd_nao_pendente
  from public.documentos_sei_itens
  where id = any (v_item_ids) and status <> 'PENDENTE';

  if v_qtd_nao_pendente > 0 then
    select string_agg(format('%s (%s)', id, status), ', ' order by id) into v_itens_nao_pendente
    from public.documentos_sei_itens
    where id = any (v_item_ids) and status <> 'PENDENTE';
    raise exception 'Um ou mais itens do lote não estão PENDENTE: %', v_itens_nao_pendente
      using errcode = 'P0036';
  end if;

  -- 9. mesmo patrimônio não pode aparecer duas vezes no lote ---------------
  if exists (
    select 1
    from public.documentos_sei_itens
    where id = any (v_item_ids) and patrimonio_id is not null
    group by patrimonio_id
    having count(*) > 1
  ) then
    raise exception 'Dois ou mais itens deste lote apontam para o mesmo patrimônio'
      using errcode = 'P0001';
  end if;

  -- 10. versão inicial do documento -----------------------------------------
  if v_documento.versao <> p_versao_esperada then
    raise exception 'Conflito de edição: versão % informada, versão atual % — releia o documento antes de tentar novamente',
      p_versao_esperada, v_documento.versao
      using errcode = 'P0010';
  end if;

  -- 11. chama a RPC individual, uma vez por item, encadeando a versão -------
  -- NENHUMA regra de negócio é duplicada aqui: cada chamada roda o corpo
  -- inteiro (já homologado) de `concluir_item_documento_sei` — travas de
  -- patrimônio, validações P0030-P0035, `registrar_movimentacao`, o
  -- UPDATE do item e o INSERT do evento ITEM_CONCLUIDO. Itera pelo
  -- `patrimonio_id` resolvido (não pela ordem recebida do cliente) para
  -- que os locks de patrimônio saiam sempre na mesma ordem relativa entre
  -- execuções concorrentes.
  v_versao_atual := p_versao_esperada;

  for v_item_id in
    select i.id
    from public.documentos_sei_itens i
    where i.id = any (v_item_ids)
    order by i.patrimonio_id, i.id
  loop
    select public.concluir_item_documento_sei(
      p_documento_id,
      v_item_id,
      v_versao_atual,
      p_observacao,
      p_confirmar_limpeza_destino
    ) into v_resultado_item;

    v_versao_atual := (v_resultado_item -> 'documento' ->> 'versao')::int;
    v_itens_resultado := v_itens_resultado || jsonb_build_object('item_id', v_item_id, 'resultado', v_resultado_item);
  end loop;

  -- 12. registra o lote — só chega aqui se TODOS os itens concluíram ---------
  -- (qualquer exceção dentro do laço aborta a transação inteira e este
  -- INSERT nunca roda: nenhum registro de tentativa fracassada sobra).
  select * into v_documento from public.documentos_sei where id = p_documento_id;

  v_resultado := jsonb_build_object(
    'ja_executado', false,
    'documento', to_jsonb(v_documento),
    'itens', v_itens_resultado
  );

  insert into public.documentos_sei_lotes_conclusao (
    lote_id, documento_id, item_ids, versao_esperada, observacao, confirmar_limpeza_destino, criado_por, resultado
  ) values (
    p_lote_id, p_documento_id, v_item_ids, p_versao_esperada, v_observacao, p_confirmar_limpeza_destino, auth.uid(), v_resultado
  );

  -- 13. retorno agregado -----------------------------------------------------
  return v_resultado;
end;
$$;

-- =============================================================================
-- 15. RPC — aplicar_decisao_comparacao_patrimonio (ADMIN + patrimonio.compare_update)
-- =============================================================================
-- Única RPC com DUPLA checagem (seção 16 do pedido): mantém
-- `has_perfil('ADMIN')` (estrutural — só ADMIN sequer pode tentar, nenhum
-- override de permissão consegue dar isto a OPERADOR/GESTOR/CONSULTA) e
-- ACRESCENTA `has_permission('patrimonio.compare_update')` (um ADMIN
-- específico pode ter essa capacidade revogada por override, sem deixar de
-- ser ADMIN para o resto do sistema).
create or replace function public.aplicar_decisao_comparacao_patrimonio(
  p_operacao_id uuid,
  p_lote_id uuid,
  p_patrimonio_id uuid,
  p_versao_esperada timestamptz,
  p_justificativa text default null,
  p_numero_serie text default null,
  p_marca text default null,
  p_modelo text default null,
  p_descricao text default null,
  p_observacao text default null,
  p_novo_setor_id uuid default null,
  p_nova_localizacao_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_numero_serie text := nullif(btrim(p_numero_serie), '');
  v_marca text := nullif(btrim(p_marca), '');
  v_modelo text := nullif(btrim(p_modelo), '');
  v_descricao text := nullif(btrim(p_descricao), '');
  v_observacao text := nullif(btrim(p_observacao), '');
  v_justificativa text := nullif(btrim(p_justificativa), '');
  v_patrimonio public.patrimonios;
  v_campos jsonb;
  v_existente record;
  v_resultado jsonb;
  v_movimentacao public.movimentacoes;
  v_tem_metadado boolean;
  v_tem_movimentacao boolean;
  v_pendencia_sei boolean;
begin
  if private.has_perfil('ADMIN') is not true then
    raise exception 'Somente administradores podem executar decisões de comparação patrimonial'
      using errcode = '42501';
  end if;
  if private.has_permission('patrimonio.compare_update') is not true then
    raise exception 'Usuário sem permissão patrimonio.compare_update'
      using errcode = '42501';
  end if;

  if p_operacao_id is null or p_lote_id is null or p_patrimonio_id is null or p_versao_esperada is null then
    raise exception 'operacao_id, lote_id, patrimonio_id e versao_esperada são obrigatórios'
      using errcode = 'P0001';
  end if;

  v_tem_metadado := v_numero_serie is not null or v_marca is not null
    or v_modelo is not null or v_descricao is not null or v_observacao is not null;
  v_tem_movimentacao := p_novo_setor_id is not null or p_nova_localizacao_id is not null;

  if not v_tem_metadado and not v_tem_movimentacao then
    raise exception 'Nenhum campo foi informado para atualização'
      using errcode = 'P0043';
  end if;

  if v_tem_movimentacao and v_justificativa is null then
    raise exception 'Alterações de setor/localização exigem uma justificativa administrativa'
      using errcode = 'P0001';
  end if;

  -- Trava pelo operacao_id ANTES de ler/escrever: serializa duas chamadas
  -- concorrentes com o mesmo id (sem isso, as duas passariam pela checagem
  -- de idempotência abaixo e uma quebraria com violação de chave primária
  -- depois de já ter escrito). Liberada automaticamente no fim da transação.
  perform pg_advisory_xact_lock(hashtextextended('comparacao_patrimonio:' || p_operacao_id::text, 0));

  -- Forma canônica dos campos, usada só para a checagem de identidade de um
  -- retry (nunca para decidir o que gravar).
  v_campos := jsonb_strip_nulls(jsonb_build_object(
    'numero_serie', v_numero_serie,
    'marca', v_marca,
    'modelo', v_modelo,
    'descricao', v_descricao,
    'observacao', v_observacao,
    'novo_setor_id', p_novo_setor_id,
    'nova_localizacao_id', p_nova_localizacao_id
  ));

  -- Idempotência: mesmo operacao_id já processado antes — nenhuma nova
  -- escrita, devolve exatamente o que foi gravado da primeira vez.
  select e.lote_id, e.patrimonio_id, e.versao_esperada, e.campos_solicitados, e.justificativa, e.criado_por, e.resultado
    into v_existente
  from public.patrimonio_comparacao_execucoes e
  where e.operacao_id = p_operacao_id;

  if found then
    if v_existente.lote_id <> p_lote_id
       or v_existente.patrimonio_id <> p_patrimonio_id
       or v_existente.versao_esperada <> p_versao_esperada
       or v_existente.campos_solicitados <> v_campos
       or v_existente.justificativa is distinct from v_justificativa
       or v_existente.criado_por <> auth.uid() then
      raise exception 'operacao_id já foi utilizado com parâmetros ou usuário diferentes'
        using errcode = 'P0041';
    end if;
    return v_existente.resultado || jsonb_build_object('ja_executado', true);
  end if;

  -- Trava a linha do patrimônio: entre duas operações com operacao_id
  -- diferentes mirando o mesmo patrimônio a partir do mesmo snapshot, a
  -- primeira a chegar aqui conclui; a segunda relê `atualizado_em` já
  -- alterado e cai no conflito de versão abaixo.
  select p.* into v_patrimonio
  from public.patrimonios p
  where p.id = p_patrimonio_id
  for update;

  if not found then
    raise exception 'Patrimônio % não encontrado', p_patrimonio_id
      using errcode = 'P0002';
  end if;

  -- Revalidação: se o patrimônio mudou desde a referência usada na decisão
  -- do administrador, é conflito — nunca uma sobrescrita silenciosa.
  if v_patrimonio.atualizado_em is distinct from p_versao_esperada then
    raise exception 'O patrimônio foi alterado por outra operação desde a comparação — revise antes de aplicar'
      using errcode = 'P0040';
  end if;

  -- Pendência SEI bloqueia só quando a decisão muda setor/localização — uma
  -- correção de metadados isolada não interfere com uma entrega SEI pendente.
  if v_tem_movimentacao then
    select exists (
      select 1
      from public.documentos_sei_itens i
      where i.patrimonio_id = p_patrimonio_id
        and i.status = 'PENDENTE'
    ) into v_pendencia_sei;

    if v_pendencia_sei then
      raise exception 'Patrimônio possui pendência SEI aberta — resolva ou cancele o item SEI antes de alterar setor/localização'
        using errcode = 'P0042';
    end if;
  end if;

  if v_tem_metadado then
    update public.patrimonios
    set numero_serie = coalesce(v_numero_serie, numero_serie),
        marca = coalesce(v_marca, marca),
        modelo = coalesce(v_modelo, modelo),
        descricao = coalesce(v_descricao, descricao),
        observacao = coalesce(v_observacao, observacao)
    where id = p_patrimonio_id;
  end if;

  if v_tem_movimentacao then
    -- Reaproveita registrar_movimentacao (nenhuma regra de setor/localização
    -- duplicada aqui). Uma exceção aqui desfaz também o UPDATE de metadados
    -- acima, por estarem na mesma transação.
    v_movimentacao := public.registrar_movimentacao(
      p_patrimonio_id := p_patrimonio_id,
      p_tipo := 'AJUSTE_INVENTARIO',
      p_destino_id := p_novo_setor_id,
      p_motivo := v_justificativa,
      p_observacao := 'Regularização cadastral via comparação de planilha (lote ' || p_lote_id::text || ').',
      p_localizacao_destino_id := p_nova_localizacao_id
    );
  end if;

  v_resultado := jsonb_build_object(
    'patrimonio_id', p_patrimonio_id,
    'metadados_atualizados', v_tem_metadado,
    'movimentacao_registrada', v_tem_movimentacao,
    'movimentacao_id', v_movimentacao.id,
    'concluido_em', clock_timestamp(),
    'ja_executado', false
  );

  insert into public.patrimonio_comparacao_execucoes (
    operacao_id, lote_id, patrimonio_id, versao_esperada, campos_solicitados,
    justificativa, criado_por, resultado
  ) values (
    p_operacao_id, p_lote_id, p_patrimonio_id, p_versao_esperada, v_campos,
    v_justificativa, auth.uid(), v_resultado
  );

  return v_resultado;
end;
$$;

-- =============================================================================
-- 16. GRANTS
-- =============================================================================
-- Nenhum GRANT novo é necessário: todas as 9 funções acima já tinham
-- EXECUTE concedido a `authenticated` desde a migration em que nasceram
-- (CREATE OR REPLACE preserva owner/ACL) — só o CORPO mudou. `aplicar_
-- decisao_comparacao_patrimonio` idem.
