import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Volta para a rota anterior do stack quando existe uma (`context.pop()`);
/// caso contrário navega para [fallback] — a página-pai lógica da
/// hierarquia real da aplicação, nunca uma rota arbitrária. Necessário
/// porque uma página pode ter sido aberta via `context.go()`, que não
/// deixa nada no stack (`canPop()` retornaria `false`).
void backOrGo(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
