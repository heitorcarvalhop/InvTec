import 'package:flutter/material.dart';

/// Cor de marca do InvTec — azul moderno usado para ação primária,
/// navegação ativa, links, foco e seleção (PROMPT 9.3). Toda a
/// `ColorScheme` (claro/escuro) é derivada dela via `ColorScheme.fromSeed`
/// em [AppTheme] — nunca usar esta cor ou qualquer outra diretamente numa
/// página; sempre passar por `Theme.of(context).colorScheme`.
class AppColors {
  AppColors._();

  static const Color seed = Color(0xFF2563EB);

  /// A sidebar mantém a MESMA identidade (azul-marinho escuro) nos dois
  /// temas — PROMPT 9.3: "sidebar pode permanecer escura para reforçar
  /// identidade" mesmo no tema claro. Não deriva de [ColorScheme]/brilho
  /// de propósito: é um elemento de marca fixo, não uma superfície comum.
  static const Color sidebarBackground = Color(0xFF0B1727);
  static const Color sidebarSurfaceHover = Color(0xFF13233A);
  static const Color sidebarSelectedBackground = Color(0xFF1D3A66);
  static const Color sidebarSelectedForeground = Color(0xFF93C5FD);
  static const Color sidebarForeground = Color(0xFFE2E8F0);
  static const Color sidebarForegroundMuted = Color(0xFF94A3B8);
  static const Color sidebarBorder = Color(0xFF1E2D42);
}

/// Cores semânticas de estado (sucesso/atenção/erro/informação/neutro —
/// PROMPT 9.3), com contraste adequado tanto no tema claro quanto no
/// escuro. Cada estado tem um par (fundo, texto/ícone) pensado para uso em
/// chips/badges e destaques pontuais — nunca a área inteira de uma tela.
///
/// Registrada como [ThemeExtension] em [AppTheme] para que `Theme.of` já
/// resolva automaticamente a variante certa por brilho, em vez de cada
/// widget decidir "estou no escuro?" na mão.
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.successBackground,
    required this.successForeground,
    required this.warningBackground,
    required this.warningForeground,
    required this.errorBackground,
    required this.errorForeground,
    required this.infoBackground,
    required this.infoForeground,
    required this.neutralBackground,
    required this.neutralForeground,
  });

  final Color successBackground;
  final Color successForeground;
  final Color warningBackground;
  final Color warningForeground;
  final Color errorBackground;
  final Color errorForeground;
  final Color infoBackground;
  final Color infoForeground;
  final Color neutralBackground;
  final Color neutralForeground;

  static const light = AppStatusColors(
    successBackground: Color(0xFFDCFCE7),
    successForeground: Color(0xFF15803D),
    warningBackground: Color(0xFFFEF3C7),
    warningForeground: Color(0xFFB45309),
    errorBackground: Color(0xFFFEE2E2),
    errorForeground: Color(0xFFB91C1C),
    infoBackground: Color(0xFFDBEAFE),
    infoForeground: Color(0xFF1D4ED8),
    neutralBackground: Color(0xFFF1F5F9),
    neutralForeground: Color(0xFF475569),
  );

  static const dark = AppStatusColors(
    successBackground: Color(0xFF15321F),
    successForeground: Color(0xFF4ADE80),
    warningBackground: Color(0xFF3A2A0B),
    warningForeground: Color(0xFFFBBF24),
    errorBackground: Color(0xFF3B1414),
    errorForeground: Color(0xFFF87171),
    infoBackground: Color(0xFF16264A),
    infoForeground: Color(0xFF60A5FA),
    neutralBackground: Color(0xFF283040),
    neutralForeground: Color(0xFFCBD5E1),
  );

  @override
  AppStatusColors copyWith({
    Color? successBackground,
    Color? successForeground,
    Color? warningBackground,
    Color? warningForeground,
    Color? errorBackground,
    Color? errorForeground,
    Color? infoBackground,
    Color? infoForeground,
    Color? neutralBackground,
    Color? neutralForeground,
  }) {
    return AppStatusColors(
      successBackground: successBackground ?? this.successBackground,
      successForeground: successForeground ?? this.successForeground,
      warningBackground: warningBackground ?? this.warningBackground,
      warningForeground: warningForeground ?? this.warningForeground,
      errorBackground: errorBackground ?? this.errorBackground,
      errorForeground: errorForeground ?? this.errorForeground,
      infoBackground: infoBackground ?? this.infoBackground,
      infoForeground: infoForeground ?? this.infoForeground,
      neutralBackground: neutralBackground ?? this.neutralBackground,
      neutralForeground: neutralForeground ?? this.neutralForeground,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      successBackground: Color.lerp(successBackground, other.successBackground, t)!,
      successForeground: Color.lerp(successForeground, other.successForeground, t)!,
      warningBackground: Color.lerp(warningBackground, other.warningBackground, t)!,
      warningForeground: Color.lerp(warningForeground, other.warningForeground, t)!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
      errorForeground: Color.lerp(errorForeground, other.errorForeground, t)!,
      infoBackground: Color.lerp(infoBackground, other.infoBackground, t)!,
      infoForeground: Color.lerp(infoForeground, other.infoForeground, t)!,
      neutralBackground: Color.lerp(neutralBackground, other.neutralBackground, t)!,
      neutralForeground: Color.lerp(neutralForeground, other.neutralForeground, t)!,
    );
  }
}

