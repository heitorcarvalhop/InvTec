import '../../../../core/errors/app_exception.dart';
import 'retificacao_comparacao.dart';

/// Nome da RPC — usado no texto técnico e no log (mesmo papel de
/// `operacaoAplicarDecisaoComparacao` em `comparacao_execucao.dart`).
const operacaoRetificarUnidade = 'retificar_unidade_patrimonio';

/// Mesma lista de `ehFalhaDeTransporte` em `comparacao_execucao.dart` —
/// códigos que o pacote `postgrest` usa quando a resposta NÃO veio do
/// PostgreSQL de verdade (proxy/gateway 502/503/504, 500, timeout 408).
/// Tratar qualquer um destes como recusa DEFINITIVA seria um erro: o
/// resultado real pode já ter sido aplicado no servidor sem o cliente
/// saber — por isso nunca envolvido em [RetificacaoExecucaoFalhouException].
bool ehFalhaDeTransporteRetificacao(String? codigo) =>
    const {'500', '502', '503', '504', '408'}.contains(codigo);

/// Mensagem COMPREENSÍVEL para o usuário de um erro de
/// [operacaoRetificarUnidade]. Códigos definidos pela própria RPC (ver
/// migration `20261022140000_add_retificacao_cadastral_unidade.sql`,
/// seção 6):
///  * `P0040` conflito de versão (snapshot desatualizado);
///  * `P0041` `operacao_id` reaproveitado com parâmetros/usuário diferentes;
///  * `P0042` pendência SEI aberta;
///  * `P0044` tombamento divergente do plano exportado;
///  * `P0045` destino igual à unidade atual;
///  * `P0046` unidade ATUAL divergente do plano exportado (checagem
///    explícita, independente do conflito genérico de versão em `P0040`);
/// mais os já conhecidos `42501`, `P0001`, `P0002`.
String mensagemErroRetificacao({required String? codigo, required String mensagemDoServidor}) {
  if (ehFalhaDeTransporteRetificacao(codigo)) {
    return 'Não foi possível confirmar se esta retificação chegou a ser aplicada (falha de conexão/tempo '
        'limite). Nada foi presumido: consulte o resultado ou tente novamente — a operação é segura para repetir.';
  }
  switch (codigo) {
    case '42501':
      return 'Você não tem permissão para executar retificações de unidade.';
    case 'P0002':
      return 'Patrimônio não encontrado. Atualize a comparação e revise novamente.';
    case 'P0040':
      return 'Este patrimônio foi alterado por outra operação desde que o plano foi exportado. '
          'Nada foi gravado — refaça a comparação para este patrimônio antes de aplicar.';
    case 'P0041':
      return 'Esta operação já havia sido registrada antes com parâmetros diferentes. '
          'Não repita automaticamente: revise este item antes de tentar de novo.';
    case 'P0042':
      return 'Este patrimônio possui uma pendência SEI em aberto — resolva ou cancele o item SEI antes de '
          'retificar a unidade por aqui.';
    case 'P0044':
      return 'O tombamento deste patrimônio não corresponde mais ao plano exportado. '
          'Nada foi gravado — revise este item individualmente.';
    case 'P0045':
      return 'Este patrimônio já pertence à unidade de destino informada.';
    case 'P0046':
      return 'A unidade atual deste patrimônio não corresponde mais ao plano exportado. '
          'Nada foi gravado — revise este item individualmente.';
    default:
      return 'Não foi possível aplicar esta retificação. Nada foi gravado. '
          'Veja os detalhes técnicos para mais informações.';
  }
}

/// Mesma forma de `ComparacaoExecucaoFalhouException`: a RPC RECUSOU de
/// forma síncrona — a transação foi desfeita, NADA foi escrito por esta
/// chamada. Qualquer OUTRA exceção (rede/timeout) nunca vira este tipo.
class RetificacaoExecucaoFalhouException extends AppException {
  const RetificacaoExecucaoFalhouException({
    required String mensagem,
    this.codigo,
    this.detalhes,
    this.dica,
    super.cause,
  }) : super(mensagem);

  final String? codigo;
  final String? detalhes;
  final String? dica;

  String get textoTecnico {
    final linhas = <String>[
      'Operação: $operacaoRetificarUnidade',
      if (codigo != null && codigo!.isNotEmpty) 'Código: $codigo',
      if (message.isNotEmpty) 'Mensagem: $message',
      if (detalhes != null && detalhes!.isNotEmpty) 'Detalhes: $detalhes',
      if (dica != null && dica!.isNotEmpty) 'Dica: $dica',
    ];
    return linhas.join('\n');
  }

  @override
  String toString() => 'RetificacaoExecucaoFalhouException(código: $codigo): $message';
}

RetificacaoExecucaoFalhouException falhaDeExecucaoRetificacao({
  required String? codigo,
  required String mensagemDoServidor,
  String? detalhes,
  String? dica,
  Object? cause,
}) {
  return RetificacaoExecucaoFalhouException(
    mensagem: mensagemErroRetificacao(codigo: codigo, mensagemDoServidor: mensagemDoServidor),
    codigo: codigo,
    detalhes: detalhes,
    dica: dica,
    cause: cause,
  );
}

