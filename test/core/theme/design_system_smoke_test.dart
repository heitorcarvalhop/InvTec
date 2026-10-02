import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/theme/app_colors.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/core/theme/app_typography.dart';
import 'package:invtec/core/widgets/page_header.dart';
import 'package:invtec/core/widgets/stat_card.dart';
import 'package:invtec/core/widgets/status_chip.dart';

/// Componentes principais do design system renderizando sem
/// erro nos dois temas — não valida pixel a pixel, só que o widget
/// constrói normalmente sob `AppTheme.light`/`AppTheme.dark`.
void main() {
  for (final tema in [
    ('claro', AppTheme.light),
    ('escuro', AppTheme.dark),
  ]) {
    final (nome, themeData) = tema;

    testWidgets('StatusChip renderiza no tema $nome', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeData,
          home: const Scaffold(
            body: Column(
              children: [
                StatusChip(label: 'Disponível', kind: AppStatusKind.success),
                StatusChip(label: 'Em manutenção', kind: AppStatusKind.warning),
                StatusChip(label: 'Baixado', kind: AppStatusKind.neutral),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Disponível'), findsOneWidget);
      expect(find.text('Em manutenção'), findsOneWidget);
      expect(find.text('Baixado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('InvTecStatCard renderiza no tema $nome', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeData,
          home: const Scaffold(
            body: InvTecStatCard(
              label: 'Total de patrimônios',
              value: 1744,
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ),
      );

      expect(find.text('1744'), findsOneWidget);
      expect(find.text('Total de patrimônios'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('InvTecPageHeader renderiza no tema $nome', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeData,
          home: Scaffold(
            body: InvTecPageHeader(
              title: 'Patrimônios',
              subtitle: 'Consulte e gerencie os equipamentos cadastrados no InvTec.',
              actions: [FilledButton(onPressed: () {}, child: const Text('Novo patrimônio'))],
            ),
          ),
        ),
      );

      expect(find.text('Patrimônios'), findsOneWidget);
      expect(find.text('Novo patrimônio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('AppDataVizColors está registrado no tema $nome e com cores não-nulas', () {
      final dataViz = themeData.dataVizColors;
      expect(dataViz.cyan, isNotNull);
      expect(dataViz.teal, isNotNull);
      expect(dataViz.emerald, isNotNull);
      // As três cores precisam ser distintas entre si (senão o acento
      // "decorativo" vira uma única cor disfarçada de três tokens).
      expect({dataViz.cyan, dataViz.teal, dataViz.emerald}, hasLength(3));
    });

    testWidgets('AppTypography.eyebrow resolve um TextStyle válido no tema $nome', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: themeData,
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final style = AppTypography.eyebrow(capturedContext);
      expect(style, isNotNull);
      expect(style!.letterSpacing, greaterThan(1));
      expect(tester.takeException(), isNull);
    });
  }
}
