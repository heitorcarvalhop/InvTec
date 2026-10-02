import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/compact_icon_button.dart';

/// Cobre a garantia central do [CompactIconButton]: shape circular (nunca
/// retangular) e área de toque compacta — o defeito real que motivou este
/// widget era um destaque de hover/focus/splash com cantos retos nos
/// controles de ordenação (ver prompt "Refinamento da área clicável dos
/// controles compactos").
void main() {
  ButtonStyle? resolveStyle(WidgetTester tester) =>
      tester.widget<IconButton>(find.byType(IconButton)).style;

  testWidgets('shape resolvido é circular, nunca retangular', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactIconButton(icon: const Icon(Icons.arrow_upward), onPressed: () {}),
        ),
      ),
    );

    final shape = resolveStyle(tester)?.shape?.resolve({});
    expect(shape, isA<CircleBorder>(), reason: 'destaque de hover/focus/splash deve ser um círculo');
  });

  testWidgets('área de toque é compacta (32x32), nunca o padrão de 48x48', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactIconButton(icon: const Icon(Icons.close), onPressed: () {}),
        ),
      ),
    );

    final tamanho = tester.getSize(find.byType(IconButton));
    expect(tamanho, const Size(32, 32));
  });

  testWidgets('tooltip aparece quando informado', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactIconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Fechar aviso',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Fechar aviso'), findsOneWidget);
  });

  testWidgets('aciona onPressed ao tocar, e fica desabilitado quando onPressed é null', (
    tester,
  ) async {
    var cliques = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactIconButton(icon: const Icon(Icons.add), onPressed: () => cliques++),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    expect(cliques, 1);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CompactIconButton(icon: Icon(Icons.add), onPressed: null)),
      ),
    );
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });

  testWidgets('respeita iconSize e color quando informados', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactIconButton(
            icon: const Icon(Icons.arrow_downward),
            iconSize: 18,
            color: Colors.red,
            onPressed: () {},
          ),
        ),
      ),
    );

    final botao = tester.widget<IconButton>(find.byType(IconButton));
    expect(botao.iconSize, 18);
    expect(botao.color, Colors.red);
  });
}
