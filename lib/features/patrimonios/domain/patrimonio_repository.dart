import '../../../core/domain/ordenacao_direcao.dart';
import '../importacao/domain/comparacao_execucao.dart';
import 'patrimonio.dart';
import 'patrimonio_detalhe.dart';
import 'patrimonio_ordenacao.dart';
import 'patrimonio_search_field.dart';
import 'patrimonios_resultado.dart';

abstract class PatrimonioRepository {
  Future<Patrimonio?> buscarPorId(String id);

  /// Detalhe com tipo/setor (e, quando a RLS permitir, quem cadastrou) já
  /// resolvidos — usado na tela de detalhe.
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id);

  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio);

  /// Página de patrimônios com tipo/setor já resolvidos (embed, sem N+1).
  /// [tipoId], [status], [setorId], [localizacaoId]/[semLocalizacao],
  /// [marca], [modelo], [responsavel] e os intervalos de data são filtros
  /// opcionais, todos combináveis entre si e com a busca por AND. Sempre
  /// resolvidos no servidor: nunca carrega a página inteira para
  /// filtrar/paginar em memória.
  ///
  /// [busca] é interpretado de acordo com [campoBusca]:
  /// - [PatrimonioSearchField.patrimonio]: correspondência EXATA contra
  ///   `numero_patrimonio` (nunca `ilike`/substring/similaridade — um
  ///   número de patrimônio incorreto não pode aparecer como se fosse o
  ///   patrimônio pesquisado).
  /// - [PatrimonioSearchField.tudo] (padrão): se [busca] contém só dígitos,
  ///   trata como identificador — `numero_patrimonio` OU `numero_serie`
  ///   EXATOS, nunca fuzzy/"número mais próximo"; se contém letras, busca
  ///   textual nos campos textuais (mantendo `numero_patrimonio` exato
  ///   quando aplicável).
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
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros);

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
  Future<ResultadoAplicacaoDecisao> aplicarDecisaoComparacao(DecisaoItemParaExecutar decisao);

  /// Consulta somente-leitura de `patrimonio_comparacao_execucoes` pelo
  /// `operacao_id` — usada para reconciliar um resultado desconhecido sem
  /// nenhuma nova escrita. `null` quando nada foi encontrado (o que NÃO
  /// prova que a operação não foi aplicada — pode não ter comitado ainda).
  Future<ResultadoAplicacaoDecisao?> buscarExecucaoComparacaoPorOperacaoId(String operacaoId);
}
