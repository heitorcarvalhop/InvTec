import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Segunda confirmação, reforçada, exigida sempre que um ADMIN está prestes
/// a conceder perfil ADMIN a outro usuário — tanto na aprovação (seção 29)
/// quanto na troca de perfil de um usuário já ativo (seção 33). Nunca um
/// "Confirmar" genérico: o botão positivo nomeia explicitamente a
/// consequência ("Conceder acesso de administrador").
Future<bool> showConfirmarPerfilAdminDialog(BuildContext context) async {
  final colorScheme = Theme.of(context).colorScheme;
  final resultado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 22),
          const SizedBox(width: AppSpacing.sm),
          const Flexible(child: Text('Confirmar acesso administrativo')),
        ],
      ),
      content: const Text('Este usuário terá acesso administrativo ao InvTec.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Conceder acesso de administrador'),
        ),
      ],
    ),
  );
  return resultado ?? false;
}
