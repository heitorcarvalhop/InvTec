import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';

/// Status mínimo de UMA linha já processada (ou ainda pendente) de uma
/// rodada de importação — só o necessário para decidir, ao retomar, se a
/// linha já tem um resultado definitivo ou ainda precisa ser (re)enviada.
/// Nunca os dados completos da linha (tipo/destino/etc.): esses só existem
/// de verdade depois que o usuário reabre o MESMO arquivo e reanalisa.
enum ImportLoteLinhaPersistidaStatus { pendente, sucesso, falha }

class ImportLoteLinhaPersistida {
  const ImportLoteLinhaPersistida({
    required this.numeroLinha,
    required this.operacaoId,
    required this.status,
  });

  final int numeroLinha;
  final String operacaoId;
  final ImportLoteLinhaPersistidaStatus status;

  Map<String, Object?> toJson() => {
    'numeroLinha': numeroLinha,
    'operacaoId': operacaoId,
    'status': status.name,
  };

  factory ImportLoteLinhaPersistida.fromJson(Map<String, Object?> json) => ImportLoteLinhaPersistida(
    numeroLinha: json['numeroLinha'] as int,
    operacaoId: json['operacaoId'] as String,
    status: ImportLoteLinhaPersistidaStatus.values.byName(json['status'] as String),
  );
}

/// Snapshot mínimo de uma rodada de confirmação de importação (ver
/// `PatrimonioImportController.confirmarImportacao`) — o suficiente para a
/// UI oferecer "retomar" ou "descartar" ao reabrir a tela/controller, nunca
/// usado como fonte de verdade (qualquer retomada revalida contra o
/// servidor antes de continuar).
///
/// AUDITORIA DE SEGURANÇA (obrigatória para qualquer campo novo adicionado
/// aqui): este snapshot NUNCA inclui token de sessão, senha, chave de API
/// nem qualquer segredo — só dados de negócio da própria importação
/// ([loteId]/[usuarioId] são identificadores internos, não credenciais;
/// [nomeArquivo] é o nome do arquivo escolhido pelo usuário, nunca seu
/// conteúdo). Confirmado nesta revisão: nenhum dos campos abaixo, nem os de
/// [ImportLoteLinhaPersistida], carrega algo sensível.
class ImportLoteSessaoPersistida {
  const ImportLoteSessaoPersistida({
    required this.loteId,
    required this.usuarioId,
    required this.nomeArquivo,
    required this.criadoEm,
    required this.linhas,
  });

  final String loteId;
  final String usuarioId;
  final String? nomeArquivo;
  final DateTime criadoEm;
  final List<ImportLoteLinhaPersistida> linhas;

  /// `true` quando NENHUMA linha ficou sem resultado definitivo — uma
  /// sessão completa nunca é oferecida para retomada.
  bool get completo => linhas.every((l) => l.status != ImportLoteLinhaPersistidaStatus.pendente);

  Map<String, Object?> toJson() => {
    'loteId': loteId,
    'usuarioId': usuarioId,
    'nomeArquivo': nomeArquivo,
    'criadoEm': criadoEm.toIso8601String(),
    'linhas': linhas.map((l) => l.toJson()).toList(),
  };

  factory ImportLoteSessaoPersistida.fromJson(Map<String, Object?> json) => ImportLoteSessaoPersistida(
    loteId: json['loteId'] as String,
    usuarioId: json['usuarioId'] as String,
    nomeArquivo: json['nomeArquivo'] as String?,
    criadoEm: DateTime.parse(json['criadoEm'] as String),
    linhas: (json['linhas'] as List<Object?>)
        .map((l) => ImportLoteLinhaPersistida.fromJson(l as Map<String, Object?>))
        .toList(),
  );
}

/// Nome de arquivo (dentro do diretório de dados do app — ver
/// `getApplicationSupportDirectory()` em `PatrimonioImportController`) para
/// a sessão ATUALMENTE pendente de um usuário — só um ponteiro (o
/// `loteId`), nunca o conteúdo da sessão em si (ver [_nomeArquivoSessao]).
String _nomeArquivoAtual(String usuarioId) => 'import_lote_atual_$usuarioId.json';

String _nomeArquivoSessao(String usuarioId, String loteId) => 'import_lote_${usuarioId}_$loteId.json';