/// Resultado de UMA chamada bem-sucedida (nova execução OU retry idêntico
/// já registrado — ver [jaExecutado]) de [operacaoRetificarUnidade].
class ResultadoRetificacaoUnidade {
  const ResultadoRetificacaoUnidade({
    required this.patrimonioId,
    required this.setorOrigemId,
    required this.setorDestinoId,
    required this.jaExecutado,
    this.movimentacaoId,
    this.concluidoEm,
  });

  factory ResultadoRetificacaoUnidade.fromJson(Map<String, dynamic> json) {
    return ResultadoRetificacaoUnidade(
      patrimonioId: json['patrimonio_id'] as String,
      setorOrigemId: json['setor_origem_id'] as String,
      setorDestinoId: json['setor_destino_id'] as String,
      jaExecutado: json['ja_executado'] as bool? ?? false,
      movimentacaoId: json['movimentacao_id'] as String?,
      concluidoEm: json['concluido_em'] == null ? null : DateTime.parse(json['concluido_em'] as String),
    );
  }

  final String patrimonioId;
  final String setorOrigemId;
  final String setorDestinoId;

  /// `true` quando esta chamada não escreveu nada de novo — a RPC
  /// encontrou uma execução anterior com o mesmo `operacao_id` e devolveu
  /// o resultado já gravado (retry seguro após um resultado desconhecido).
  final bool jaExecutado;
  final String? movimentacaoId;
  final DateTime? concluidoEm;
}

/// A decisão de UM patrimônio, CONGELADA no momento da confirmação — mesmo
/// espírito de `DecisaoItemParaExecutar` (importação): [operacaoId] é
/// gerado UMA ÚNICA VEZ e nunca recriado, mesmo num retry.
class ItemRetificacaoParaExecutar {
  const ItemRetificacaoParaExecutar({
    required this.operacaoId,
    required this.loteId,
    required this.patrimonioId,
    required this.tombamentoEsperado,
    required this.versaoEsperada,
    required this.setorOrigemEsperadoId,
    required this.setorDestinoId,
    required this.justificativa,
    this.localizacaoDestinoId,
    this.numeroPatrimonioExibicao,
    this.setorDestinoNomeExibicao,
  });

  final String operacaoId;
  final String loteId;
  final String patrimonioId;
  final String tombamentoEsperado;
  final DateTime versaoEsperada;

  /// Unidade ATUAL esperada (snapshot do CSV) — validada explicitamente
  /// pela RPC (`p_setor_origem_esperado`, errcode `P0046`), nunca só
  /// implicitamente via [versaoEsperada]. Ver comentário da migration
  /// `retificar_unidade_patrimonio` sobre por que isso é uma checagem
  /// própria.
  final String setorOrigemEsperadoId;
  final String setorDestinoId;
  final String justificativa;
  final String? localizacaoDestinoId;

  /// Só para exibição (progresso, relatório final) — nunca enviados à RPC.
  final String? numeroPatrimonioExibicao;
  final String? setorDestinoNomeExibicao;
}

/// Traduz um [RetificacaoLote] + a justificativa única da campanha (ver
/// migration: sempre obrigatória, nunca opcional) na lista CONGELADA de
/// itens prontos para execução — um por patrimônio, só a partir de
/// [RetificacaoLote.itensProntos] ([ClassificacaoRetificacao.
/// jaNaUnidadeCorreta] e qualquer bloqueio nunca entram aqui).
List<ItemRetificacaoParaExecutar> construirItensRetificacaoParaExecucao({
  required RetificacaoLote lote,
  required String loteId,
  required String justificativa,
  required String Function() gerarOperacaoId,
}) {
  final itens = <ItemRetificacaoParaExecutar>[];

  for (final item in lote.itensProntos) {
    final detalhe = item.patrimonioDetalhe;
    final setorOrigemEsperadoId = item.setorAtualRealId;
    final setorDestinoId = item.setorDestinoId;
    if (detalhe == null || setorOrigemEsperadoId == null || setorDestinoId == null) {
      continue; // nunca deveria ocorrer para `pronto`
    }

    itens.add(
      ItemRetificacaoParaExecutar(
        operacaoId: gerarOperacaoId(),
        loteId: loteId,
        patrimonioId: detalhe.patrimonio.id,
        tombamentoEsperado: item.linha.tombamentoAtualInvtec,
        versaoEsperada: detalhe.patrimonio.atualizadoEm,
        setorOrigemEsperadoId: setorOrigemEsperadoId,
        setorDestinoId: setorDestinoId,
        justificativa: justificativa,
        numeroPatrimonioExibicao: detalhe.patrimonio.numeroPatrimonio,
        setorDestinoNomeExibicao: item.setorDestinoNome,
      ),
    );
  }

  return itens;
}
