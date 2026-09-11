import 'package:flutter/material.dart';

import '../../../features/auth/domain/profile.dart';
import '../../theme/app_spacing.dart';

/// Nome + perfil do usuário atual. Usado tanto no cabeçalho desktop quanto
/// no topo do drawer mobile.
class UserProfileHeader extends StatelessWidget {
  const UserProfileHeader({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(_iniciais(profile.nome)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(profile.nome, style: theme.textTheme.bodyMedium),
            Text(
              profile.perfil.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
