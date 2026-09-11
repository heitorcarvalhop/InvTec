import 'package:flutter/material.dart';

import '../../domain/setor.dart';

/// Confirmação antes de desativar — a única ação desta tela destrutiva o
/// bastante para pedir confirmação (editar/reativar não pedem).
Future<bool> confirmarDesativacao(BuildContext context, Setor setor) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Desativar setor?'),
      content: Text(
        'O setor "${setor.nome}" continuará aparecendo no histórico, mas '
        'não poderá ser utilizado como destino de novas movimentações.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Desativar'),
        ),
      ],
    ),
  );
  return result ?? false;
}