/// Persistência local de uma sessão de importação em lote em andamento —
/// sobrevive a sair da tela ou fechar o app (inclusive um reinício completo
/// do processo, já que grava em disco, não em memória).
///
/// Decisão de ARMAZENAMENTO (Fase de persistência em escala): esta sessão
/// pode chegar a MILHARES de linhas (um `operacaoId` de UUID por linha,
/// mais número de linha e status) — um JSON de ~90-100 bytes por linha
/// soma ~1 MB para 10.000 linhas. `shared_preferences` foi avaliado e
/// descartado para este uso específico (ver
/// `import_lote_persistencia_carga_test.dart` e o relatório da tarefa):
/// cada implementação de plataforma (`shared_preferences_windows` incluído
/// — ver `_readFromFile`/`_writePreferences` do pacote) lê e reescreve o
/// arquivo de preferências do app POR COMPLETO a cada `setString`/`remove`
/// — ou seja, persistir esta sessão arrastaria (lenta e
/// desnecessariamente) TODAS as outras preferências do app (tema, barra
/// lateral etc.) a cada gravação, crescendo com o tamanho total de dados
/// não relacionados, nunca só com o tamanho desta sessão. Um arquivo JSON
/// próprio (via `path_provider`, isolado das demais preferências, com
/// leitura/escrita de UM arquivo do tamanho exato desta sessão) é
/// apropriado para este volume sem precisar de um banco relacional:
/// `sqflite` foi considerado e descartado por não ter suporte nativo a
/// Windows sem uma dependência adicional (`sqflite_common_ffi` +
/// `sqlite3_flutter_libs`, nenhuma delas já presente no projeto) para um
/// caso de uso que não precisa de consulta relacional — só salvar/carregar
/// um único blob por usuário. `package:file`/`package:path_provider` já
/// eram dependências TRANSITIVAS resolvidas (via `shared_preferences`),
/// promovidas aqui a diretas — nenhuma dependência nova foi de fato
/// adicionada ao projeto.
///
/// [FileSystem] é injetável só para teste (`MemoryFileSystem`, sem tocar o
/// disco real) — produção sempre usa [LocalFileSystem] (padrão).
class ImportLotePersistencia {
  ImportLotePersistencia(this._diretorio, {FileSystem? fileSystem}) : _fs = fileSystem ?? const LocalFileSystem();

  final String _diretorio;
  final FileSystem _fs;

  File _arquivo(String nome) => _fs.file(_fs.path.join(_diretorio, nome));

  Future<void> salvar(ImportLoteSessaoPersistida sessao) async {
    final arquivo = _arquivo(_nomeArquivoSessao(sessao.usuarioId, sessao.loteId));
    await arquivo.parent.create(recursive: true);
    await arquivo.writeAsString(jsonEncode(sessao.toJson()));
    await _arquivo(_nomeArquivoAtual(sessao.usuarioId)).writeAsString(sessao.loteId);
  }

  /// Sessão pendente mais recente do usuário [usuarioId] — `null` quando
  /// não há nenhuma. Nunca lança por dado corrompido/desatualizado/arquivo
  /// ausente: trata como "nenhuma sessão" (a retomada, de qualquer forma,
  /// sempre revalida do zero contra o servidor).
  ImportLoteSessaoPersistida? carregar(String usuarioId) {
    try {
      final apontador = _arquivo(_nomeArquivoAtual(usuarioId));
      if (!apontador.existsSync()) return null;
      final loteId = apontador.readAsStringSync().trim();
      if (loteId.isEmpty) return null;

      final arquivoSessao = _arquivo(_nomeArquivoSessao(usuarioId, loteId));
      if (!arquivoSessao.existsSync()) return null;
      final bruto = arquivoSessao.readAsStringSync();
      return ImportLoteSessaoPersistida.fromJson(jsonDecode(bruto) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  Future<void> limpar(String usuarioId, String loteId) async {
    final arquivoSessao = _arquivo(_nomeArquivoSessao(usuarioId, loteId));
    if (await arquivoSessao.exists()) await arquivoSessao.delete();

    final apontador = _arquivo(_nomeArquivoAtual(usuarioId));
    if (await apontador.exists() && (await apontador.readAsString()).trim() == loteId) {
      await apontador.delete();
    }
  }
}
