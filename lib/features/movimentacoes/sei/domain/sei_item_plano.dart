import '../../../patrimonios/domain/patrimonio.dart';
import '../../domain/movimentacao.dart';
import 'sei_duplicidade.dart';

/// Uma linha do plano de execução em memória — somente leitura: nada neste
/// arquivo, nem em quem o consome, chama `registrarMovimentacao`. É a
/// "prévia" do que uma futura confirmação enviaria à RPC, para revisão
/// humana antes de qualquer escrita existir.
class SeiItemPlano {
  const SeiItemPlano({
    required this.linha,
    required this.numeroPatrimonio,
    required this.patrimonioId,
    required this.tipo,
    required this.origemAtualId,
    required this.origemAtualNome,
    this.destinoId,
    this.destinoNome,
    this.localizacaoDestinoId,
    this.localizacaoDestinoNome,
    this.responsavelDestino,
    this.motivo,
    this.observacao,
    required this.numeroDocumentoSei,
    this.numeroChamado,
    required this.statusEsperadoAposOperacao,
    required this.avisoConfirmado,
    required this.duplicidade,
    this.pendenciasDecisao = const [],
  });

  final int linha;
  final String numeroPatrimonio;
  final String patrimonioId;
  final MovimentacaoTipo tipo;

  final String origemAtualId;
  final String origemAtualNome;

  /// `null` quando o destino do documento não foi encontrado no InvTec —
  /// um item assim nunca deveria chegar até aqui selecionável (ver
  /// `construirPlanoExecucao`), mas o campo fica nulo em vez de inventado
  /// caso chegue de qualquer forma.
  final String? destinoId;
  final String? destinoNome;

  /// `null` aqui significa "não informado no documento" — NUNCA é
  /// silenciosamente traduzido em "preservar" ou "limpar". Ver
  /// [pendenciasDecisao]: a RPC real de TRANSFERENCIA usa o valor
  /// exatamente como enviado (não preserva o atual quando omitido), então
  /// "não informado" exige uma decisão explícita antes de qualquer
  /// execução futura.
  final String? localizacaoDestinoId;
  final String? localizacaoDestinoNome;
  final String? responsavelDestino;

  final String? motivo;
  final String? observacao;
  final String numeroDocumentoSei;
  final String? numeroChamado;

  /// Status que o patrimônio teria após a operação, pela regra real da RPC
  /// (para TRANSFERENCIA: responsável de destino preenchido -> EM_USO,
  /// vazio -> DISPONIVEL) — só informativo nesta versão, nunca escrito.
  final PatrimonioStatus statusEsperadoAposOperacao;

  final bool avisoConfirmado;
  final SeiDuplicidadeResultado duplicidade;

  /// Avisos explícitos de decisão pendente — ex.: "localização de destino
  /// não informada no documento; a RPC não preserva o valor atual quando
  /// este campo é omitido". Uma lista vazia não significa "tudo certo para
  /// executar": só que não há pendência DESTE tipo específico.
  final List<String> pendenciasDecisao;
}
