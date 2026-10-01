import '../../domain/movimentacao.dart';
import 'sei_documento_situacao.dart';
import 'sei_item_pendencia_status.dart';
import 'sei_item_pendente.dart';

/// O que o assistente de importação envia para persistir quando o usuário
/// escolhe "Salvar como pendência" — ainda sem id: o repositório é quem
/// cria o registro e devolve o [SeiDocumentoPendente] completo. Importar e
/// salvar um despacho SEMPRE cria uma solicitação PENDENTE; nunca altera um
/// patrimônio.
class SeiDocumentoPendenteRascunho {
  const SeiDocumentoPendenteRascunho({
    this.numeroDocumentoSei,
    this.numeroProcesso,
    this.numeroDocumentoFormatado,
    this.assunto,
    required this.tipoOperacaoPretendida,
    required this.nomeArquivo,
    required this.hashSha256,
    required this.itens,
  });

  final String? numeroDocumentoSei;
  final String? numeroProcesso;
  final String? numeroDocumentoFormatado;
  final String? assunto;
  final MovimentacaoTipo tipoOperacaoPretendida;
  final String nomeArquivo;
  final String hashSha256;
  final List<SeiItemPendenteRascunho> itens;
}

/// Documento SEI persistido como pendência — SEPARADO do histórico de
/// `movimentacoes`: nenhum item aqui altera um patrimônio só por existir.
/// A conclusão de um item é que registra a movimentação efetiva e a
/// vincula ao item (`SeiItemPendente.movimentacaoId`).
class SeiDocumentoPendente {
  factory SeiDocumentoPendente.fromJson(Map<String, dynamic> json) {
    final autor = json['autor'] as Map<String, dynamic>?;
    // `documentos_sei_repository_supabase.dart` tem duas consultas: `obterPorId`
    // (detalhe) busca a tabela base com embed `itens:documentos_sei_itens(...)`
    // — a chave "itens" existe no JSON. `listar` busca a VIEW
    // `documentos_sei_com_situacao`, que já manda os totais prontos mas nunca
    // embeda os itens. `containsKey('itens')` distingue as duas: com a chave
    // presente, os itens são a fonte de verdade; sem ela, os totais/situação
    // vêm direto da view.
    final temItensEmbed = json.containsKey('itens');
    final itensJson = json['itens'] as List<dynamic>?;
    final itens = (itensJson ?? const []).cast<Map<String, dynamic>>().map(SeiItemPendente.fromJson).toList()
      ..sort((a, b) => a.linha.compareTo(b.linha));

    final totais = temItensEmbed
        ? _TotaisDocumento.deItens(itens)
        : _TotaisDocumento(
            totalItens: (json['total_itens'] as num).toInt(),
            totalPendentes: (json['total_pendentes'] as num).toInt(),
            totalConcluidos: (json['total_concluidos'] as num).toInt(),
            totalCancelados: (json['total_cancelados'] as num).toInt(),
            situacao: situacaoDocumentoFromValue(json['situacao'] as String),
          );

    return SeiDocumentoPendente(
      id: json['id'] as String,
      numeroDocumentoSei: json['numero_documento_sei'] as String?,
      numeroProcesso: json['numero_processo'] as String?,
      numeroDocumentoFormatado: json['numero_documento_formatado'] as String?,
      assunto: json['assunto'] as String?,
      tipoOperacaoPretendida: MovimentacaoTipo.fromValue(json['tipo_operacao_pretendida'] as String),
      nomeArquivo: json['nome_arquivo'] as String,
      hashSha256: json['hash_sha256'] as String,
      versao: json['versao'] as int,
      criadoEm: DateTime.parse(json['criado_em'] as String),
      criadoPorId: json['criado_por'] as String,
      // profiles_select só deixa ADMIN/GESTOR verem o nome de outro usuário
      // (mesma ressalva de `MovimentacaoListagemItem.autorExibido`) — um
      // embed ausente aqui é a RLS ocultando, nunca falta de dado.
      criadoPorNome: autor?['nome'] as String? ?? 'Não disponível',
      atualizadoEm: json['atualizado_em'] == null ? null : DateTime.parse(json['atualizado_em'] as String),
      itens: itens,
      totalItens: totais.totalItens,
      totalPendentes: totais.totalPendentes,
      totalConcluidos: totais.totalConcluidos,
      totalCancelados: totais.totalCancelados,
      situacao: totais.situacao,
    );
  }

  const SeiDocumentoPendente({
    required this.id,
    this.numeroDocumentoSei,
    this.numeroProcesso,
    this.numeroDocumentoFormatado,
    this.assunto,
    required this.tipoOperacaoPretendida,
    required this.nomeArquivo,
    required this.hashSha256,
    required this.versao,
    required this.criadoEm,
    required this.criadoPorId,
    required this.criadoPorNome,
    this.atualizadoEm,
    this.itens = const [],
    required this.totalItens,
    required this.totalPendentes,
    required this.totalConcluidos,
    required this.totalCancelados,
    required this.situacao,
  });

