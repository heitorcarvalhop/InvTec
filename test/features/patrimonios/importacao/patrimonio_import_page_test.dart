import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/importacao/data/spreadsheet_parser.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_page.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';

import '../../auth/fake_auth_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

/// Subclasse só para teste: expõe uma forma de forçar um [state] arbitrário
/// sem passar por [PatrimonioImportController.carregarArquivo]. O parser
/// real usa `compute()` (isolate) para ler a planilha — algo que trava
/// indefinidamente quando chamado de dentro de um `testWidgets` (o ambiente
/// de teste do Flutter não entrega a mensagem de volta do isolate gerado).
/// Como este domínio de teste é só "há progresso no assistente ou não" (ver
/// `_temProgressoRelevante` em `patrimonio_import_page.dart`), simular o
/// estado pós-carregamento direto é suficiente e evita essa armadilha —
/// nunca usar isto para testar o parser em si (isso já é coberto por
/// `spreadsheet_parser_test.dart`/`patrimonio_import_controller_test.dart`,
/// que chamam `carregarArquivo` fora de `testWidgets`).
class _ControladorComEstadoForcado extends PatrimonioImportController {
  void forcarEstado(PatrimonioImportState estado) {
    state = estado;
  }
}

/// Estado equivalente ao que `carregarArquivo` produziria para uma planilha
/// CSV de uma aba só: pula direto para `selecionarCabecalho` (ver
/// `PatrimonioImportController.carregarArquivo`).
PatrimonioImportState _estadoComArquivoCarregado() => PatrimonioImportState(
  nomeArquivo: 'inventario.csv',
  abas: [
    const ImportParsedSheet(
      nome: 'Sheet1',
      linhas: [
        ['Patrimônio', 'Tipo', 'Marca', 'Serial', 'Setor'],
        ['00045872', 'Notebook', 'Dell', 'AAA1', 'GETEC'],
      ],
    ),
  ],
  abaSelecionadaIndice: 0,
  step: ImportStep.selecionarCabecalho,
);

/// Monta o assistente de importação dentro de um `GoRouter` de verdade,
/// aberto via `context.push` a partir de uma página "/patrimonios" —
/// exatamente como a sidebar faz hoje (seção "Patrimônios" > "Importar").
/// Retorna o [ProviderContainer] usado, para os testes poderem forçar um
/// estado "com progresso" diretamente no controller (ver
/// [_ControladorComEstadoForcado]).
Future<ProviderContainer> _pumpImportPage(WidgetTester tester) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(ProfilePerfil.admin),
  );
  addTearDown(fakeAuth.dispose);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      patrimonioImportControllerProvider.overrideWith(_ControladorComEstadoForcado.new),
    ],
  );
  addTearDown(container.dispose);
  // mantém o NotifierProvider.autoDispose vivo durante todo o teste.
  container.listen(patrimonioImportControllerProvider, (_, _) {});

  final router = GoRouter(
    initialLocation: '/patrimonios',
    routes: [
      GoRoute(
        path: '/patrimonios',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push('/patrimonios/importar'),
              child: const Text('Abrir importação'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/patrimonios/importar',
        builder: (context, state) => const Scaffold(body: PatrimonioImportPage()),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Abrir importação'));
  await tester.pumpAndSettle();

  return container;
}

void main() {
  testWidgets(
    'sem progresso (ainda no passo de seleção de arquivo): Cancelar importação sai direto, sem confirmação',
    (tester) async {
      await _pumpImportPage(tester);

      // O cabeçalho (com a ação de cancelar) já está disponível no
      // primeiro passo, que antes não tinha nenhuma saída além da sidebar.
      expect(find.text('Cancelar importação'), findsOneWidget);
      expect(find.text('Selecionar arquivo'), findsOneWidget);

      await tester.tap(find.text('Cancelar importação'));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsNothing);
      expect(find.text('Abrir importação'), findsOneWidget);
      expect(find.byType(PatrimonioImportPage), findsNothing);
    },
  );

  testWidgets(
    'com progresso (arquivo já carregado): Cancelar importação pede confirmação; Continuar editando mantém o assistente',
    (tester) async {
      final container = await _pumpImportPage(tester);

      final controller =
          container.read(patrimonioImportControllerProvider.notifier) as _ControladorComEstadoForcado;
      controller.forcarEstado(_estadoComArquivoCarregado());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar importação'));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsOneWidget);

      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsNothing);
      expect(find.byType(PatrimonioImportPage), findsOneWidget);
      // o progresso (arquivo carregado, já no passo de cabeçalho) continua
      // presente — nada foi descartado.
      expect(container.read(patrimonioImportControllerProvider).nomeArquivo, 'inventario.csv');
    },
  );

  testWidgets(
    'com progresso (arquivo já carregado): Descartar sai, reinicia o assistente e volta para Patrimônios',
    (tester) async {
      final container = await _pumpImportPage(tester);

      final controller =
          container.read(patrimonioImportControllerProvider.notifier) as _ControladorComEstadoForcado;
      controller.forcarEstado(_estadoComArquivoCarregado());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar importação'));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsOneWidget);

      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      expect(find.text('Abrir importação'), findsOneWidget);
      expect(find.byType(PatrimonioImportPage), findsNothing);
      expect(container.read(patrimonioImportControllerProvider).nomeArquivo, isNull);
    },
  );
}
