import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_comparacao.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_csv_linha.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_execucao.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../fake_patrimonio_repository.dart';

Setor _setor({required String id, required String nome, String? sigla}) =>
    Setor(id: id, nome: nome, sigla: sigla, ativo: true, criadoEm: DateTime(2026, 1, 1));

PatrimonioDetalhe _patrimonio({
  required String id,
  required String numero,
  required String setorAtualId,
  DateTime? atualizadoEm,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.emUso,
      setorAtualId: setorAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: atualizadoEm ?? DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'GETEC',
  );
}

RetificacaoCsvLinha _linha({required String patrimonioId, required String tombamento, required String sigla}) {
  return RetificacaoCsvLinha(
    numeroLinha: 2,
    patrimonioId: patrimonioId,
    tombamentoOficial: tombamento,
    tombamentoAtualInvtec: tombamento,
    descricaoOficial: 'Descrição',
    setorAtualTexto: 'GETEC',
    unidadeCorretaSigla: sigla,
    unidadeCorretaNome: '',
  );
}

void main() {
  final getec = _setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC');
  final cimehgo = _setor(id: 'setor-cimehgo', nome: 'CIMEHGO', sigla: 'CIMEHGO');

  group('construirItensRetificacaoParaExecucao', () {
    test('só inclui itens PRONTOS — nunca jaNaUnidadeCorreta nem bloqueados', () {
      final pronto = _patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id);
      final jaCorreto = _patrimonio(id: 'p2', numero: '2', setorAtualId: cimehgo.id);

      final lote = RetificacaoComparador.comparar(
        linhas: [
          _linha(patrimonioId: 'p1', tombamento: '1', sigla: 'CIMEHGO'),
          _linha(patrimonioId: 'p2', tombamento: '2', sigla: 'CIMEHGO'),
          _linha(patrimonioId: 'nao-existe', tombamento: '3', sigla: 'CIMEHGO'),
        ],
        patrimoniosPorId: {'p1': pronto, 'p2': jaCorreto},
        setores: [getec, cimehgo],
      );

      var contador = 0;
      final itens = construirItensRetificacaoParaExecucao(
        lote: lote,
        loteId: 'lote-1',
        justificativa: 'Plano de reclassificação SEMAD',
        gerarOperacaoId: () => 'op-${contador++}',
      );

      expect(itens, hasLength(1));
      expect(itens.single.patrimonioId, 'p1');
      expect(itens.single.setorDestinoId, cimehgo.id);
      expect(itens.single.justificativa, 'Plano de reclassificação SEMAD');
      expect(itens.single.tombamentoEsperado, '1');
    });

    test('cada item recebe um operacaoId PRÓPRIO, gerado uma única vez', () {
      final p1 = _patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id);
      final p2 = _patrimonio(id: 'p2', numero: '2', setorAtualId: getec.id);

      final lote = RetificacaoComparador.comparar(
        linhas: [
          _linha(patrimonioId: 'p1', tombamento: '1', sigla: 'CIMEHGO'),
          _linha(patrimonioId: 'p2', tombamento: '2', sigla: 'CIMEHGO'),
        ],
        patrimoniosPorId: {'p1': p1, 'p2': p2},
        setores: [getec, cimehgo],
      );

      var contador = 0;
      final itens = construirItensRetificacaoParaExecucao(
        lote: lote,
        loteId: 'lote-1',
        justificativa: 'j',
        gerarOperacaoId: () => 'op-${contador++}',
      );

      expect(itens.map((i) => i.operacaoId).toSet(), hasLength(2));
    });
  });

  group('FakePatrimonioRepository.retificarUnidadePatrimonio', () {
    test('executa a retificação: muda o setor, limpa a localização, nunca toca responsável/status', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id)],
      );
      final item = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1),
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: cimehgo.id,
        justificativa: 'Plano SEMAD',
      );

      final resultado = await repo.retificarUnidadePatrimonio(item);

      expect(resultado.jaExecutado, isFalse);
      expect(resultado.setorOrigemId, getec.id);
      expect(resultado.setorDestinoId, cimehgo.id);
      expect(repo.retificarUnidadePatrimonioCallCount, 1);
      expect(repo.retificacoesAplicadas, hasLength(1));

      final atualizado = await repo.buscarDetalhePorId('p1');
      expect(atualizado!.patrimonio.setorAtualId, cimehgo.id);
      expect(atualizado.patrimonio.localizacaoAtualId, isNull);
    });

    test('reenviar o MESMO operacaoId com os mesmos parâmetros é idempotente', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id)],
      );
      final item = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1),
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: cimehgo.id,
        justificativa: 'Plano SEMAD',
      );

      await repo.retificarUnidadePatrimonio(item);
      final segunda = await repo.retificarUnidadePatrimonio(item);

      expect(segunda.jaExecutado, isTrue);
      expect(repo.retificacoesAplicadas, hasLength(1)); // nenhuma segunda escrita
    });

    test('reenviar o MESMO operacaoId com parâmetros diferentes é conflito (P0041)', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id)],
      );
      final primeiro = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1),
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: cimehgo.id,
        justificativa: 'Plano SEMAD',
      );
      await repo.retificarUnidadePatrimonio(primeiro);

      final comOutraJustificativa = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1),
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: cimehgo.id,
        justificativa: 'Justificativa diferente',
      );

      await expectLater(
        repo.retificarUnidadePatrimonio(comOutraJustificativa),
        throwsA(
          isA<RetificacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0041'),
        ),
      );
    });

    test('conflito de versão (patrimônio mudou desde o snapshot): P0040, nada é gravado', () async {
      final repo = FakePatrimonioRepository(
        itens: [
          _patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id, atualizadoEm: DateTime(2026, 2, 1)),
        ],
      );
      final item = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1), // snapshot antigo
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: cimehgo.id,
        justificativa: 'j',
      );

      await expectLater(
        repo.retificarUnidadePatrimonio(item),
        throwsA(isA<RetificacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0040')),
      );
      expect(repo.retificacoesAplicadas, isEmpty);
    });

    test('tombamento divergente do esperado: P0044, nada é gravado', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '999', setorAtualId: getec.id)],
      );
      final item = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1),
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: cimehgo.id,
        justificativa: 'j',
      );

      await expectLater(
        repo.retificarUnidadePatrimonio(item),
        throwsA(isA<RetificacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0044')),
      );
      expect(repo.retificacoesAplicadas, isEmpty);
    });

    test('destino igual à unidade atual: P0045, nada é gravado', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '1', setorAtualId: getec.id)],
      );
      final item = ItemRetificacaoParaExecutar(
        operacaoId: 'op-1',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        tombamentoEsperado: '1',
        versaoEsperada: DateTime(2026, 1, 1),
        setorOrigemEsperadoId: getec.id,
        setorDestinoId: getec.id, // igual ao atual
        justificativa: 'j',
      );

      await expectLater(
        repo.retificarUnidadePatrimonio(item),
        throwsA(isA<RetificacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0045')),
      );
      expect(repo.retificacoesAplicadas, isEmpty);
    });

    test(
      'unidade atual real diferente da esperada no snapshot: P0046, nada é gravado '
      '(auditoria: checagem explícita, não só o efeito colateral de atualizado_em)',
      () async {
        // Patrimônio já está em CIMEHGO de verdade, mas o item "acha" que
        // ainda está em GETEC (snapshot desatualizado) — mesmo que
        // `atualizado_em` por acaso não tenha mudado (ex.: a movimentação
        // anterior aconteceu exatamente no mesmo instante do cadastro).
        final repo = FakePatrimonioRepository(
          itens: [
            _patrimonio(id: 'p1', numero: '1', setorAtualId: cimehgo.id, atualizadoEm: DateTime(2026, 1, 1)),
          ],
        );
        final item = ItemRetificacaoParaExecutar(
          operacaoId: 'op-1',
          loteId: 'lote-1',
          patrimonioId: 'p1',
          tombamentoEsperado: '1',
          versaoEsperada: DateTime(2026, 1, 1),
          setorOrigemEsperadoId: getec.id, // snapshot desatualizado
          setorDestinoId: _setor(id: 'setor-gecad', nome: 'GECAD', sigla: 'GECAD').id,
          justificativa: 'j',
        );

        await expectLater(
          repo.retificarUnidadePatrimonio(item),
          throwsA(isA<RetificacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0046')),
        );
        expect(repo.retificacoesAplicadas, isEmpty);
      },
    );
  });
}