  /// Constrói a partir de [itens] JÁ CARREGADOS, computando totais/situação
  /// automaticamente (mesma lógica de [fromJson] com o embed de itens
  /// presente) — para quem monta um [SeiDocumentoPendente] diretamente em
  /// memória (dublês de teste) em vez de a partir do JSON do Supabase,
  /// sem duplicar a computação em cada chamador.
  factory SeiDocumentoPendente.fromItens({
    required String id,
    String? numeroDocumentoSei,
    String? numeroProcesso,
    String? numeroDocumentoFormatado,
    String? assunto,
    required MovimentacaoTipo tipoOperacaoPretendida,
    required String nomeArquivo,
    required String hashSha256,
    required int versao,
    required DateTime criadoEm,
    required String criadoPorId,
    required String criadoPorNome,
    DateTime? atualizadoEm,
    List<SeiItemPendente> itens = const [],
  }) {
    final totais = _TotaisDocumento.deItens(itens);
    return SeiDocumentoPendente(
      id: id,
      numeroDocumentoSei: numeroDocumentoSei,
      numeroProcesso: numeroProcesso,
      numeroDocumentoFormatado: numeroDocumentoFormatado,
      assunto: assunto,
      tipoOperacaoPretendida: tipoOperacaoPretendida,
      nomeArquivo: nomeArquivo,
      hashSha256: hashSha256,
      versao: versao,
      criadoEm: criadoEm,
      criadoPorId: criadoPorId,
      criadoPorNome: criadoPorNome,
      atualizadoEm: atualizadoEm,
      itens: itens,
      totalItens: totais.totalItens,
      totalPendentes: totais.totalPendentes,
      totalConcluidos: totais.totalConcluidos,
      totalCancelados: totais.totalCancelados,
      situacao: totais.situacao,
    );
  }

  final String id;
  final String? numeroDocumentoSei;
  final String? numeroProcesso;
  final String? numeroDocumentoFormatado;
  final String? assunto;
  final MovimentacaoTipo tipoOperacaoPretendida;
  final String nomeArquivo;

  /// Guardado só como metadado: NUNCA usado sozinho como identidade do
  /// documento nem como chave de deduplicação — o mesmo despacho pode ser
  /// reexportado do SEI com bytes diferentes.
  final String hashSha256;

  /// Controle de concorrência otimista — toda edição exige o cliente
  /// enviar a [versao] que ele leu; a base rejeita quando ela não bate mais
  /// com a atual (outra sessão editou/concluiu/cancelou entre a leitura e a
  /// tentativa de escrita).
  final int versao;

  final DateTime criadoEm;
  final String criadoPorId;
  final String criadoPorNome;
  final DateTime? atualizadoEm;

  final List<SeiItemPendente> itens;

  /// Situação e totais são campos definidos em [fromJson]/[copyWith] (nunca
  /// getters calculados de [itens]): numa linha de listagem [itens] vem
  /// vazio e a view já manda os totais prontos.
  final SeiDocumentoSituacao situacao;
  final int totalItens;
  final int totalPendentes;
  final int totalConcluidos;
  final int totalCancelados;

  /// REGRA DEFINITIVA: o documento inteiro (dados principais e itens) só
  /// pode ser editado enquanto nenhum item estiver concluído. Depois da
  /// primeira conclusão, editar fica bloqueado — cancelar/concluir itens
  /// PENDENTES continua possível, mas isso nunca reabre a edição dos dados
  /// originais.
  bool get podeSerEditado => itens.every((i) => i.status != SeiItemPendenciaStatus.concluido);

  /// documento ENCERRADO: nenhum item PENDENTE (todos
  /// concluídos e/ou cancelados). Não há mais nada a corrigir, concluir ou
  /// cancelar: fica só consulta e histórico. Usa os totais do documento (a
  /// listagem da view não traz `itens`).
  bool get encerrado => totalPendentes == 0;

  /// Edição operacional permitida: nenhum item concluído ([podeSerEditado])
  /// E ainda há item pendente (documento não encerrado).
  bool get permiteEdicao => podeSerEditado && !encerrado;

  SeiDocumentoPendente copyWith({int? versao, DateTime? atualizadoEm, List<SeiItemPendente>? itens}) {
    // Sempre recalculado a partir dos itens (nunca copiado de `this`) —
    // só faz sentido quando [itens] está carregado.
    final totais = _TotaisDocumento.deItens(itens ?? this.itens);
    return SeiDocumentoPendente(
      id: id,
      numeroDocumentoSei: numeroDocumentoSei,
      numeroProcesso: numeroProcesso,
      numeroDocumentoFormatado: numeroDocumentoFormatado,
      assunto: assunto,
      tipoOperacaoPretendida: tipoOperacaoPretendida,
      nomeArquivo: nomeArquivo,
      hashSha256: hashSha256,
      versao: versao ?? this.versao,
      criadoEm: criadoEm,
      criadoPorId: criadoPorId,
      criadoPorNome: criadoPorNome,
      atualizadoEm: atualizadoEm ?? this.atualizadoEm,
      itens: itens ?? this.itens,
      totalItens: totais.totalItens,
      totalPendentes: totais.totalPendentes,
      totalConcluidos: totais.totalConcluidos,
      totalCancelados: totais.totalCancelados,
      situacao: totais.situacao,
    );
  }
}

/// Agrupa os 4 totais + situação para não espalhar a mesma computação em
/// dois lugares ([SeiDocumentoPendente.fromJson] e `.copyWith`).
class _TotaisDocumento {
  const _TotaisDocumento({
    required this.totalItens,
    required this.totalPendentes,
    required this.totalConcluidos,
    required this.totalCancelados,
    required this.situacao,
  });

  factory _TotaisDocumento.deItens(List<SeiItemPendente> itens) {
    return _TotaisDocumento(
      totalItens: itens.length,
      totalPendentes: itens.where((i) => i.status == SeiItemPendenciaStatus.pendente).length,
      totalConcluidos: itens.where((i) => i.status == SeiItemPendenciaStatus.concluido).length,
      totalCancelados: itens.where((i) => i.status == SeiItemPendenciaStatus.cancelado).length,
      situacao: calcularSituacaoDocumento(itens.map((i) => i.status).toList()),
    );
  }

  final int totalItens;
  final int totalPendentes;
  final int totalConcluidos;
  final int totalCancelados;
  final SeiDocumentoSituacao situacao;
}