/// Acesso curto: `Theme.of(context).statusColors`.
extension AppStatusColorsContext on ThemeData {
  AppStatusColors get statusColors =>
      extension<AppStatusColors>() ?? AppStatusColors.light;
}

/// Camadas de superfície (PROMPT 9.3.3) — fundo da página, cards, cabeçalho
/// de tabela, hover de linha e borda, todas nomeadas explicitamente em vez
/// de reaproveitar a família `surfaceContainer*` da `ColorScheme` gerada
/// por `ColorScheme.fromSeed`.
///
/// Motivo: o algoritmo tonal do Material 3 (HCT) tinge levemente os tons
/// neutros com o matiz da cor semente — com um azul como semente, isso
/// produz um cinza com viés lilás perceptível no tema claro (relatado nos
/// screenshots do PROMPT 9.3.3). [light] usa valores neutros
/// escolhidos à mão (cinza-azulado discreto, nunca lilás). [dark] continua
/// derivado da `ColorScheme` do tema escuro — a direção do tema escuro já
/// estava aprovada; aqui só nomeamos papéis que antes eram implícitos
/// (cabeçalho de tabela e hover de linha usavam a mesma cor do card, sem
/// distinção).
class AppSurfaceColors extends ThemeExtension<AppSurfaceColors> {
  const AppSurfaceColors({
    required this.pageBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.input,
    required this.tableHeader,
    required this.rowHover,
    required this.border,
  });

  final Color pageBackground;
  final Color surface;
  final Color surfaceElevated;
  final Color input;
  final Color tableHeader;
  final Color rowHover;
  final Color border;

  static const light = AppSurfaceColors(
    pageBackground: Color(0xFFF3F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    input: Color(0xFFFFFFFF),
    tableHeader: Color(0xFFEEF2F7),
    rowHover: Color(0xFFF4F7FB),
    border: Color(0xFFE2E8F0),
  );

  factory AppSurfaceColors.fromDarkColorScheme(ColorScheme colorScheme) {
    return AppSurfaceColors(
      pageBackground: colorScheme.surfaceContainerLowest,
      surface: colorScheme.surfaceContainer,
      surfaceElevated: colorScheme.surfaceContainerHigh,
      input: colorScheme.surfaceContainerHigh,
      tableHeader: colorScheme.surfaceContainerHigh,
      rowHover: colorScheme.surfaceContainerHighest,
      border: colorScheme.outlineVariant,
    );
  }

  @override
  AppSurfaceColors copyWith({
    Color? pageBackground,
    Color? surface,
    Color? surfaceElevated,
    Color? input,
    Color? tableHeader,
    Color? rowHover,
    Color? border,
  }) {
    return AppSurfaceColors(
      pageBackground: pageBackground ?? this.pageBackground,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      input: input ?? this.input,
      tableHeader: tableHeader ?? this.tableHeader,
      rowHover: rowHover ?? this.rowHover,
      border: border ?? this.border,
    );
  }

  @override
  AppSurfaceColors lerp(ThemeExtension<AppSurfaceColors>? other, double t) {
    if (other is! AppSurfaceColors) return this;
    return AppSurfaceColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      input: Color.lerp(input, other.input, t)!,
      tableHeader: Color.lerp(tableHeader, other.tableHeader, t)!,
      rowHover: Color.lerp(rowHover, other.rowHover, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

/// Acesso curto: `Theme.of(context).surfaceColors`.
extension AppSurfaceColorsContext on ThemeData {
  AppSurfaceColors get surfaceColors =>
      extension<AppSurfaceColors>() ?? AppSurfaceColors.light;
}
