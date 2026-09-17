/// Escala de raio de borda do InvTec (PROMPT 9.3) — os mesmos poucos
/// valores em toda a aplicação, nunca `BorderRadius.circular(...)` com um
/// número arbitrário espalhado pelas páginas.
class AppRadius {
  AppRadius._();

  /// Controles pequenos: inputs compactos, tags.
  static const double sm = 8;

  /// Padrão de cards, dialogs, botões grandes.
  static const double md = 12;

  /// Superfícies maiores (painéis, seções destacadas).
  static const double lg = 16;

  /// Chips/badges em formato de pílula.
  static const double pill = 999;
}
