import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_defaults_step.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_review_step.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// Os passos "Configurar padrões" e "Revisar" do
/// assistente de importação de planilha mostram a sigla real do setor
/// (nunca o nome completo) nos dropdowns/botões de decisão — mesma regra
/// já aplicada em Movimentações/Pendências. Monta o estado diretamente
/// (`controller.state = ...`), sem passar por `carregarArquivo` (usa
/// `compute()`, que pode travar sob `testWidgets` — mesmo raciocínio de
/// `import_locations_step_test.dart`), e pumpa cada widget de passo
/// isoladamente.
final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
// "GEPOS" não existe em nenhuma lista fixa do app — prova que a sigla vem
// do cadastro real, não de um switch fechado nos setores conhecidos.
final _setorGepos = Setor(id: 'setor-gepos', nome: 'Gerência de Posturas', sigla: 'GEPOS', ativo: true, criadoEm: DateTime(2026, 1, 1));

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: const [])),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGepos])),
      localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
    ],
  );
}

void main() {
  testWidgets('ImportDefaultsStep: dropdowns Destino/Origem padrão mostram a sigla real', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});
    final controller = container.read(patrimonioImportControllerProvider.notifier);
    controller.state = PatrimonioImportState();
    final state = container.read(patrimonioImportControllerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportDefaultsStep(state: state)))),
      ),
    );
    await tester.pumpAndSettle();

    final campoDestino = find.widgetWithText(DropdownButtonFormField<String?>, 'Destino padrão');
    await tester.ensureVisible(campoDestino);
    await tester.pumpAndSettle();
    await tester.tap(campoDestino);
    await tester.pumpAndSettle();

    expect(find.text('GETEC'), findsOneWidget);
    expect(find.text('GEPOS'), findsOneWidget);
    expect(find.text('Gerencia de Tecnologia'), findsNothing);
    expect(find.text('Gerência de Posturas'), findsNothing);
  });

  testWidgets(
    'ImportReviewStep: painel de decisão de setor não encontrado mostra a sigla, e a escolha continua usando o ID',
    (tester) async {
      // ImportReviewStep tem um resumo + filtros + lista, mais alto que a
      // viewport padrão de teste (800x600) — mesmo ajuste de
      // `import_tipos_pendentes_step_test.dart`.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _container();
      addTearDown(container.dispose);
      container.listen(patrimonioImportControllerProvider, (_, _) {});
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      final linha = ImportRow(numeroLinha: 2, celulas: {ImportColumnField.setor: 'Setor Desconhecido'})
        ..numeroPatrimonio = '00001'
        ..status = ImportRowStatus.erro
        ..setorTexto = 'Setor Desconhecido'
        ..destinoIdResolvido = null
        ..destinoIdSugerido = _setorGepos.id;
      controller.state = PatrimonioImportState(linhas: [linha]);
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: ImportReviewStep(state: state))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('L.2'));
      await tester.pumpAndSettle();

      // O botão de sugestão e o dropdown mostram a sigla (GEPOS), nunca o
      // nome completo do setor.
      expect(find.textContaining('GEPOS'), findsWidgets);
      expect(find.text('Gerência de Posturas'), findsNothing);

      await tester.tap(find.textContaining('Usar GEPOS'));
      await tester.pumpAndSettle();

      // O valor real da decisão continua sendo o ID do setor.
      expect(linha.destinoIdResolvido, _setorGepos.id);
    },
  );
}
