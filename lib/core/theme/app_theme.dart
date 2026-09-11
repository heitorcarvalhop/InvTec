import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// Temas claro e escuro do InvTec.
///
/// Identidade visual corporativa: tons de azul/petróleo, cards com bordas
/// suaves, sem gradientes ou efeitos chamativos. Por enquanto segue o tema
/// do sistema (`ThemeMode.system`, ver [lib/app/app.dart]).
class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF0F5C8C);

  static ThemeData get light => _base(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
      );

  static ThemeData get dark => _base(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _base({required ColorScheme colorScheme}) {
    final base = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    return base.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surface,
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
      ),
    );
  }
}
