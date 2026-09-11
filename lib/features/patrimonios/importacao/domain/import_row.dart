import '../../domain/patrimonio_detalhe.dart';
import 'import_column_field.dart';

enum ImportIssueSeverity { erro, aviso }

class ImportIssue {
  const ImportIssue(this.severity, this.message);

  final ImportIssueSeverity severity;
  final String message;
}

/// Classificação final da linha (seção 20) — exatamente estes 6 valores,
/// sem um status extra para "duplicado dentro do arquivo": duplicidade é um
/// caso particular de ERRO até o usuário decidir qual ocorrência manter
/// (ver [ImportRow.duplicadoNoArquivo]).
enum ImportRowStatus { pronto, aviso, erro, ignorado, existente, atualizar }

extension ImportRowStatusLabel on ImportRowStatus {
  String get label {
    switch (this) {
      case ImportRowStatus.pronto:
        return 'Pronto';
      case ImportRowStatus.aviso:
        return 'Aviso';
      case ImportRowStatus.erro:
        return 'Erro';
      case ImportRowStatus.ignorado:
        return 'Ignorado';
      case ImportRowStatus.existente:
        return 'Já existente';
      case ImportRowStatus.atualizar:
        return 'Atualizar';
    }
  }
}

/// Decisão do usuário para um patrimônio cujo número já existe no InvTec
/// (seção 16) — nunca há opção de criar um duplicado.
enum ImportExistingAction { manterExistente, atualizarMetadados }

/// Resultado da tentativa de gravação de uma linha (seção 28: falha
/// parcial nunca derruba a importação inteira).
class ImportRowResult {
  const ImportRowResult({required this.sucesso, this.mensagemErro, this.patrimonioId});

  final bool sucesso;
  final String? mensagemErro;
  final String? patrimonioId;
}

/// Uma linha de dados da planilha, do texto bruto lido até a classificação
/// final pronta para gravação. É mutável de propósito: milhares de linhas
/// são reclassificadas repetidamente (mapeamento, padrões, decisões
/// individuais) e recriar objetos imutáveis a cada mudança seria caro sem
/// necessidade — ver ImportAnalyzer.
class ImportRow {
  ImportRow({required this.numeroLinha, required this.celulas});

  /// Número da linha na planilha original (1-based) — para o usuário achar
  /// a linha no arquivo original.
  final int numeroLinha;

  /// Texto bruto (já convertido de célula para String) de cada coluna
  /// mapeada, antes de qualquer resolução ou aplicação de padrão.
  final Map<ImportColumnField, String?> celulas;

  // --- campos resolvidos pelo ImportAnalyzer ---
  String? numeroPatrimonio;
  String? numeroPatrimonioNormalizado;
  String? numeroSerie;
  String? marca;
  String? modelo;
  String? descricao;
  String? observacao;
  String? motivo;
  DateTime? dataAquisicao;
  DateTime? dataEntrada;
  String? responsavelDestino;

  String? tipoTexto;
  String? tipoIdResolvido;
  String? tipoIdSugerido;

  String? setorTexto;
  String? destinoIdResolvido;
  String? destinoIdSugerido;

  String? origemTexto;
  String? origemIdResolvido;
  String? origemIdSugerido;

  bool usouDestinoPadrao = false;
  bool usouOrigemPadrao = false;
  bool usouResponsavelPadrao = false;
  bool usouMotivoPadrao = false;
  bool usouDataPadrao = false;

  /// Célula preenchida mas que não foi possível interpretar como data —
  /// usado por [ImportAnalyzer.classificar] para gerar o aviso
  /// correspondente (não é adicionado diretamente às issues durante a
  /// resolução, já que `classificar` limpa `issues` a cada chamada).
  bool dataAquisicaoNaoReconhecida = false;
  bool dataEntradaNaoReconhecida = false;

  bool duplicadoNoArquivo = false;
  PatrimonioDetalhe? existenteNoBanco;
  ImportExistingAction? acaoExistente;
  bool possivelDuplicidadeSerial = false;
  bool ignoradaManualmente = false;

  /// Setor de destino (texto da linha, antes de qualquer resolução) sugere
  /// que o bem já está baixado — sinal genérico interpretado por
  /// [ImportAnalyzer.classificar] como aviso; hoje só é preenchido pelo
  /// perfil GETEC (ver GetecImportProfile.indicaBaixa), mas não é exclusivo
  /// dele por construção.
  bool possivelBaixa = false;

  /// `true` quando o tipo não veio de uma coluna mapeada e sim foi deduzido
  /// automaticamente (ex.: inferência por descrição do perfil GETEC) — usado
  /// só para mostrar a etiqueta "Inferido" na revisão.
  bool tipoInferidoAutomaticamente = false;

  final List<ImportIssue> issues = [];
  ImportRowStatus status = ImportRowStatus.pronto;
  ImportRowResult? resultado;

  bool get temErro => issues.any((i) => i.severity == ImportIssueSeverity.erro);
  bool get temAviso => issues.any((i) => i.severity == ImportIssueSeverity.aviso);

  /// Vai para o Supabase nesta importação (novo cadastro ou atualização de
  /// metadados) — usado para contar "prontos para importar" e para o loop
  /// de gravação.
  bool get seraEnviada =>
      status == ImportRowStatus.pronto ||
      status == ImportRowStatus.aviso ||
      status == ImportRowStatus.atualizar;
}
