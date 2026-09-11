import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/domain/movimentacao_resumo.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';

void main() {
  test('fromJson lê patrimônio e setores embutidos (join do Postgrest)', () {
    final resumo = MovimentacaoResumo.fromJson({
      'id': 'a1b2c3d4-0000-0000-0000-000000000020',
      'tipo': 'TRANSFERENCIA',
      'data_movimentacao': '2026-01-10T12:00:00.000Z',
      'patrimonios': {
        'numero_patrimonio': '00045872',
        'descricao': 'Notebook Dell',
      },
      'origem': {'nome': 'GETEC'},
      'destino': {'nome': 'Almoxarifado'},
    });

    expect(resumo.tipo, MovimentacaoTipo.transferencia);
    expect(resumo.patrimonioLabel, '00045872');
    expect(resumo.origemNome, 'GETEC');
    expect(resumo.destinoNome, 'Almoxarifado');
  });

  test('usa a descrição quando não há número de patrimônio', () {
    final resumo = MovimentacaoResumo.fromJson({
      'id': 'a1b2c3d4-0000-0000-0000-000000000021',
      'tipo': 'ENTRADA',
      'data_movimentacao': '2026-01-10T12:00:00.000Z',
      'patrimonios': {'numero_patrimonio': null, 'descricao': 'Monitor LG'},
      'origem': null,
      'destino': {'nome': 'GETEC'},
    });

    expect(resumo.patrimonioLabel, 'Monitor LG');
  });

  test('origem e destino nulos (ex.: BAIXA) não quebram o parsing', () {
    final resumo = MovimentacaoResumo.fromJson({
      'id': 'a1b2c3d4-0000-0000-0000-000000000022',
      'tipo': 'BAIXA',
      'data_movimentacao': '2026-01-10T12:00:00.000Z',
      'patrimonios': {'numero_patrimonio': '123', 'descricao': null},
      'origem': {'nome': 'GETEC'},
      'destino': null,
    });

    expect(resumo.destinoNome, isNull);
    expect(resumo.origemNome, 'GETEC');
  });
}
