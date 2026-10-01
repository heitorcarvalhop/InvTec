import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/shell/navigation_items.dart';
import 'package:invtec/core/shell/widgets/navigation_sidebar.dart';
import 'package:invtec/features/auth/domain/profile.dart';

/// PROMPT 11.3.9.1 — reproduz o `BOTTOM OVERFLOWED BY 71 PIXELS` do vídeo:
/// em janelas BAIXAS, o `Column` da sidebar tinha um bloco fixo no fim
/// ("Configurações"/"Sair") que nunca rolava — só a lista do meio rolava.
/// Quando a altura ficava curta demais mesmo com a lista colapsada a zero,
/// o `Column` estourava por baixo, e "Configurações"/"Sair" ficavam
/// inacessíveis (não só visualmente cortados: sem nenhum jeito de rolar até
/// eles). Nenhum handler customizado de `FlutterError.onError` é necessário
/// aqui: o `flutter_test` já falha o teste sozinho quando um
/// `RenderFlex overflowed` não é tratado — customizar o handler só é
/// necessário quando se precisa CONTINUAR interagindo depois do erro (não é
/// o caso destes testes).
void main() {
  Future<void> pumpSidebar(WidgetTester tester, Size tamanho) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationSidebar(
            currentRoute: '/movimentacoes',
            items: navigationItemsFor(ProfilePerfil.admin),
            onNavigate: (_) {},
            onLogout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('PROMPT 11.3.9.1 — NavigationSidebar nunca estoura, mesmo em janelas baixas', () {
    // As 4 resoluções pedidas na seção 6 (360x640 usa o Drawer mobile, não
    // esta sidebar — ver `Breakpoints.mobileMax`) + uma altura bem mais
    // curta, plausível durante um redimensionamento manual da janela (o
    // cenário que o vídeo mostrou), para exercitar de fato o overflow que
    // as 4 resoluções "oficiais" — todas com altura >= 600 — não alcançam.
    for (final tamanho in [
      const Size(1920, 1080),
      const Size(1280, 720),
      const Size(800, 600),
      const Size(1024, 150),
    ]) {
      testWidgets('em ${tamanho.width.toInt()}x${tamanho.height.toInt()}: sem overflow, e "Sair" fica acessível '
          'após rolar', (tester) async {
        await pumpSidebar(tester, tamanho);

        // "Sair" precisa ficar ACESSÍVEL — rola até ele em vez de só
        // procurar o widget na árvore (que existiria mesmo cortado).
        await tester.dragUntilVisible(find.text('Sair'), find.byType(Scrollable).first, const Offset(0, -50));
        await tester.pumpAndSettle();
        expect(find.text('Sair'), findsOneWidget);

        final posicao = tester.getBottomRight(find.text('Sair'));
        expect(posicao.dy, lessThanOrEqualTo(tamanho.height), reason: '"Sair" precisa estar dentro da viewport visível');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('em altura confortável (1080px), nada precisa rolar e tudo já está visível', (tester) async {
      await pumpSidebar(tester, const Size(1024, 1080));

      expect(find.text('Movimentações'), findsOneWidget);
      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
    });
  });
}
