import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/widgets/empty_state.dart';
import 'package:invtec/features/dashboard/presentation/widgets/consultar_patrimonio_dialog.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

import '../patrimonios/fake_patrimonio_repository.dart';

/// Correção de overflow (InvTec 4.0 — Android): "Consultar patrimônio"
/// (Dashboard) estourava "BOTTOM OVERFLOWED BY 73 PIXELS" quando o teclado
/// virtual abria, porque a região de conteúdo tinha altura FIXA
/// (`SizedBox(height: 260)`) — exigia mais espaço do que o `Dialog`
/// efetivamente tinha disponível depois de `MediaQuery.viewInsets` reduzir
/// a altura da caixa (ver `Dialog.build`, que soma `viewInsets` ao seu
/// `insetPadding`). Este arquivo cobre especificamente o cenário de
/// teclado — a suíte funcional (debounce, resultados, erro, navegação)
/// já existe em `dashboard_page_test.dart`, grupo "diálogo Consultar
/// patrimônio", e continua passando sem alteração.
const _largurasAndroid = [360.0, 390.0, 412.0];

/// Altura aproximada (px lógicos, dpr=1) de um teclado virtual Android.
const _alturaTecladoSimulada = 300.0;

PatrimonioDetalhe _item({
  required String id,
  required String numero,
  String tipoNome = 'Notebook',
  String setorNome = 'GETEC',
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-1',
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: tipoNome,
    setorNome: setorNome,
  );
}

void _definirTela(
  WidgetTester tester, {
  required double largura,
  double tecladoBottom = 0,
}) {
  tester.view.physicalSize = Size(largura, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: tecladoBottom);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> _pumpDialogo(
  WidgetTester tester, {
  FakePatrimonioRepository? repo,
}) async {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showConsultarPatrimonioDialog(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/patrimonios/:id',
        builder: (context, state) =>
            Scaffold(body: Text('detalhe:${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        patrimonioRepositoryProvider.overrideWithValue(
          repo ?? FakePatrimonioRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('sem teclado — comportamento original preservado', () {
    for (final largura in _largurasAndroid) {
      testWidgets('abre sem overflow em ${largura}px', (tester) async {
        _definirTela(tester, largura: largura);
        await _pumpDialogo(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Consultar patrimônio'), findsWidgets);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Fechar'), findsOneWidget);
        // Estado inicial ilustrado (ícone + mensagem, via `EmptyState`)
        // continua completo sem teclado — "recuperando-o quando houver
        // espaço".
        expect(find.byType(EmptyState), findsOneWidget);
        expect(
          find.text('Digite um número patrimonial para pesquisar.'),
          findsOneWidget,
        );
      });
    }
  });

  group('teclado aberto — sem overflow, conteúdo essencial preservado', () {
    for (final largura in _largurasAndroid) {
      testWidgets(
        'abrir com teclado simulado em ${largura}px: sem RenderFlex overflow',
        (tester) async {
          _definirTela(
            tester,
            largura: largura,
            tecladoBottom: _alturaTecladoSimulada,
          );
          await _pumpDialogo(tester);

          expect(tester.takeException(), isNull);
          // Campo de busca e botão "Fechar" continuam visíveis e
          // acessíveis mesmo com o teclado aberto.
          expect(find.byType(TextField), findsOneWidget);
          expect(find.widgetWithText(TextButton, 'Fechar'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'teclado aberto: estado vazio ilustrativo é compactado (sem ícone grande)',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        await _pumpDialogo(tester);

        expect(tester.takeException(), isNull);
        // A mensagem continua visível, só sem a ilustração grande
        // (ícone de busca) que ocupa espaço vertical desnecessário.
        expect(
          find.text('Digite um número patrimonial para pesquisar.'),
          findsOneWidget,
        );
        expect(find.byType(EmptyState), findsNothing);
      },
    );

    testWidgets(
      'fechar o teclado recupera a ilustração do estado vazio',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        await _pumpDialogo(tester);
        expect(find.byType(EmptyState), findsNothing);

        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();

        expect(find.byType(EmptyState), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'abrir e fechar o teclado repetidamente nunca produz overflow',
      (tester) async {
        _definirTela(tester, largura: 390);
        await _pumpDialogo(tester);

        for (var i = 0; i < 4; i++) {
          tester.view.viewInsets = const FakeViewPadding(
            bottom: _alturaTecladoSimulada,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'abrir teclado #$i');

          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'fechar teclado #$i');
        }
      },
    );

    testWidgets(
      'digitar e apagar um tombamento com o teclado aberto: sem overflow',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        final repo = FakePatrimonioRepository(
          itens: [_item(id: '1', numero: '3636001')],
        );
        await _pumpDialogo(tester, repo: repo);

        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('3636001'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Digite um número patrimonial para pesquisar.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'resultados com o teclado aberto: lista rolável, "Fechar" continua '
      'acessível',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        final repo = FakePatrimonioRepository(
          itens: [
            for (var i = 0; i < 6; i++)
              _item(id: '$i', numero: '36${i.toString().padLeft(2, '0')}'),
          ],
        );
        await _pumpDialogo(tester, repo: repo);

        await tester.enterText(find.byType(TextField), '36');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(TextButton, 'Fechar'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Fechar'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets(
      'sem correspondência com o teclado aberto: mensagem compacta, sem overflow',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        final repo = FakePatrimonioRepository(
          itens: [_item(id: '1', numero: '9999999')],
        );
        await _pumpDialogo(tester, repo: repo);

        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Nenhum patrimônio encontrado.'), findsOneWidget);
        expect(find.byType(EmptyState), findsNothing);
      },
    );

    testWidgets(
      'falha na consulta com o teclado aberto: "Tentar novamente" continua '
      'completo e acessível',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        final repo = FakePatrimonioRepository(erro: Exception('falha'));
        await _pumpDialogo(tester, repo: repo);

        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Não foi possível pesquisar os patrimônios.'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Tentar novamente'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tombamento alfanumérico com o teclado aberto: busca por prefixo '
      'continua funcionando',
      (tester) async {
        _definirTela(
          tester,
          largura: 390,
          tecladoBottom: _alturaTecladoSimulada,
        );
        final repo = FakePatrimonioRepository(
          itens: [_item(id: '1', numero: 'AB-3601')],
        );
        await _pumpDialogo(tester, repo: repo);

        await tester.enterText(find.byType(TextField), 'AB-36');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('AB-3601'), findsOneWidget);
      },
    );
  });
}
