import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_result_step.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// Totais consolidados (importados / já existentes / rejeitados /
/// pendentes) e o botão "Exportar CSV" do passo "Resultado" — derivados de
/// `ImportRow.status`/`resultado`, nunca um modelo paralelo (ver docstring
/// de `ImportResultStep`). Nunca toca as rotas de `go_router` (os botões
/// "Concluir"/"Ver patrimônios" não são tocados aqui) — então um
/// `MaterialApp` simples, sem `GoRouter`, já é suficiente.
ImportRow _linha({
  required int numeroLinha,
  required ImportRowStatus status,
  ImportRowResult? resultado,
}) => ImportRow(numeroLinha: numeroLinha, celulas: const {})
  ..numeroPatrimonio = '$numeroLinha'
  ..status = status
  ..resultado = resultado;

ProviderContainer _container() => ProviderContainer(
  overrides: [
    patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
    tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: const [])),
    setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: const [])),
    localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
    dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
  ],
);

void main() {
  testWidgets('mostra os 4 totais consolidados: importados / já existentes / rejeitados / pendentes', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});

    final state = PatrimonioImportState(
      linhas: [
        // 2 importadas com sucesso (1 novo, 1 atualizado).
        _linha(
          numeroLinha: 1,
          status: ImportRowStatus.pronto,
          resultado: const ImportRowResult(sucesso: true, patrimonioId: 'p1'),
        ),
        _linha(
          numeroLinha: 2,
          status: ImportRowStatus.atualizar,
          resultado: const ImportRowResult(sucesso: true, patrimonioId: 'p2'),
        ),
        // 1 já existente (nunca enviada).
        _linha(numeroLinha: 3, status: ImportRowStatus.existente),
        // 1 rejeitada (falha).
        _linha(
          numeroLinha: 4,
          status: ImportRowStatus.pronto,
          resultado: const ImportRowResult(sucesso: false, mensagemErro: 'erro'),
        ),
        // 1 pendente (seria enviada, mas ainda sem resultado — processo
        // interrompido no meio do lote).
        _linha(numeroLinha: 5, status: ImportRowStatus.pronto),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportResultStep(state: state)))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Importados: 2'), findsOneWidget);
    expect(find.text('Já existentes (mantidos): 1'), findsOneWidget);
    expect(find.text('Rejeitados (falha): 1'), findsOneWidget);
    expect(find.text('Pendentes (resultado desconhecido): 1'), findsOneWidget);

    final botaoExportar = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Exportar CSV'));
    expect(botaoExportar.onPressed, isNotNull); // há linhas com resultado => habilitado.
  });

  testWidgets('botão "Exportar CSV" fica desabilitado quando nenhuma linha tem resultado ainda', (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    container.listen(patrimonioImportControllerProvider, (_, _) {});

    final state = PatrimonioImportState(linhas: [_linha(numeroLinha: 1, status: ImportRowStatus.pronto)]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportResultStep(state: state)))),
      ),
    );
    await tester.pumpAndSettle();

    final botaoExportar = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Exportar CSV'));
    expect(botaoExportar.onPressed, isNull);
  });
}
