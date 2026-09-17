import 'package:flutter/material.dart';

import '../../../features/auth/domain/profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Nome + perfil do usuário atual. Usado tanto no cabeçalho desktop
/// (superfície normal, [onDarkSurface] = false) quanto no topo do drawer
/// mobile (fundo azul-marinho da navegação, [onDarkSurface] = true —
/// PROMPT 9.3).
class UserProfileHeader extends StatelessWidget {
  const UserProfileHeader({super.key, required this.profile, this.onDarkSurface = false});

  final Profile profile;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameColor = onDarkSurface ? AppColors.sidebarForeground : theme.colorScheme.onSurface;
    final roleColor = onDarkSurface ? AppColors.sidebarForegroundMuted : theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          backgroundColor: onDarkSurface ? AppColors.sidebarSelectedBackground : theme.colorScheme.primaryContainer,
          foregroundColor: onDarkSurface ? AppColors.sidebarSelectedForeground : theme.colorScheme.onPrimaryContainer,
          child: Text(_iniciais(profile.nome)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(profile.nome, style: theme.textTheme.bodyMedium?.copyWith(color: nameColor)),
            Text(profile.perfil.label, style: theme.textTheme.bodySmall?.copyWith(color: roleColor)),
          ],
        ),
      ],
    );
  }
}

String _iniciais(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letras = partes.take(2).map((p) => p[0].toUpperCase());
  return letras.isEmpty ? '?' : letras.join();
}
