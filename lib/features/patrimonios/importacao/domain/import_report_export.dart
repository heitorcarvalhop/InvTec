import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'import_row.dart';

/// Uma linha do relatório de uma rodada de importação CONCLUÍDA — gerado a
/// partir de [ImportRow] já processadas (sempre com [ImportRow.resultado]
/// definido; nunca usado para linhas ainda pendentes).
class ImportReportLinha {
  const ImportReportLinha({
    required this.numeroLinha,
    required this.numeroPatrimonio,
    required this.sucesso,
    required this.patrimonioId,
    required this.mensagemErro,
  });

  factory ImportReportLinha.fromImportRow(ImportRow linha) => ImportReportLinha(
    numeroLinha: linha.numeroLinha,
    numeroPatrimonio: linha.numeroPatrimonio,
    sucesso: linha.resultado?.sucesso ?? false,
    patrimonioId: linha.resultado?.patrimonioId,
    mensagemErro: linha.resultado?.mensagemErro,
  );

  final int numeroLinha;
  final String? numeroPatrimonio;
  final bool sucesso;
  final String? patrimonioId;
  final String? mensagemErro;

  Map<String, Object?> toJson() => {
    'numeroLinha': numeroLinha,
    'numeroPatrimonio': numeroPatrimonio,
    'sucesso': sucesso,
    'patrimonioId': patrimonioId,
    'mensagemErro': mensagemErro,
  };

  factory ImportReportLinha.fromJson(Map<String, Object?> json) => ImportReportLinha(
    numeroLinha: json['numeroLinha'] as int,
    numeroPatrimonio: json['numeroPatrimonio'] as String?,
    sucesso: json['sucesso'] as bool,
    patrimonioId: json['patrimonioId'] as String?,
    mensagemErro: json['mensagemErro'] as String?,
  );
}

/// Relatório completo de uma rodada de importação — [loteId] identifica a
/// rodada (ver `PatrimonioImportController.confirmarImportacao`).
class ImportReport {
  const ImportReport({required this.loteId, required this.nomeArquivo, required this.linhas});

  factory ImportReport.fromImportRows({
    required String loteId,
    required String? nomeArquivo,
    required List<ImportRow> linhas,
  }) => ImportReport(
    loteId: loteId,
    nomeArquivo: nomeArquivo,
    linhas: linhas.map(ImportReportLinha.fromImportRow).toList(),
  );

  final String loteId;
  final String? nomeArquivo;
  final List<ImportReportLinha> linhas;

  Map<String, Object?> toJson() => {
    'loteId': loteId,
    'nomeArquivo': nomeArquivo,
    'linhas': linhas.map((l) => l.toJson()).toList(),
  };

  factory ImportReport.fromJson(Map<String, Object?> json) => ImportReport(
    loteId: json['loteId'] as String,
    nomeArquivo: json['nomeArquivo'] as String?,
    linhas: (json['linhas'] as List<Object?>)
        .map((l) => ImportReportLinha.fromJson(l as Map<String, Object?>))
        .toList(),
  );
}

/// Colunas (nesta ordem, sempre) do CSV gerado por [gerarCsvRelatorioImportacao].
const colunasRelatorioImportacao = ['Linha', 'Número de patrimônio', 'Status', 'Id gerado', 'Mensagem de erro'];

/// Gera os bytes (UTF-8) de um CSV do relatório de uma rodada de
/// importação já concluída — função pura, sem nenhuma dependência de
/// rede/arquivo: [linhas] já vem pronto (ver [ImportReport]/
/// [ImportReportLinha.fromImportRow]). Determinístico: a mesma entrada
/// sempre produz a mesma saída, byte a byte.
Uint8List gerarCsvRelatorioImportacao(List<ImportReportLinha> linhas) {
  final registros = [
    colunasRelatorioImportacao,
    for (final linha in linhas)
      [
        linha.numeroLinha,
        linha.numeroPatrimonio ?? '',
        linha.sucesso ? 'Sucesso' : 'Erro',
        linha.patrimonioId ?? '',
        linha.mensagemErro ?? '',
      ],
  ];
  final texto = csv.encode(registros);
  return Uint8List.fromList(utf8.encode(texto));
}

String _nomeArquivoRelatorio(String loteId) => 'import_relatorio_$loteId.json';

/// Persistência local (arquivo JSON próprio — ver docstring de
/// `ImportLotePersistencia` sobre a decisão de trocar `shared_preferences`
/// por `path_provider`/`package:file` para dados de importação em escala)
/// de um [ImportReport] já gerado — sobrevive a sair da tela de importação,
/// mesmo sem o usuário ter exportado o CSV na hora.
///
/// AUDITORIA DE SEGURANÇA: [ImportReport]/[ImportReportLinha] carregam só
/// `loteId`/número de linha/número de patrimônio/status/id do patrimônio
/// gerado/mensagem de erro de NEGÓCIO — nunca um token de sessão, senha ou
/// chave de API. Confirmado nesta revisão.
///
/// [FileSystem] é injetável só para teste (`MemoryFileSystem`) — produção
/// sempre usa [LocalFileSystem] (padrão).
class ImportReportPersistencia {
  ImportReportPersistencia(this._diretorio, {FileSystem? fileSystem}) : _fs = fileSystem ?? const LocalFileSystem();

  final String _diretorio;
  final FileSystem _fs;

  File _arquivo(String loteId) => _fs.file(_fs.path.join(_diretorio, _nomeArquivoRelatorio(loteId)));

  Future<void> salvar(ImportReport relatorio) async {
    final arquivo = _arquivo(relatorio.loteId);
    await arquivo.parent.create(recursive: true);
    await arquivo.writeAsString(jsonEncode(relatorio.toJson()));
  }

  /// `null` quando não há relatório salvo para [loteId] — nunca lança por
  /// dado corrompido/arquivo ausente, trata como ausente.
  ImportReport? carregar(String loteId) {
    try {
      final arquivo = _arquivo(loteId);
      if (!arquivo.existsSync()) return null;
      final bruto = arquivo.readAsStringSync();
      return ImportReport.fromJson(jsonDecode(bruto) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> limpar(String loteId) async {
    final arquivo = _arquivo(loteId);
    if (await arquivo.exists()) await arquivo.delete();
  }
}
