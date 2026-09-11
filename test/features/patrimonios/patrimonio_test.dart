import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';

void main() {
  final json = {
    'id': 'a1b2c3d4-0000-0000-0000-000000000010',
    'numero_patrimonio': '123456',
    'numero_serie': 'SN-001',
    'tipo_id': 'a1b2c3d4-0000-0000-0000-000000000030',
    'marca': 'Dell',
    'modelo': 'Latitude 5440',
    'descricao': 'Notebook corporativo',
    'observacao': null,
    'status': 'EM_USO',
    'setor_atual_id': 'a1b2c3d4-0000-0000-0000-000000000001',
    'responsavel_atual': 'Fulano de Tal',
    'data_aquisicao': '2025-05-20',
    'data_cadastro': '2026-01-10T12:00:00.000Z',
    'criado_por': 'a1b2c3d4-0000-0000-0000-000000000002',
    'atualizado_em': '2026-01-10T12:00:00.000Z',
  };

  group('Patrimonio', () {
    test('fromJson converte status para enum e mantém tipo_id como texto', () {
      final patrimonio = Patrimonio.fromJson(json);

      expect(patrimonio.tipoId, json['tipo_id']);
      expect(patrimonio.status, PatrimonioStatus.emUso);
      expect(patrimonio.responsavelAtual, 'Fulano de Tal');
      expect(patrimonio.numeroPatrimonio, '123456');
      expect(patrimonio.dataAquisicao, DateTime.parse('2025-05-20'));
    });

    test('patrimônio disponível não tem responsável atual', () {
      final patrimonio = Patrimonio.fromJson({
        ...json,
        'status': 'DISPONIVEL',
        'responsavel_atual': null,
      });

      expect(patrimonio.status, PatrimonioStatus.disponivel);
      expect(patrimonio.responsavelAtual, isNull);
    });

    test('numero_patrimonio e numero_serie podem ser nulos', () {
      final patrimonio = Patrimonio.fromJson({
        ...json,
        'numero_patrimonio': null,
        'numero_serie': null,
      });

      expect(patrimonio.numeroPatrimonio, isNull);
      expect(patrimonio.numeroSerie, isNull);
    });

    test('data_aquisicao pode ser nula quando desconhecida', () {
      final patrimonio = Patrimonio.fromJson({
        ...json,
        'data_aquisicao': null,
      });
      expect(patrimonio.dataAquisicao, isNull);
    });

    test('copyWith altera metadados e preserva status, setor e responsável', () {
      final patrimonio = Patrimonio.fromJson(json);
      final atualizado = patrimonio.copyWith(
        marca: 'HP',
        tipoId: 'a1b2c3d4-0000-0000-0000-000000000031',
      );

      expect(atualizado.marca, 'HP');
      expect(atualizado.tipoId, 'a1b2c3d4-0000-0000-0000-000000000031');
      expect(atualizado.id, patrimonio.id);
      expect(atualizado.status, patrimonio.status);
      expect(atualizado.setorAtualId, patrimonio.setorAtualId);
      expect(atualizado.responsavelAtual, patrimonio.responsavelAtual);
    });
  });

  group('PatrimonioStatus', () {
    test('lança erro para valor desconhecido', () {
      expect(
        () => PatrimonioStatus.fromValue('TRANSFERIDO'),
        throwsArgumentError,
      );
    });

    test('todos os 5 status são reconhecidos', () {
      const valores = [
        'DISPONIVEL',
        'EM_USO',
        'EMPRESTADO',
        'EM_MANUTENCAO',
        'BAIXADO',
      ];

      for (final valor in valores) {
        expect(PatrimonioStatus.fromValue(valor).value, valor);
      }
    });
  });

  group('normalizarNumeroPatrimonio', () {
    test('remove espaços das pontas', () {
      expect(normalizarNumeroPatrimonio(' 45872 '), '45872');
    });

    test('converte letras para maiúsculas', () {
      expect(normalizarNumeroPatrimonio('abc123'), 'ABC123');
    });

    test('preserva zeros à esquerda', () {
      expect(normalizarNumeroPatrimonio('00045872'), '00045872');
    });

    test('vazio, só espaços ou nulo viram nulo', () {
      expect(normalizarNumeroPatrimonio(''), isNull);
      expect(normalizarNumeroPatrimonio('   '), isNull);
      expect(normalizarNumeroPatrimonio(null), isNull);
    });
  });
}
