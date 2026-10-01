-- =============================================================================
-- PROMPT 11.6.4 — execução segura das decisões do modo ADMIN "Comparar e
-- Atualizar" (PROMPT 11.6.2/11.6.3): aplica, PATRIMÔNIO POR PATRIMÔNIO, os
-- campos que o administrador marcou como "aplicar valor da planilha".
--
-- PROMPT 11.6.5 — CORRIGIDA durante a auditoria de homologação, ANTES de
-- qualquer aplicação real (o arquivo nunca chegou a rodar em produção nem em
-- homologação — por isso as correções foram feitas neste MESMO arquivo, em
-- vez de uma migration de correção em cima de algo já aplicado, seguindo o
-- mesmo raciocínio documentado nas migrations SEI quando uma correção
-- acontece ANTES da primeira aplicação real):
--  1. (seção 2 do PROMPT 11.6.5) trava consultiva `pg_advisory_xact_lock`
--     sobre o `operacao_id` ANTES da checagem de idempotência — duas
--     chamadas concorrentes com o MESMO `operacao_id` agora são serializadas
--     de verdade (a versão anterior só tinha um SELECT antes do INSERT, sem
--     nenhuma proteção transacional: duas chamadas simultâneas passariam as
--     duas pelo SELECT "não encontrado" e uma delas quebraria com violação
--     de chave primária DEPOIS de já ter feito a escrita real);
--  2. (seção 2C) `p_justificativa` agora entra na checagem de identidade de
--     um retry — reenviar o mesmo `operacao_id` com uma justificativa
--     DIFERENTE agora é `P0041` (conflito), nunca silenciosamente aceito;
--  3. (seção 4) `p_numero_patrimonio` foi REMOVIDO da função inteiramente —
--     ver a justificativa completa abaixo, antes da assinatura.
-- =============================================================================
--
-- STATUS: PREPARADA PARA REVISÃO — NÃO APLICADA em produção nesta etapa
-- (restrição explícita do PROMPT 11.6.4, seção 10, reafirmada no PROMPT
-- 11.6.5, seção 9: "não aplicar a migration em produção para contornar a
-- limitação [de não haver Postgres disponível]").
--
-- DESENHO (por que uma função POR PATRIMÔNIO, chamada uma vez por item, em
-- vez de uma única função que recebe o lote inteiro):
--  * seção 4 exige garantia TRANSACIONAL só por patrimônio (nunca metadados
--    aplicados com a movimentação correspondente falhando à parte) — uma
--    função plpgsql é sempre UMA transação, então "uma chamada = um
--    patrimônio" já entrega isso sem savepoints manuais;
--  * seção 6 pede lotes de tamanho CONTROLADO com progresso e resultado
--    IDENTIFICÁVEL por item, nunca uma operação monolítica — o cliente
--    (`ComparacaoExecucaoController`) chama esta função várias vezes, com
--    concorrência limitada (mesmo padrão de `_executarLote`/
--    `importConcorrenciaMaxima` já usado pela importação convencional),
--    preservando cada resultado individualmente;
--  * evita reescrever a máquina de estados inteira de
--    `concluir_itens_documento_sei_lote` (pensada para um lote de ATÉ 200
--    itens processados como uma ÚNICA operação atômica) para um cenário
--    onde o requisito é o OPOSTO: falhas isoladas por item, nunca a falha
--    de um patrimônio invalidando os outros 1.999.
--
-- REAPROVEITAMENTO (seção 2): esta função NUNCA atualiza `setor_atual_id`
-- nem `localizacao_atual_id` diretamente — qualquer alteração de setor/
-- localização é sempre uma chamada a `public.registrar_movimentacao` já
-- existente e homologada (tipo `AJUSTE_INVENTARIO`, que já cobre setor,
-- localização ou os dois ao mesmo tempo, sem nenhuma regra nova). Metadados
-- de texto simples (mesmos campos de `PatrimonioRepository.atualizar`,
-- EXCETO `numero_patrimonio` — ver seção 4 abaixo) são gravados por um
-- UPDATE direto, exatamente como `atualizar()` já faz hoje.
--
-- SEÇÃO 4 DO PROMPT 11.6.5 — por que `numero_patrimonio` NÃO é um campo
-- aplicável por esta função (diferente da versão original desta migration,
-- que o incluía por espelhar `PatrimonioRepository.atualizar`):
-- `numero_patrimonio` é a CHAVE usada para casar cada linha da planilha com
-- um patrimônio existente (`ImportAnalyzer`/`PatrimonioComparador` — ver
-- `buscarPorNumerosPatrimonio`) — é o que TORNA a linha "a mesma" que o
-- registro do banco. Permitir sua alteração pelo MESMO fluxo que decide
-- "isto é o mesmo bem, com estes campos divergentes" mistura identidade do
-- registro com o conteúdo do registro: uma correção de tombamento mal
-- pensada poderia (a) fazer uma planilha futura deixar de casar com o
-- patrimônio corrigido (por comparar contra o número ANTIGO), (b) colidir
-- com a identidade de outra linha da MESMA planilha, e (c) confundir a
-- leitura do histórico de movimentações (que não guarda um "número
-- patrimonial no momento", só referencia o patrimônio por id). Uma correção
-- de tombamento legítima continua possível — pelo formulário de edição
-- normal (`PatrimonioRepository.atualizar`, tela de detalhe do patrimônio),
-- nunca por aqui. `tombamento_anterior` (`ImportColumnField
-- .tombamentoAnterior`) é um campo DIFERENTE (histórico livre, nunca
-- comparado/aplicado por este fluxo) e continua sem nenhuma relação com
-- `numero_patrimonio` — ver `_compararMetadados` em `patrimonio_comparacao
-- .dart`, que nunca o usa.
-- =============================================================================

-- =============================================================================
-- 1. Tabela de controle: uma linha por OPERAÇÃO (= uma chamada bem-sucedida
--    desta função para UM patrimônio), nunca reaproveitando
--    `documentos_sei_lotes_conclusao` (que pertence exclusivamente ao fluxo
--    SEI — restrição explícita da seção 6). `operacao_id` é gerado no
--    CLIENTE (mesmo padrão de `lote_id` em `documentos_sei_lotes_conclusao`)
--    e nunca recriado num retry — é ele que torna um retry seguro: uma
--    segunda chamada com o MESMO `operacao_id` encontra esta linha e
--    devolve o resultado já gravado, sem repetir a escrita.
--
-- VISIBILIDADE (PROMPT 11.6.5, seção 1 — "verificar se um usuário consegue
-- consultar indevidamente operações de outro usuário"): a policy abaixo
-- deixa QUALQUER ADMIN ler QUALQUER linha (não só as suas), DE PROPÓSITO —
-- mesma decisão já tomada e revisada para `documentos_sei_lotes_conclusao`
-- (`has_perfil('ADMIN','GESTOR','OPERADOR','CONSULTA')`, sem filtro por
-- `criado_por`): esta tabela é uma trilha de auditoria administrativa
-- (quem regularizou o quê, quando, com qual justificativa), não um dado
-- pessoal do usuário que a criou — um ADMIN precisa poder auditar
-- regularizações feitas por OUTRO ADMIN. A defesa de que uma leitura nunca
-- é confundida com "esta é a MINHA operação em andamento" fica no
-- CLIENTE, que confere `criado_por` contra a sessão atual antes de tratar
-- um resultado de `buscarExecucaoComparacaoPorOperacaoId` como a resposta
-- da própria tentativa pendente (ver o comentário em
-- `PatrimonioRepositorySupabase.buscarExecucaoComparacaoPorOperacaoId`) —
-- mesmo padrão de defesa em profundidade de
-- `DocumentosSeiRepositorySupabase.buscarLotePorId`.
-- =============================================================================
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

-- =============================================================================
-- 2. RPC principal.
--
-- Parâmetros de metadado (p_numero_serie.. p_observacao): mesma semântica de
-- `PatrimonioRepository.atualizar` — um valor NÃO NULO significa "aplicar
-- este novo valor"; NULO significa "preservar o valor atual" (nunca apaga
-- por omissão — seção 4: "ausência de decisão significa preservar o valor
-- atual"). Em nenhum caso um valor NULO ou vazio some com um valor
-- existente: o Flutter nunca envia string vazia (só omite o parâmetro) e,
-- em defesa adicional, `nullif(btrim(...), '')` trata uma string vazia
-- exatamente como ausência. `numero_patrimonio` NÃO é um parâmetro desta
-- função — ver a justificativa da seção 4 no cabeçalho do arquivo.
--
-- p_novo_setor_id / p_nova_localizacao_id: quando informados, tornam-se
-- `p_destino_id`/`p_localizacao_destino_id` de UMA chamada a
-- `registrar_movimentacao` com `p_tipo = 'AJUSTE_INVENTARIO'` — nunca um
-- UPDATE direto das colunas de setor/localização (seção 2, restrição
-- explícita). Uma troca de setor SEM uma nova localização explícita limpa a
-- localização atual (mesma regra (b) já existente e homologada dentro de
-- `registrar_movimentacao` para AJUSTE_INVENTARIO: uma localização
-- pertence a exatamente um setor, então a localização antiga nunca pode
-- permanecer válida sob o setor novo) — o cliente deve avisar isso
-- explicitamente ao administrador ANTES de confirmar (ver
-- `import_comparacao_resumo_step.dart`), nunca como uma surpresa silenciosa
-- depois.
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

  -- PROMPT 11.6.5, seção 2D — trava CONSULTIVA pelo próprio operacao_id,
  -- ANTES de qualquer leitura/escrita: duas chamadas concorrentes com o
  -- MESMO operacao_id agora são SERIALIZADAS de verdade (a primeira a
  -- chegar aqui trava; a segunda espera até a primeira commitar/abortar).
  -- Sem isto, a checagem de idempotência abaixo era só um SELECT antes do
  -- INSERT: duas chamadas simultâneas passariam as duas pela checagem
  -- "não encontrado ainda" e a segunda quebraria com violação de chave
  -- primária DEPOIS de já ter aplicado metadados/movimentação de verdade —
  -- nunca uma duplicação silenciosa, mas um erro confuso e uma escrita já
  -- feita sem o retorno idempotente limpo. `hashtextextended` com o mesmo
  -- padrão de `concluir_itens_documento_sei_lote`
  -- (`pg_advisory_xact_lock`, liberada automaticamente no fim da
  -- transação — nunca precisa de um unlock manual).
  perform pg_advisory_xact_lock(hashtextextended('comparacao_patrimonio:' || p_operacao_id::text, 0));

  -- Forma canônica dos campos solicitados: usada, junto com lote_id/
  -- justificativa/patrimonio_id/versao_esperada/criado_por, SÓ para a
  -- checagem de identidade de um retry — nunca para decidir o que gravar
  -- (isso sempre vem dos parâmetros normalizados acima).
  v_campos := jsonb_strip_nulls(jsonb_build_object(
    'numero_serie', v_numero_serie,
    'marca', v_marca,
    'modelo', v_modelo,
    'descricao', v_descricao,
    'observacao', v_observacao,
    'novo_setor_id', p_novo_setor_id,
    'nova_localizacao_id', p_nova_localizacao_id
  ));

  -- Idempotência (seção 6): mesmo operacao_id já processado antes (agora
  -- protegido pela trava acima contra a corrida de duas primeiras
  -- chamadas simultâneas) — nenhuma nova escrita, devolve exatamente o
  -- que foi gravado da primeira vez.
  select e.lote_id, e.patrimonio_id, e.versao_esperada, e.campos_solicitados, e.justificativa, e.criado_por, e.resultado
    into v_existente
  from public.patrimonio_comparacao_execucoes e
  where e.operacao_id = p_operacao_id;

  if found then
    if v_existente.lote_id <> p_lote_id
       or v_existente.patrimonio_id <> p_patrimonio_id
       or v_existente.versao_esperada <> p_versao_esperada
       or v_existente.campos_solicitados <> v_campos
       -- PROMPT 11.6.5, seção 2C — justificativa agora faz parte da
       -- identidade da operação: reenviar o mesmo operacao_id com uma
       -- justificativa diferente é tão inaceitável quanto com um campo
       -- diferente.
       or v_existente.justificativa is distinct from v_justificativa
       or v_existente.criado_por <> auth.uid() then
      raise exception 'operacao_id já foi utilizado com parâmetros ou usuário diferentes'
        using errcode = 'P0041';
    end if;
    return v_existente.resultado || jsonb_build_object('ja_executado', true);
  end if;

  -- trava o patrimônio: mesma disciplina de `registrar_movimentacao`
  -- (serializa operações concorrentes sobre o mesmo item — PROMPT 11.6.5,
  -- seção 2E: entre duas operações com operacao_id DIFERENTES mirando o
  -- MESMO patrimônio a partir do mesmo snapshot, a primeira a chegar aqui
  -- trava, conclui e commita; a segunda só prossegue depois, relê
  -- `atualizado_em` já alterado pela primeira e cai no conflito de versão
  -- abaixo — nunca as duas aplicam por cima uma da outra).
  select p.* into v_patrimonio
  from public.patrimonios p
  where p.id = p_patrimonio_id
  for update;

  if not found then
    raise exception 'Patrimônio % não encontrado', p_patrimonio_id
      using errcode = 'P0002';
  end if;

  -- Revalidação (seção 5): a comparação inicial não é autorização
  -- suficiente para gravar — se o patrimônio mudou desde a referência usada
  -- na decisão do administrador, é um CONFLITO, nunca uma sobrescrita
  -- silenciosa.
  if v_patrimonio.atualizado_em is distinct from p_versao_esperada then
    raise exception 'O patrimônio foi alterado por outra operação desde a comparação — revise antes de aplicar'
      using errcode = 'P0040';
  end if;

  -- Pendência SEI incompatível (seção 5): nunca abrir um caminho
  -- administrativo que contorne, sem querer, as proteções do módulo SEI —
  -- só bloqueia quando a decisão realmente muda setor/localização (uma
  -- correção de metadados isolada não interfere com uma entrega SEI
  -- pendente).
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
    -- Reaproveita INTEIRAMENTE `registrar_movimentacao` — nenhuma regra de
    -- transição/validação de setor/localização duplicada aqui (seção 2).
    -- Uma exceção levantada aqui desfaz TAMBÉM o UPDATE de metadados
    -- acima (mesma transação, sem handler capturando no meio — PROMPT
    -- 11.6.5, seção 3: "se a movimentação falhar, nenhuma alteração de
    -- metadados poderá permanecer gravada").
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
