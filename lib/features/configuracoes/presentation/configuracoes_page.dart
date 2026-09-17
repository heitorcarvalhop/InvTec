import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/shell/widgets/theme_toggle_button.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/page_header.dart';

/// Configurações do InvTec (PROMPT 9.3). Por ora só a seção "Aparência" —
/// o mesmo estado de tema controlado pelo botão do header (nenhuma lógica
/// duplicada, ambos leem/escrevem [themeModeControllerProvider]).
class ConfiguracoesPage extends ConsumerWidget {
  const ConfiguracoesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InvTecPageHeader(
              title: 'Configurações',
              subtitle: 'Preferências do sistema e da sua conta.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aparência', style: AppTypography.cardTitle(context)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Escolha entre o tema claro ou escuro. A preferência fica salva '
                      'neste dispositivo e é aplicada assim que o InvTec é aberto.',
                      style: AppTypography.auxiliary(context),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Tema', style: AppTypography.label(context)),
                    const SizedBox(height: AppSpacing.sm),
                    const ThemeToggleButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
