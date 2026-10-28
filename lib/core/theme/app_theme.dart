import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';

/// Temas claro e escuro do InvTec.
///
/// Identidade visual corporativa moderna: azul como accent principal
/// (nunca a cor de tudo), cards com bordas discretas, sem gradientes ou
/// efeitos chamativos. A troca entre [light]/[dark] é controlada pelo
/// usuário e persistida localmente — ver
/// `lib/core/theme/theme_mode_controller.dart` e `lib/app/app.dart`.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _base(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.light,
    ),
    statusColors: AppStatusColors.light,
    surfaceColors: AppSurfaceColors.light,
    dataVizColors: AppDataVizColors.light,
  );

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.dark,
    );
    return _base(
      colorScheme: colorScheme,
      statusColors: AppStatusColors.dark,
      surfaceColors: AppSurfaceColors.fromDarkColorScheme(colorScheme),
      dataVizColors: AppDataVizColors.dark,
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required AppStatusColors statusColors,
    required AppSurfaceColors surfaceColors,
    required AppDataVizColors dataVizColors,
  }) {
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);
    final textTheme = _textTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme,
      // Fundo levemente afastado das superfícies "acima" dele (cards,
      // sidebar, appbar) — sem preto/branco absoluto em nenhum dos dois
      // temas, e sem o viés lilás da família `surfaceContainer*` gerada
      // por `fromSeed` no tema claro — ver [AppSurfaceColors].
      scaffoldBackgroundColor: surfaceColors.pageBackground,
      extensions: [statusColors, surfaceColors, dataVizColors],
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: surfaceColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        // Mesma cor do fundo da página: a topbar não deve parecer uma
        // segunda barra empilhada sobre a sidebar.
        backgroundColor: surfaceColors.pageBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
        titleTextStyle: textTheme.titleLarge,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: surfaceColors.surface,
      ),
      // Barra inferior (só montada no celular — ver AppShell): rótulos
      // sempre visíveis e altura confortável para o polegar.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColors.surface,
        elevation: 0,
        height: 64,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColors.surfaceElevated,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: surfaceColors.border),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        filled: true,
        fillColor: surfaceColors.input,
        // Campos mais altos que o padrão denso: alvo de toque >= 48dp.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: BorderSide.none,
        labelStyle: textTheme.labelMedium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        // Margem lateral menor que o padrão (40): em 360 px o diálogo ganha
        // ~48 px de largura útil. Desktop não muda (diálogos têm maxWidth).
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 24,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  /// Ajustes discretos de peso/espaçamento sobre o `TextTheme` padrão do
  /// Material 3 — nunca uma fonte customizada (não há necessidade visual
  /// para isso), só uma hierarquia mais nítida entre título/corpo/legenda.
  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
