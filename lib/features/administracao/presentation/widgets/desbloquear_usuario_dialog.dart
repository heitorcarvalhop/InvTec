import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../admin_usuario_detalhe_controller.dart';
import 'dialog_helpers.dart';

/// Diálogo "Desbloquear" (seção 31) — explica o RESULTADO antes de
/// confirmar, já que a RPC decide ACTIVE ou PENDING de formas diferentes
/// dependendo de `approvedAt`: quem já foi aprovado alguma vez volta a
/// ACTIVE; quem nunca foi aprovado volta a PENDING com o contador de
/// rejeições zerado.
class DesbloquearUsuarioDialog extends ConsumerStatefulWidget {
  const DesbloquearUsuarioDialog({super.key, required this.userId, required this.jaFoiAprovado});

  final String userId;
  final bool jaFoiAprovado;

  @override
  ConsumerState<DesbloquearUsuarioDialog> createState() => _DesbloquearUsuarioDialogState();
}

class _DesbloquearUsuarioDialogState extends ConsumerState<DesbloquearUsuarioDialog> {
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _confirmar() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(adminUsuarioDetalheControllerProvider(widget.userId).notifier).desbloquear();
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Desbloquear usuário'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.jaFoiAprovado
                  ? 'Este usuário já foi aprovado antes — ao desbloquear, voltará para Ativo.'
                  : 'Este usuário nunca foi aprovado — ao desbloquear, voltará para Pendente '
                        'com o contador de rejeições zerado.',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              buildErroInlineDialog(context, _errorMessage!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _confirmar,
          child: _isSubmitting ? dialogButtonSpinner : const Text('Desbloquear'),
        ),
      ],
    );
  }
}
