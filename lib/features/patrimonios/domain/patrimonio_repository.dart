import '../../../core/domain/ordenacao_direcao.dart';
import '../importacao/domain/comparacao_execucao.dart';
import '../retificacao/domain/retificacao_execucao.dart';
import 'patrimonio.dart';
import 'patrimonio_cadastro_lote.dart';
import 'patrimonio_detalhe.dart';
import 'patrimonio_ordenacao.dart';
import 'patrimonio_search_field.dart';
import 'patrimonios_resultado.dart';
import 'tombamento_historico_item.dart';

/// Controla [PatrimonioRepository.buscarPorTombamentoAnterior]: enquanto
/// `false`, o repositório nunca tenta consultar
/// `patrimonio_tombamentos_historico` (nem em caso de engano — ver o
/// `try/catch` defensivo na implementação Supabase, uma segunda camada de
/// proteção que continua ativa independente desta flag).
///
/// `true` a partir de 2026-10-20 — migration `20261014100000_add_
/// patrimonio_tombamento_historico.sql` (Fase 3A.4) e a RPC de importação
/// (`20261019120000`) foram aplicadas e conferidas em produção; os 121
/// candidatos aprovados foram importados administrativamente (121
/// registrados, 0 conflitos, 0 falhas). Decisão administrativa, não
/// técnica — nunca ligar isto automaticamente a partir de uma consulta ao
/// banco.
const bool historicoTombamentosDisponivel = true;

abstract class PatrimonioRepository {
  Future<Patrimonio?> buscarPorId(String id);

