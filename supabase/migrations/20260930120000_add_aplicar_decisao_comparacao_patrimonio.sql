-- Aplica decisões de comparação patrimonial (planilha x cadastro), uma
-- chamada por patrimônio, dentro de uma única transação: metadados e/ou
-- movimentação de ajuste são tudo-ou-nada. Operação idempotente por
-- operacao_id e exclusiva para ADMIN.
--
-- `numero_patrimonio` nunca é um campo aplicável aqui: é a chave usada para
-- casar a linha da planilha com o patrimônio existente, então alterá-la por
-- este fluxo misturaria identidade do registro com conteúdo do registro.
-- Correção de tombamento é feita pelo formulário de edição normal.

-- 1. Tabela de controle: uma linha por operação (chamada bem-sucedida desta
-- função para um patrimônio). operacao_id é gerado no cliente e nunca
-- recriado num retry — uma segunda chamada com o mesmo id devolve o
-- resultado já gravado, sem repetir a escrita.
--
-- Qualquer ADMIN pode ler qualquer linha (trilha de auditoria administrativa,
-- não dado pessoal do usuário que criou); o cliente confere `criado_por`
-- contra a sessão atual antes de tratar uma leitura como a própria tentativa
-- pendente.
create table public.patrimonio_comparacao_execucoes (
  operacao_id uuid primary key,
  -- agrupa todos os itens de uma mesma "rodada" de execução (só para
  -- consulta/relatório — nunca usado para decidir idempotência, que é
  -- inteiramente por operacao_id).
  lote_id uuid not null,
  patrimonio_id uuid not null references public.patrimonios (id) on delete restrict,
  -- snapshot de `patrimonios.atualizado_em` no momento em que a comparação
  -- foi feita — é contra ISTO que a revalidação (seção 5) compara o estado
  -- atual antes de gravar.
  versao_esperada timestamptz not null,
  -- canônico (chaves ordenadas via jsonb_build_object determinístico) —
  -- usado, JUNTO com justificativa/patrimonio_id/versao_esperada/criado_por,
  -- para a checagem de identidade de um retry (seção 6): mesmo operacao_id,
  -- parâmetros diferentes nunca é aceito silenciosamente.
  campos_solicitados jsonb not null,
  justificativa text,
  criado_por uuid not null references public.profiles (id) on delete restrict,
  criado_em timestamptz not null default now(),
  -- resposta EXATA devolvida na primeira execução — replicada sem nenhuma
  -- nova escrita em qualquer retry com o mesmo operacao_id.
  resultado jsonb not null,
  constraint patrimonio_comparacao_execucoes_campos_objeto check (jsonb_typeof(campos_solicitados) = 'object')
);

create index patrimonio_comparacao_execucoes_lote_idx on public.patrimonio_comparacao_execucoes (lote_id);
create index patrimonio_comparacao_execucoes_patrimonio_idx on public.patrimonio_comparacao_execucoes (patrimonio_id);

alter table public.patrimonio_comparacao_execucoes enable row level security;

-- Só ADMIN lê (mesmo perfil exigido para executar) — nenhuma escrita
-- concedida a `authenticated`: a única forma de inserir uma linha é a
-- função SECURITY DEFINER abaixo. Ver o comentário acima sobre visibilidade
-- entre usuários ADMIN.
create policy patrimonio_comparacao_execucoes_select on public.patrimonio_comparacao_execucoes
  for select
  to authenticated
  using ((select private.has_perfil('ADMIN')));

revoke all on table public.patrimonio_comparacao_execucoes from public, anon, authenticated;
grant select on table public.patrimonio_comparacao_execucoes to authenticated;

-- 2. RPC principal.
--
-- Parâmetros de metadado: valor não nulo aplica; nulo preserva o atual
-- (nunca apaga por omissão). p_novo_setor_id/p_nova_localizacao_id sempre
-- passam por `registrar_movimentacao` (AJUSTE_INVENTARIO), nunca por UPDATE
-- direto de setor/localização. Trocar de setor sem nova localização limpa a
-- localização atual (uma localização pertence a um único setor).
create function public.aplicar_decisao_comparacao_patrimonio(
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

revoke all on function public.aplicar_decisao_comparacao_patrimonio from public, anon, authenticated;
grant execute on function public.aplicar_decisao_comparacao_patrimonio to authenticated;
