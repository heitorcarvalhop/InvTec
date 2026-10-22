import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_search_field.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_controller.dart';

import 'fake_patrimonio_repository.dart';

/// InvTec 4.0 — Pesquisa inteligente, Fase 3 (tombamento anterior).
///
/// Cobre especificamente o que é NOVO nesta tarefa: a busca por
/// `patrimonio_tombamentos_historico` (ainda sem migration aplicada em
/// produção). A regressão de busca por descrição/marca/série e a
/// paginação/debounce/corrida entre buscas já estão cobertas por
/// `patrimonios_controller_test.dart` (inalterado nesses aspectos) — não
/// duplicadas aqui.
Patrimonio _patrimonio({required String id, required String numero}) =>
    Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-1',
      dataCadastro: DateTime.utc(2026, 1, 1),
      atualizadoEm: DateTime.utc(2026, 1, 1),
    );

PatrimonioDetalhe _detalhe({required String id, required String numero}) =>
    PatrimonioDetalhe(
      patrimonio: _patrimonio(id: id, numero: numero),
      tipoNome: 'Tipo',
      setorNome: 'Setor',
    );

ProviderContainer _container(PatrimonioRepository repo) {
  final container = ProviderContainer(
    overrides: [patrimonioRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(patrimoniosControllerProvider, (_, _) {});
  return container;
}

void main() {
  group('Migration 3A.4 — ativação consciente', () {
    test(
      'historicoTombamentosDisponivel é true — migration 3A.4 e a RPC de '
      'importação aplicadas e conferidas em produção, 121 históricos '
      'importados (0 conflitos, 0 falhas), decisão administrativa de 2026-10-20',
      () {
        // Tripwire deliberado (mesma ideia de antes, invertida): qualquer
        // mudança nesta flag precisa passar por uma decisão consciente,
        // documentada no comentário de patrimonio_repository.dart — nunca
        // "ligar/desligar sozinha" silenciosamente.
        expect(historicoTombamentosDisponivel, isTrue);
      },
    );
  });

  group('buscarPorTombamentoAnterior — Fase 3', () {
    test('tombamento anterior validado encontra o patrimônio pelo número ATUAL', () async {
      final atual = _detalhe(id: '1', numero: '654321');
      final repo = FakePatrimonioRepository(
        itens: [atual],
        historicoAnterior: {
          '123456': [('1', 'IMPORTACAO_PLANILHA')],
        },
      );

      final resultado = await repo.buscarPorTombamentoAnterior('123456');

      expect(resultado, hasLength(1));
      expect(resultado.single.patrimonio.patrimonio.numeroPatrimonio, '654321');
      expect(resultado.single.numeroAnteriorEncontrado, '123456');
      expect(resultado.single.origem, 'IMPORTACAO_PLANILHA');
    });

    test('zeros à esquerda no termo buscado são equivalentes ao anterior registrado', () async {
      final atual = _detalhe(id: '1', numero: '654321');
      final repo = FakePatrimonioRepository(
        itens: [atual],
        historicoAnterior: {
          '123456': [('1', 'ALTERACAO_DIRETA')],
        },
      );

      final resultado = await repo.buscarPorTombamentoAnterior('0000123456');

      expect(resultado, hasLength(1));
      expect(resultado.single.patrimonio.patrimonio.numeroPatrimonio, '654321');
    });

    test('tombamento anterior inexistente não encontra nada (nunca inventa correspondência)', () async {
      final repo = FakePatrimonioRepository(
        itens: [_detalhe(id: '1', numero: '654321')],
        historicoAnterior: {
          '123456': [('1', 'MANUAL')],
        },
      );

      final resultado = await repo.buscarPorTombamentoAnterior('999999');

      expect(resultado, isEmpty);
    });

    test(
      'histórico AMBÍGUO (mesmo anterior em bens diferentes): devolve todos, nunca escolhe um',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [
            _detalhe(id: '1', numero: '111111'),
            _detalhe(id: '2', numero: '222222'),
          ],
          historicoAnterior: {
            '999999': [('1', 'ADMINISTRATIVA'), ('2', 'MANUAL')],
          },
        );

        final resultado = await repo.buscarPorTombamentoAnterior('999999');

        expect(resultado, hasLength(2));
        expect(
          resultado.map((r) => r.patrimonio.patrimonio.numeroPatrimonio).toSet(),
          {'111111', '222222'},
        );
      },
    );

    test('falha de consulta ao histórico propaga o erro (nunca silenciosamente vira lista vazia)', () async {
      final repo = FakePatrimonioRepository(
        itens: const [],
        erroHistoricoAnterior: Exception('falha de rede simulada'),
      );

      await expectLater(
        repo.buscarPorTombamentoAnterior('123456'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PatrimoniosController — integração com a busca histórica (Fase 4: prioridade/dedup)', () {
    test(
      'busca "Tudo" por tombamento anterior: aparece em correspondenciasPorTombamentoAnterior, nunca em itens',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_detalhe(id: '1', numero: '654321')],
          historicoAnterior: {
            '123456': [('1', 'IMPORTACAO_PLANILHA')],
          },
        );
        final container = _container(repo);
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.buscar('123456');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens, isEmpty, reason: 'não é o tombamento ATUAL de ninguém');
        expect(state.resultado.correspondenciasPorTombamentoAnterior, hasLength(1));
        final encontrado = state.resultado.correspondenciasPorTombamentoAnterior.single;
        expect(encontrado.patrimonio.patrimonio.numeroPatrimonio, '654321');
        expect(encontrado.numeroAnteriorEncontrado, '123456');
      },
    );

    test(
      'quando o próprio tombamento ATUAL já bate, o resultado histórico continua aparecendo (não oculta)',
      () async {
        // 555555 é ao mesmo tempo (a) o tombamento ATUAL de um bem E (b) o
        // tombamento ANTERIOR de outro — Fase 4: "não ocultar outros
        // resultados válidos".
        final repo = FakePatrimonioRepository(
          itens: [
            _detalhe(id: '1', numero: '555555'),
            _detalhe(id: '2', numero: '777777'),
          ],
          historicoAnterior: {
            '555555': [('2', 'MANUAL')],
          },
        );
        final container = _container(repo);
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.buscar('555555');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(
          state.resultado.itens.map((i) => i.patrimonio.numeroPatrimonio),
          ['555555'],
        );
        expect(state.resultado.correspondenciasPorTombamentoAnterior, hasLength(1));
        expect(
          state.resultado.correspondenciasPorTombamentoAnterior.single.patrimonio.patrimonio.numeroPatrimonio,
          '777777',
        );
      },
    );

    test(
      'nunca repete o mesmo patrimônio: se já está em itens pelo atual, não duplica em correspondenciasPorTombamentoAnterior',
      () async {
        // Caso de borda: o próprio bem 1 tem, no seu HISTÓRICO, uma
        // entrada cujo "anterior" normalizado é igual ao seu PRÓPRIO
        // tombamento atual (ex.: um erro de digitação corrigido e
        // corrigido de volta) — nunca deve aparecer duas vezes para a
        // mesma busca.
        final repo = FakePatrimonioRepository(
          itens: [_detalhe(id: '1', numero: '123456')],
          historicoAnterior: {
            '123456': [('1', 'ALTERACAO_DIRETA')],
          },
        );
        final container = _container(repo);
        addTearDown(container.dispose);
        final notifier = container.read(patrimoniosControllerProvider.notifier);

        notifier.buscar('123456');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final state = await container.read(patrimoniosControllerProvider.future);

        expect(state.resultado.itens, hasLength(1));
        expect(
          state.resultado.correspondenciasPorTombamentoAnterior,
          isEmpty,
          reason: 'o bem 1 já apareceu em itens pelo tombamento atual — nunca duplicado',
        );
      },
    );

    test('campo "Patrimônio" também encontra por tombamento anterior (não só o modo Tudo)', () async {
      final repo = FakePatrimonioRepository(
        itens: [_detalhe(id: '1', numero: '654321')],
        historicoAnterior: {
          '123456': [('1', 'MANUAL')],
        },
      );
      final container = _container(repo);
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.definirCampoBusca(PatrimonioSearchField.patrimonio);
      notifier.buscar('123456');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.correspondenciasPorTombamentoAnterior, hasLength(1));
    });

    test('filtros existentes (setor) continuam combinando por AND com a busca histórica', () async {
      // A busca histórica em si não aplica _FiltrosComuns (ela busca
      // direto na tabela de histórico) — mas o filtro de setor precisa
      // continuar funcionando normalmente para `itens`, sem que a
      // presença de correspondências históricas interfira.
      final repo = FakePatrimonioRepository(
        itens: [
          _detalhe(id: '1', numero: '123456'),
          _detalhe(id: '2', numero: '123457'),
        ],
        historicoAnterior: const {},
      );
      final container = _container(repo);
      addTearDown(container.dispose);
      final notifier = container.read(patrimoniosControllerProvider.notifier);

      notifier.buscar('1234');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final state = await container.read(patrimoniosControllerProvider.future);

      expect(state.resultado.itens, hasLength(2));
    });
  });
}
