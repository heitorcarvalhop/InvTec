import 'package:flutter/material.dart';

/// Hierarquia tipográfica do InvTec (PROMPT 9.3) — nomes semânticos por
/// função ("título de página", "métrica"...), nunca por tamanho, para que
/// o mesmo papel visual seja sempre usado do mesmo jeito em toda a
/// aplicação. Todos os estilos derivam de `Theme.of(context).textTheme`
/// (que já reflete o tema claro/escuro atual) — nunca um `TextStyle` fixo
/// desacoplado do tema.
class AppTypography {
  AppTypography._();

  /// Título principal de uma página (ex.: "Patrimônios", "Dashboard").
  static TextStyle? pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);

  /// Linha de apoio logo abaixo do título da página.
  static TextStyle? pageSubtitle(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  /// Título de um card/seção dentro da página.
  static TextStyle? cardTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

  /// Número em destaque (ex.: cards de estatística do dashboard).
  static TextStyle? metric(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700);

  /// Rótulo curto (ex.: label de campo, cabeçalho de coluna de tabela).
  static TextStyle? label(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);

  /// Texto de conteúdo padrão (corpo de tabela, texto de card).
  static TextStyle? body(BuildContext context) => Theme.of(context).textTheme.bodyMedium;

  /// Texto auxiliar, discreto (ex.: setor/gerência abaixo da localização).
  static TextStyle? auxiliary(BuildContext context) => Theme.of(
    context,
  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  /// Legenda pequena (ex.: rodapé de tabela, data discreta).
  static TextStyle? caption(BuildContext context) => Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
}
