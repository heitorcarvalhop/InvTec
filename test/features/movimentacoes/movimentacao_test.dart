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

  test('todos os 11 tipos de movimentação são reconhecidos', () {
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
      'RETIFICACAO_CADASTRAL',
    ];

    for (final valor in valores) {
      expect(MovimentacaoTipo.fromValue(valor).value, valor);
    }
    // Lista acima precisa cobrir TODOS os valores do enum — nenhum deixado
    // de fora por engano (foi exatamente isso que faltou quando
    // RETIFICACAO_CADASTRAL foi adicionada ao enum do Postgres sem
    // atualizar o lado Dart: Movimentacao.fromJson teria lançado
    // ArgumentError ao carregar o histórico de QUALQUER patrimônio
    // retificado — auditoria da migration 20261022140000).
    expect(valores, hasLength(MovimentacaoTipo.values.length));
  });

  test(
    'RETIFICACAO_CADASTRAL nunca lança ao desserializar — regressão da '
    'auditoria da migration retificar_unidade_patrimonio (Movimentacao.'
    'fromJson throwia ArgumentError antes desta correção, quebrando o '
    'histórico de qualquer patrimônio retificado)',
    () {
      final movimentacao = Movimentacao.fromJson({
        ...json,
        'tipo': 'RETIFICACAO_CADASTRAL',
        'destino_id': json['destino_id'],
        // responsável NUNCA muda por este tipo — origem e destino idênticos,
        // mesmo padrão já usado por AJUSTE_INVENTARIO.
        'responsavel_origem': 'Fulano',
        'responsavel_destino': 'Fulano',
      });

      expect(movimentacao.tipo, MovimentacaoTipo.retificacaoCadastral);
      expect(movimentacao.responsavelOrigem, movimentacao.responsavelDestino);
    },
  );

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

  test('MovimentacaoTipoLabel traduz todos os 11 tipos para PT-BR', () {
    for (final tipo in MovimentacaoTipo.values) {
      expect(tipo.label, isNotEmpty);
    }
    expect(MovimentacaoTipo.transferencia.label, 'Transferência');
    expect(MovimentacaoTipo.retornoManutencao.label, 'Retorno de manutenção');
    expect(
      MovimentacaoTipo.alteracaoResponsavel.label,
      'Alteração de responsável',
    );
    expect(MovimentacaoTipo.retificacaoCadastral.label, 'Retificação cadastral');
  });
}
