import 'import_column_field.dart';

/// Mapeamento de colunas escolhido pelo usuário para a importação atual —
/// vale só para esta importação (seção 43: persistência de modelos fica
/// para uma etapa futura).
class ImportColumnMapping {
  const ImportColumnMapping(this.colunaPorCampo);

  static const vazio = ImportColumnMapping({});

  /// Índice da coluna (0-based, relativa às colunas da aba) escolhida para
  /// cada campo do InvTec; `null` (ou ausente) significa "Não importar esta
  /// coluna" / campo não presente na planilha.
  final Map<ImportColumnField, int?> colunaPorCampo;

  int? colunaDe(ImportColumnField campo) => colunaPorCampo[campo];

  ImportColumnMapping definindo(ImportColumnField campo, int? coluna) {
    final novoMapa = Map<ImportColumnField, int?>.from(colunaPorCampo);
    if (coluna == null) {
      novoMapa.remove(campo);
    } else {
      novoMapa[campo] = coluna;
    }
    return ImportColumnMapping(novoMapa);
  }
}
