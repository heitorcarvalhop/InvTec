import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_mode_controller.dart';

/// Alternância Claro/Escuro do header (PROMPT 9.3) — em telas largas mostra
/// as duas opções lado a lado (☀ Claro | 🌙 Escuro); em telas estreitas
/// [compact] reduz para um único ícone com tooltip. A troca aplica-se
/// imediatamente a todo o app (ver [ThemeModeController]).
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modoAsync = ref.watch(themeModeControllerProvider);
    final modo = modoAsync.value ?? ThemeMode.light;
    final notifier = ref.read(themeModeControllerProvider.notifier);

    if (compact) {
      final ehEscuro = modo == ThemeMode.dark;
      return IconButton(
        tooltip: ehEscuro ? 'Mudar para tema claro' : 'Mudar para tema escuro',
        icon: Icon(ehEscuro ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
        onPressed: notifier.alternar,
      );
    }

    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('Claro'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('Escuro'),
        ),
      ],
      selected: {modo},
      showSelectedIcon: false,
      onSelectionChanged: (selecionados) => notifier.definir(selecionados.first),
    );
  }
}
