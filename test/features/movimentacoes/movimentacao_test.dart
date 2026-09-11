import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';

void main() {
  final json = {
    'id': 'a1b2c3d4-0000-0000-0000-000000000020',
    'patrimonio_id': 'a1b2c3d4-0000-0000-0000-000000000010',
    'tipo': 'TRANSFERENCIA',
    'origem_id': 'a1b2c3d4-0000-0000-0000-000000000001',
    'destino_id': 'a1b2c3d4-0000-0000-0000-000000000003',
    'responsavel_origem': 'Fulano',
    'responsavel_destino': 'Ciclano',
    'motivo': 'Realocação de equipe',
    'observacao': null,
    'numero_documento': 'TERMO-2026-001',
    'numero_chamado': null,
    'realizado_por': 'a1b2c3d4-0000-0000-0000-000000000002',
    'data_movimentacao': '2026-01-10T12:00:00.000Z',
    'criado_em': '2026-01-10T12:00:01.000Z',
  };

  test('Movimentacao.fromJson converte o tipo para o enum correto', () {
    final movimentacao = Movimentacao.fromJson(json);

    expect(movimentacao.tipo, MovimentacaoTipo.transferencia);
    expect(movimentacao.origemId, json['origem_id']);
    expect(movimentacao.destinoId, json['destino_id']);
    expect(movimentacao.numeroDocumento, 'TERMO-2026-001');
  });

  test('origem e destino podem ser nulos (ex.: BAIXA)', () {
    final movimentacao = Movimentacao.fromJson({
      ...json,
      'tipo': 'BAIXA',
      'destino_id': null,
    });

    expect(movimentacao.tipo, MovimentacaoTipo.baixa);
    expect(movimentacao.destinoId, isNull);
  });

  test('MovimentacaoTipo.fromValue lança erro para valor desconhecido', () {
    expect(
      () => MovimentacaoTipo.fromValue('CANCELAMENTO'),
      throwsArgumentError,
    );
  });

  test('todos os 10 tipos de movimentação são reconhecidos', () {
    const valores = [
      'ENTRADA',
      'SAIDA',
      'TRANSFERENCIA',
      'EMPRESTIMO',
      'DEVOLUCAO',
      'MANUTENCAO',
      'RETORNO_MANUTENCAO',
      'BAIXA',
      'AJUSTE_INVENTARIO',
      'ALTERACAO_RESPONSAVEL',
    ];

    for (final valor in valores) {
      expect(MovimentacaoTipo.fromValue(valor).value, valor);
    }
  });

  test(
    'ALTERACAO_RESPONSAVEL preserva o setor (origem = destino) e troca o responsável',
    () {
      final movimentacao = Movimentacao.fromJson({
        ...json,
        'tipo': 'ALTERACAO_RESPONSAVEL',
        'origem_id': json['destino_id'],
        'responsavel_origem': 'João',
        'responsavel_destino': 'Maria',
      });

      expect(movimentacao.tipo, MovimentacaoTipo.alteracaoResponsavel);
      expect(movimentacao.origemId, movimentacao.destinoId);
      expect(movimentacao.responsavelOrigem, 'João');
      expect(movimentacao.responsavelDestino, 'Maria');
    },
  );

  test('MovimentacaoTipoLabel traduz todos os 10 tipos para PT-BR', () {
    for (final tipo in MovimentacaoTipo.values) {
      expect(tipo.label, isNotEmpty);
    }
    expect(MovimentacaoTipo.transferencia.label, 'Transferência');
    expect(MovimentacaoTipo.retornoManutencao.label, 'Retorno de manutenção');
    expect(
      MovimentacaoTipo.alteracaoResponsavel.label,
      'Alteração de responsável',
    );
  });
}
