import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/setores/domain/setor.dart';

void main() {
  final json = {
    'id': 'a1b2c3d4-0000-0000-0000-000000000001',
    'nome': 'GETEC',
    'sigla': 'GETEC',
    'descricao': 'Gerência de Tecnologia',
    'ativo': true,
    'criado_em': '2026-01-10T12:00:00.000Z',
  };

  test('Setor.fromJson lê corretamente os campos', () {
    final setor = Setor.fromJson(json);

    expect(setor.id, json['id']);
    expect(setor.nome, 'GETEC');
    expect(setor.sigla, 'GETEC');
    expect(setor.ativo, isTrue);
  });

  test('Setor.fromJson aceita sigla e descricao nulas', () {
    final setor = Setor.fromJson({
      ...json,
      'sigla': null,
      'descricao': null,
    });

    expect(setor.sigla, isNull);
    expect(setor.descricao, isNull);
  });

  test('toJson é o inverso de fromJson para os campos principais', () {
    final setor = Setor.fromJson(json);
    final result = setor.toJson();

    expect(result['id'], json['id']);
    expect(result['nome'], json['nome']);
    expect(result['ativo'], json['ativo']);
  });

  test('copyWith substitui apenas os campos informados', () {
    final setor = Setor.fromJson(json);
    final atualizado = setor.copyWith(ativo: false);

    expect(atualizado.ativo, isFalse);
    expect(atualizado.nome, setor.nome);
    expect(atualizado.id, setor.id);
  });
}
