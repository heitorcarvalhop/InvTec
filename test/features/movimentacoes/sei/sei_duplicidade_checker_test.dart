import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_duplicidade_checker.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_duplicidade.dart';

MovimentacaoListagemItem _mov({
  String id = 'm1',
  String patrimonioId = 'p1',
  MovimentacaoTipo tipo = MovimentacaoTipo.transferencia,
  String? setorDestinoId = 'setor-geasi',
  String? numeroChamado = '4556',
  String? numeroDocumento = '95955192',
}) {
  return MovimentacaoListagemItem(
    id: id,
    tipo: tipo,
    patrimonioId: patrimonioId,
    setorDestinoId: setorDestinoId,
    numeroChamado: numeroChamado,
    numeroDocumento: numeroDocumento,
    dataMovimentacao: DateTime(2026, 1, 1),
  );
}

/// Classificação de duplicidade — só compara o que
/// já foi lido em lote (função pura, sem nenhum I/O).
void main() {
  group('classificarDuplicidade', () {
    test('nenhuma movimentação do patrimônio para este documento: sem correspondência', () {
      final resultado = classificarDuplicidade(
        patrimonioId: 'p1',
        tipoProposto: MovimentacaoTipo.transferencia,
        destinoIdProposto: 'setor-geasi',
        numeroChamadoProposto: '4556',
        historicoDoDocumento: const [],
      );
      expect(resultado.status, SeiDuplicidadeStatus.semCorrespondencia);
      expect(resultado.correspondente, isNull);
    });

    test('mesmo tipo, destino e chamado já registrados: já registrada', () {
      final resultado = classificarDuplicidade(
        patrimonioId: 'p1',
        tipoProposto: MovimentacaoTipo.transferencia,
        destinoIdProposto: 'setor-geasi',
        numeroChamadoProposto: '4556',
        historicoDoDocumento: [_mov()],
      );
      expect(resultado.status, SeiDuplicidadeStatus.jaRegistrada);
      expect(resultado.correspondente, isNotNull);
    });

    test('mesmo tipo mas destino diferente do proposto: possível duplicidade', () {
      final resultado = classificarDuplicidade(
        patrimonioId: 'p1',
        tipoProposto: MovimentacaoTipo.transferencia,
        destinoIdProposto: 'setor-gesol',
        numeroChamadoProposto: '4556',
        historicoDoDocumento: [_mov(setorDestinoId: 'setor-geasi')],
      );
      expect(resultado.status, SeiDuplicidadeStatus.possivelDuplicidade);
    });

    test('mesmo tipo mas chamado diferente do proposto: possível duplicidade', () {
      final resultado = classificarDuplicidade(
        patrimonioId: 'p1',
        tipoProposto: MovimentacaoTipo.transferencia,
        destinoIdProposto: 'setor-geasi',
        numeroChamadoProposto: '9999',
        historicoDoDocumento: [_mov(numeroChamado: '4556')],
      );
      expect(resultado.status, SeiDuplicidadeStatus.possivelDuplicidade);
    });

    test('já existe movimentação deste patrimônio para o documento, mas de tipo diferente: exige revisão', () {
      final resultado = classificarDuplicidade(
        patrimonioId: 'p1',
        tipoProposto: MovimentacaoTipo.transferencia,
        destinoIdProposto: 'setor-geasi',
        numeroChamadoProposto: '4556',
        historicoDoDocumento: [_mov(tipo: MovimentacaoTipo.baixa)],
      );
      expect(resultado.status, SeiDuplicidadeStatus.exigeRevisao);
    });

    test('mesma referência SEI em patrimônios DISTINTOS não é duplicidade', () {
      final resultado = classificarDuplicidade(
        patrimonioId: 'p2',
        tipoProposto: MovimentacaoTipo.transferencia,
        destinoIdProposto: 'setor-geasi',
        numeroChamadoProposto: '4556',
        // histórico é do mesmo documento SEI, mas para outro patrimônio (p1)
        historicoDoDocumento: [_mov(patrimonioId: 'p1')],
      );
      expect(resultado.status, SeiDuplicidadeStatus.semCorrespondencia);
    });
  });
}
