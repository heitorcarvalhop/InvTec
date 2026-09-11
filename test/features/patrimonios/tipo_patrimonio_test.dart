import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';

void main() {
  final json = {
    'id': 'a1b2c3d4-0000-0000-0000-000000000030',
    'nome': 'Notebook',
    'descricao': null,
    'ativo': true,
    'criado_em': '2026-01-10T12:00:00.000Z',
  };

  test('TipoPatrimonio.fromJson lê corretamente os campos', () {
    final tipo = TipoPatrimonio.fromJson(json);

    expect(tipo.id, json['id']);
    expect(tipo.nome, 'Notebook');
    expect(tipo.ativo, isTrue);
    expect(tipo.criadoEm, DateTime.parse('2026-01-10T12:00:00.000Z'));
  });

  test('descricao é opcional', () {
    final tipo = TipoPatrimonio.fromJson({
      ...json,
      'descricao': 'Notebooks corporativos padrão GETEC',
    });

    expect(tipo.descricao, 'Notebooks corporativos padrão GETEC');
  });

  test('tipo inativo é lido corretamente', () {
    final tipo = TipoPatrimonio.fromJson({...json, 'ativo': false});
    expect(tipo.ativo, isFalse);
  });
}
