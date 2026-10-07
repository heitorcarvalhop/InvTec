import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_chip.dart';

/// Um par rótulo/valor exibido no card de dados do usuário (Nome, E-mail,
/// CPF, Motivo, Tentativas...).
class InfoRowData {
  const InfoRowData(this.label, this.value);

  final String label;
  final String value;
}

/// Scaffold visual compartilhado pelas telas "fora do shell" de status de
/// acesso (`/acesso/pendente`, `/acesso/rejeitado`, `/acesso/bloqueado`) —
/// mesmo card centralizado da `LoginPage` (ícone de destaque + `ConstrainedBox`
/// de 380px), com um [StatusChip] no topo. Mantido como widget único para as
/// 3 telas nunca divergirem visualmente por engano.
class AcessoStatusScaffold extends StatelessWidget {
  const AcessoStatusScaffold({
    super.key,
    required this.icon,
    required this.statusLabel,
    required this.statusKind,
    required this.title,
    required this.message,
    required this.infoRows,
    required this.actions,
  });

  final IconData icon;
  final String statusLabel;
  final AppStatusKind statusKind;
  final String title;
  final String message;
  final List<InfoRowData> infoRows;

  /// Botões de ação (ex.: "Atualizar status", "Reenviar solicitação",
  /// "Sair") — cada página decide os próprios, inclusive estado de loading.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.seed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(icon, color: AppColors.seed, size: 28),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  StatusChip(label: statusLabel, kind: statusKind),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final row in infoRows) _InfoRow(row),
                          if (infoRows.isNotEmpty) const SizedBox(height: AppSpacing.md),
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.sm),
                            actions[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.data);

  final InfoRowData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              data.label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(data.value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
