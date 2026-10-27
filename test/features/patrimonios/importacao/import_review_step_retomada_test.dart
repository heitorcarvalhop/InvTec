import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_lote_persistencia.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_review_step.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// Prova, no nível de WIDGET (não só de controller), que o passo "Revisar"
/// reconhece uma sessão em retomada (`PatrimonioImportState
/// .loteAnteriorPendente`) e usa o botão de confirmação para chamar
/// `retomarLoteAnterior` em vez de `confirmarImportacao` — ver
/// `ImportLotePendenteBanner` para a oferta inicial de "retomar"/
/// "descartar".
ImportRow _linhaParaEnvio({required int numeroLinha, required String numeroPatrimonio}) =>
    ImportRow(numeroLinha: numeroLinha, celulas: const {})
      ..numeroPatrimonio = numeroPatrimonio
      ..numeroPatrimonioNormalizado = numeroPatrimonio
      ..tipoIdResolvido = 'tipo-x'
      ..destinoIdResolvido = 'setor-x'
      ..status = ImportRowStatus.pronto;

void main() {
  testWidgets(
    'botão de confirmação mostra "Retomar importação" e chama retomarLoteAnterior (reaproveita o loteId da sessão)',
    (tester) async {
      // ImportReviewStep é mais alto que a viewport padrão de teste
      // (800x600) — mesmo ajuste de `import_setor_sigla_test.dart`.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakePatrimonioRepository();
      final fs = MemoryFileSystem();
      final container = ProviderContainer(
        overrides: [
          patrimonioRepositoryProvider.overrideWithValue(repo),
          tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: const [])),
          setorRepositoryProvider.overrideWithValue(
            FakeSetorRepository(
              setores: [Setor(id: 'setor-x', nome: 'Setor X', sigla: 'SX', ativo: true, criadoEm: DateTime(2026, 1, 1))],
            ),
          ),
          localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          patrimonioImportControllerProvider.overrideWith(
            () => PatrimonioImportController(
              importacaoLoteExecucaoHabilitada: () => true,
              fileSystem: fs,
              resolverDiretorioPersistencia: () async => '/import-review-retomada',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(patrimonioImportControllerProvider, (_, _) {});
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      final sessao = ImportLoteSessaoPersistida(
        loteId: 'lote-widget-retomada',
        usuarioId: 'user-1',
        nomeArquivo: 'original.csv',
        criadoEm: DateTime(2026, 1, 1),
        linhas: const [
          ImportLoteLinhaPersistida(numeroLinha: 1, operacaoId: 'op-w-1', status: ImportLoteLinhaPersistidaStatus.pendente),
        ],
      );
      controller.state = PatrimonioImportState(
        linhas: [_linhaParaEnvio(numeroLinha: 1, numeroPatrimonio: '870001')],
        loteAnteriorPendente: sessao,
      );
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportReviewStep(state: state)))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retomar importação (1)'), findsOneWidget);

      await tester.tap(find.text('Retomar importação (1)'));
      await tester.pumpAndSettle();

      // diálogo de confirmação da revalidação.
      expect(find.text('Confirmar importação'), findsOneWidget);
      await tester.tap(find.text('Confirmar importação'));
      await tester.pumpAndSettle();

      expect(repo.cadastrarLoteCallCount, 1);
      final estadoFinal = container.read(patrimonioImportControllerProvider);
      expect(estadoFinal.loteIdAtual, 'lote-widget-retomada'); // prova que foi `retomarLoteAnterior`, não uma rodada nova.
      expect(estadoFinal.loteAnteriorPendente, isNull);
      expect(estadoFinal.step, ImportStep.resultado);
    },
  );
}
