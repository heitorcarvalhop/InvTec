import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';

void main() {
  group('sugerirCampoPorCabecalho', () {
    test('reconhece aliases comuns de número patrimonial', () {
      expect(sugerirCampoPorCabecalho('Patrimônio'), ImportColumnField.numeroPatrimonio);
      expect(sugerirCampoPorCabecalho('Nº Patrimônio'), ImportColumnField.numeroPatrimonio);
      expect(sugerirCampoPorCabecalho('Tombamento'), ImportColumnField.numeroPatrimonio);
    });

    test('reconhece tipo/equipamento', () {
      expect(sugerirCampoPorCabecalho('Tipo'), ImportColumnField.tipo);
      expect(sugerirCampoPorCabecalho('Equipamento'), ImportColumnField.tipo);
    });

    test('reconhece setor/localização', () {
      expect(sugerirCampoPorCabecalho('Setor'), ImportColumnField.setor);
      expect(sugerirCampoPorCabecalho('Localização'), ImportColumnField.setor);
    });

    test('reconhece responsável', () {
      expect(sugerirCampoPorCabecalho('Responsável'), ImportColumnField.responsavel);
      expect(sugerirCampoPorCabecalho('Usuário'), ImportColumnField.responsavel);
    });

    test('não sugere nada para um cabeçalho desconhecido', () {
      expect(sugerirCampoPorCabecalho('Coluna Estranha XYZ'), isNull);
    });

    test('é insensível a caixa e acentuação', () {
      expect(sugerirCampoPorCabecalho('  MARCA  '), ImportColumnField.marca);
    });
  });
}
