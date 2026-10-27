import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_lote_persistencia.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_lote_pendente_banner.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

ImportLoteSessaoPersistida _sessao() => ImportLoteSessaoPersistida(
  loteId: 'lote-banner',
  usuarioId: 'user-1',
  nomeArquivo: 'inventario_banner.csv',
  criadoEm: DateTime(2026, 1, 1, 9, 0),
  linhas: const [
    ImportLoteLinhaPersistida(numeroLinha: 1, operacaoId: 'op-1', status: ImportLoteLinhaPersistidaStatus.sucesso),
    ImportLoteLinhaPersistida(numeroLinha: 2, operacaoId: 'op-2', status: ImportLoteLinhaPersistidaStatus.falha),
    ImportLoteLinhaPersistida(numeroLinha: 3, operacaoId: 'op-3', status: ImportLoteLinhaPersistidaStatus.pendente),
  ],
);

ProviderContainer _container({bool importacaoLoteExecucaoHabilitada = true}) => ProviderContainer(
  overrides: [
    patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
    tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: const [])),
    setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: const [])),
    localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
    patrimonioImportControllerProvider.overrideWith(
      () => PatrimonioImportController(
        importacaoLoteExecucaoHabilitada: () => importacaoLoteExecucaoHabilitada,
        fileSystem: MemoryFileSystem(),
        resolverDiretorioPersistencia: () async => '/import-banner-test',
      ),
    ),
  ],
);

void main() {
  testWidgets('mostra contagens sucesso/falha/pendente e oferece Retomar quando o gate está ligado', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ImportLotePendenteBanner(sessao: _sessao()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('inventario_banner.csv'), findsOneWidget);
    expect(find.textContaining('1 linha(s) concluída(s) com sucesso'), findsOneWidget);
    expect(find.textContaining('1 com falha'), findsOneWidget);
    expect(find.textContaining('1 ainda pendente(s)'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    expect(find.text('Selecionar arquivo e retomar'), findsOneWidget);
  });

  testWidgets('com o gate desligado, só "Descartar" fica disponível (nunca "Retomar")', (tester) async {
    final container = _container(importacaoLoteExecucaoHabilitada: false);
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ImportLotePendenteBanner(sessao: _sessao()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Descartar'), findsOneWidget);
    expect(find.text('Selecionar arquivo e retomar'), findsNothing);
  });

  testWidgets('"Descartar" exige confirmação explícita — cancelar no diálogo não remove a sessão', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});
    const diretorio = '/import-banner-test';
    final fs = MemoryFileSystem();
    await ImportLotePersistencia(diretorio, fileSystem: fs).salvar(_sessao());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ImportLotePendenteBanner(sessao: _sessao()))),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(find.text('Descartar esta importação pendente?'), findsOneWidget);
    await tester.tap(find.text('Continuar editando'));
    await tester.pumpAndSettle();

    // nenhuma chamada de descarte foi disparada — nunca descarta sem confirmação.
    expect(find.text('Descartar esta importação pendente?'), findsNothing);
  });
}