  /// Detalhe com tipo/setor (e, quando a RLS permitir, quem cadastrou) já
  /// resolvidos — usado na tela de detalhe.
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id);

  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio);

  /// Busca EXATA (nunca substring, nunca sujeita a paginação) por [codigo]
  /// no tombamento ATUAL — mesma igualdade normalizada de zeros à esquerda
  /// usada em todo o projeto (ver `normalizarTombamentoParaComparacao`).
  ///
  /// Ao contrário de [listar] (ILIKE `%...%`, pensado para o humano
  /// revisar uma LISTA de candidatos, com paginação — então um
  /// `numero_patrimonio` existente mas fora da página retornada pode
  /// nunca aparecer) e de [buscarPorPrefixoNumeroPatrimonio] (prefixo, com
  /// teto fixo de resultados), este método existe para decidir IDENTIDADE
  /// automaticamente (leitor de código de barras): nunca pode perder a
  /// correspondência verdadeira só porque ela "não coube" em uma página.
  ///
  /// Devolve TODOS os patrimônios cuja chave normalizada bate com
  /// [codigo] — 0 ou 1 no caso comum; mais de 1 é uma anomalia de dados
  /// (duplicidade), nunca resolvida/escolhida automaticamente aqui.
  ///
  /// Lança [AcessoInsuficienteException] (nunca [AppException] genérica)
  /// quando a própria consulta é recusada por falta de permissão — quem
  /// chama precisa diferenciar isso de "não encontrado" e de uma falha de
  /// rede comum.
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(String codigo);

  /// Busca rápida por PREFIXO de `numero_patrimonio` (ex.: "3636" encontra
  /// "3636001"/"3636127", nunca "1236360") — usada pelo diálogo "Consultar
  /// patrimônio" do Dashboard. Sempre resolvida no SERVIDOR (nunca baixa
  /// tudo para filtrar no Flutter), com tipo/setor/localização já
  /// resolvidos no mesmo embed (zero N+1), ordenada por
  /// `numero_patrimonio` ASC (texto) e limitada a [limit] — esse limite é
  /// exclusivo desta busca rápida, nunca aplicado à listagem oficial de
  /// [listar]. [prefixo] vazio (após trim) devolve lista vazia sem
  /// consultar o servidor.
  Future<List<PatrimonioDetalhe>> buscarPorPrefixoNumeroPatrimonio(
    String prefixo, {
    int limit = 6,
  });

  /// Página de patrimônios com tipo/setor já resolvidos (embed, sem N+1).
  /// [tipoId], [status], [setorId], [localizacaoId]/[semLocalizacao],
  /// [marca], [modelo], [responsavel] e os intervalos de data são filtros
  /// opcionais, todos combináveis entre si e com a busca por AND. Sempre
  /// resolvidos no servidor: nunca carrega a página inteira para
  /// filtrar/paginar em memória.
  ///
  /// [busca] é interpretado de acordo com [campoBusca]:
  /// - [PatrimonioSearchField.patrimonio]: QUALQUER SEQUÊNCIA CONTÍGUA de
  ///   dígitos de `numero_patrimonio` (`ILIKE '%termo%'`, em qualquer
  ///   posição — início, meio ou fim) — "3636" encontra "3636001",
  ///   "1236360" E "0036360", já que zeros à esquerda digitados são
  ///   equivalentes aos do número armazenado (ver
  ///   `normalizarTombamentoParaComparacao`). A correspondência exata
  ///   continua funcionando como caso particular. Sem nenhum limite de
  ///   itens além da paginação normal desta listagem (o teto de 6
  ///   resultados é exclusivo do diálogo "Consultar patrimônio" do
  ///   Dashboard — ver [buscarPorPrefixoNumeroPatrimonio]). Além de
  ///   [PatrimoniosResultado.itens], também preenche
  ///   [PatrimoniosResultado.correspondenciasPorTombamentoAnterior] quando
  ///   [historicoTombamentosDisponivel] for `true` (ver
  ///   [buscarPorTombamentoAnterior]) — hoje sempre vazio.
  /// - [PatrimonioSearchField.tudo] (padrão): se [busca] contém só dígitos,
  ///   trata como identificador — mesma regra de sequência contígua do
  ///   campo [patrimonio] OU `numero_serie` EXATO como aviso separado
  ///   quando nenhum patrimônio corresponde; se contém letras, busca
  ///   textual nos campos textuais.
  /// - os demais campos ([numeroSerie], [equipamentoDescricao],
  ///   [marcaModelo], [responsavel], [localizacao]) usam `ilike` no(s)
  ///   campo(s) correspondente(s).
  ///
  /// [localizacaoId] filtra por `localizacao_atual_id` exato (nunca texto).
  /// [semLocalizacao] filtra `localizacao_atual_id IS NULL` — mutuamente
  /// exclusivo com [localizacaoId] (a UI nunca envia os dois juntos).
  ///
  /// [marca], [modelo] e [responsavel] usam `ilike` case-insensitive,
  /// independentes do [campoBusca]/[busca] da busca principal — vazio
  /// (após trim) significa "filtro não aplicado".
  ///
  /// [dataCadastroDe]/[dataCadastroAte] e [dataAquisicaoDe]/
  /// [dataAquisicaoAte] filtram por intervalo INCLUSIVO nos dois limites.
  ///
  /// [ordenarPor] `null` (padrão) mantém a ordenação padrão (`data_cadastro`
  /// mais recente primeiro) — qualquer outro valor substitui totalmente essa
  /// ordenação, sempre resolvida no SERVIDOR antes de [limit]/[offset]
  /// (nunca ordenar só a página já paginada). [ordenacaoDirecao] só importa
  /// quando [ordenarPor] não é `null`.
  ///
  /// [PatrimonioOrdenacaoCampo.numeroPatrimonio] ordena pelo valor de TEXTO
  /// armazenado (`numero_patrimonio` é `text`, nunca `integer` — ver
  /// docs/database.md): "10" vem antes de "2" alfabeticamente. Isso é uma
  /// limitação conhecida, não um bug — ver nota em
  /// PatrimonioRepositorySupabase._colunaDeOrdenacao.
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
    PatrimonioOrdenacaoCampo? ordenarPor,
    OrdenacaoDirecao ordenacaoDirecao = OrdenacaoDirecao.asc,
  });

  /// Cadastra um patrimônio novo e sua movimentação inicial (ENTRADA) via
  /// a função `cadastrar_patrimonio` no Postgres, atomicamente. O
  /// responsável atual passa a ser [responsavelDestino].
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  });

  /// Cadastra um patrimônio novo dentro de uma IMPORTAÇÃO EM LOTE, via
  /// `cadastrar_patrimonio_lote` — os mesmos efeitos de [cadastrar]
  /// (cadastro + movimentação inicial ENTRADA, atomicamente), mais
  /// [operacaoId] (idempotência: reenviar a MESMA chamada após um resultado
  /// de rede desconhecido é seguro — nunca cadastra duas vezes; ver
  /// [ResultadoCadastroLote.jaExecutado]), [loteId] (agrupa todas as linhas
  /// de uma mesma rodada de confirmação da importação) e
  /// [origemArquivo]/[origemLinha] (rastreabilidade: de qual arquivo/linha
  /// da planilha este patrimônio veio). [operacaoId] deve ser gerado UMA
  /// única vez por linha e reenviado IDÊNTICO em qualquer retry — nunca
  /// recriado.
  Future<ResultadoCadastroLote> cadastrarLote({
    required String tipoId,
    required String destinoId,
    required String operacaoId,
    required String loteId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
    String? origemArquivo,
    int? origemLinha,
  });

  /// Atualiza somente metadados (nunca status/setor/responsável — esses só
  /// mudam por movimentação registrada, ver docs/database.md).
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  });

  /// Busca, em uma única consulta, os patrimônios cujo `numero_patrimonio`
  /// (já normalizado) esteja em [numeros] — usado pela importação de
  /// planilha para detectar existentes sem uma consulta por linha (nunca
  /// N+1).
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(
    List<String> numeros,
  );

  /// Entre [numerosSerie], devolve os que já pertencem a algum patrimônio
  /// cadastrado — usado para o aviso de possível duplicidade por número de
  /// série (não é `unique` no banco, então nunca bloqueia, só avisa).
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie);

  /// aplica UMA decisão de comparação (um patrimônio) via
  /// `aplicar_decisao_comparacao_patrimonio`, dentro de uma única transação
  /// no servidor: metadados por UPDATE direto, setor/localização sempre por
  /// `registrar_movimentacao` (nunca um atalho). Idempotente por
  /// [DecisaoItemParaExecutar.operacaoId] — reenviar a MESMA [decisao] após
  /// um resultado de rede desconhecido é seguro (ver
  /// [ResultadoAplicacaoDecisao.jaExecutado]).
  ///
  /// Uma [ComparacaoExecucaoFalhouException] significa RECUSA síncrona do
  /// servidor: a transação foi desfeita, nada foi escrito por esta chamada.
  /// Qualquer OUTRA exceção (rede/timeout) tem resultado DESCONHECIDO —
  /// quem chama precisa preservar [decisao] (nunca gerar uma nova) para um
  /// retry ou uma reconciliação posterior via
  /// [buscarExecucaoComparacaoPorOperacaoId].
  Future<ResultadoAplicacaoDecisao> aplicarDecisaoComparacao(
    DecisaoItemParaExecutar decisao,
  );

  /// Consulta somente-leitura de `patrimonio_comparacao_execucoes` pelo
  /// `operacao_id` — usada para reconciliar um resultado desconhecido sem
  /// nenhuma nova escrita. `null` quando nada foi encontrado (o que NÃO
  /// prova que a operação não foi aplicada — pode não ter comitado ainda).
  Future<ResultadoAplicacaoDecisao?> buscarExecucaoComparacaoPorOperacaoId(
    String operacaoId,
  );

  /// Busca patrimônios pelo TOMBAMENTO ANTERIOR, validado e persistido em
  /// `patrimonio_tombamentos_historico` (migration 3A.4) — cobre tanto
  /// tombamentos anteriores do relatório oficial já validados e
  /// importados quanto qualquer alteração de tombamento feita dentro do
  /// próprio InvTec ([PatrimonioEncontradoPorAnterior.origem] distingue os
  /// casos). [termo] é comparado pela MESMA regra de equivalência de zeros
  /// à esquerda usada em todo o projeto (ver
  /// `normalizarTombamentoParaComparacao`) — sempre correspondência EXATA
  /// da chave normalizada, nunca parcial/substring.
  ///
  /// Devolve TODOS os patrimônios encontrados — nunca escolhe um
  /// automaticamente quando mais de um bem compartilha o mesmo tombamento
  /// anterior (ambiguidade é responsabilidade de quem exibe o resultado,
  /// nunca resolvida aqui).
  ///
  /// Lista SEMPRE vazia enquanto [historicoTombamentosDisponivel] for
  /// `false` — nunca lança por a tabela ainda não existir em produção.
  Future<List<PatrimonioEncontradoPorAnterior>> buscarPorTombamentoAnterior(
    String termo,
  );

  /// Histórico COMPLETO de trocas de tombamento de UM patrimônio
  /// ([patrimonioId]), para a seção "Histórico de tombamentos" da tela de
  /// detalhe — nunca filtrado por chave de busca (diferente de
  /// [buscarPorTombamentoAnterior]). Ordenado por `sequencia` DESC (evento
  /// mais recente primeiro — mesma convenção de
  /// `MovimentacaoRepository.listarHistoricoPorPatrimonio`), nunca por
  /// `registrado_em` isolado (pode empatar dentro de uma mesma transação).
  ///
  /// Valores de tombamento preservados BRUTOS (zeros à esquerda intactos).
  /// Lista vazia tanto quando o patrimônio nunca trocou de número quanto
  /// quando a tabela ainda não existe (migration 3A.4 não aplicada) —
  /// nunca lança por isso, mesma defesa de [buscarPorTombamentoAnterior].
  /// RLS de `patrimonio_tombamentos_historico` já exige `patrimonio.view`
  /// — a mesma permissão que já controla a visibilidade do patrimônio em
  /// si, então nenhum gate adicional é necessário no cliente.
  Future<List<TombamentoHistoricoItem>> buscarHistoricoTombamentosPorId(
    String patrimonioId,
  );

  /// Aplica UMA retificação cadastral de unidade (um patrimônio) via
  /// `retificar_unidade_patrimonio`, dentro de uma única transação no
  /// servidor: valida tombamento/versão esperados contra o estado REAL e
  /// delega a mudança de setor a `registrar_movimentacao`
  /// (`RETIFICACAO_CADASTRAL`) — nunca um UPDATE direto. Idempotente por
  /// [ItemRetificacaoParaExecutar.operacaoId] — mesma semântica de
  /// [aplicarDecisaoComparacao]: reenviar o MESMO [item] após um resultado
  /// de rede desconhecido é seguro.
  ///
  /// Uma [RetificacaoExecucaoFalhouException] significa recusa síncrona do
  /// servidor (nada foi escrito). Qualquer OUTRA exceção tem resultado
  /// DESCONHECIDO — quem chama precisa preservar [item] para um retry.
  Future<ResultadoRetificacaoUnidade> retificarUnidadePatrimonio(
    ItemRetificacaoParaExecutar item,
  );
}
