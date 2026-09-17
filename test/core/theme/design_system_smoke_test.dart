import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/core/widgets/page_header.dart';
import 'package:invtec/core/widgets/stat_card.dart';
import 'package:invtec/core/widgets/status_chip.dart';

/// Componentes principais do design system (PROMPT 9.3) renderizando sem
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
  }
}
