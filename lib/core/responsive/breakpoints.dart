import 'package:flutter/widgets.dart';

/// Tamanhos de tela do InvTec, usados para decidir layout (sidebar fixa vs.
/// drawer) e evitar overflow em conteúdo que não reage só a
/// `Platform.isWindows`/`Platform.isAndroid` — a mesma janela do Windows
/// pode ser redimensionada para qualquer largura.
enum ScreenSize { mobile, tablet, desktop }

class Breakpoints {
  Breakpoints._();

  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  static ScreenSize of(double width) {
    if (width < mobileMax) return ScreenSize.mobile;
    if (width < tabletMax) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }
}

extension BreakpointsContext on BuildContext {
  ScreenSize get screenSize =>
      Breakpoints.of(MediaQuery.sizeOf(this).width);

  /// Sidebar fixa (tablet/desktop) em vez de Drawer sob demanda (mobile).
  bool get usesPermanentSidebar => screenSize != ScreenSize.mobile;
}
