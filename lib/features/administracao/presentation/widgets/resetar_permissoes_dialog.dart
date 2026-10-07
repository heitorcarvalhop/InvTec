import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/profile.dart';
import '../admin_usuario_detalhe_controller.dart';
import 'dialog_helpers.dart';

/// Confirmação de "Restaurar padrão do perfil" (seção 42) — remove TODAS as
/// personalizações de permissão do usuário, voltando a herdar o padrão de
/// [perfil] em todas as 14 chaves do catálogo.
class ResetarPermissoesDialog extends ConsumerStatefulWidget {
  const ResetarPermissoesDialog({super.key, required this.userId, required this.perfil});

  final String userId;
  final ProfilePerfil perfil;

  @override
  ConsumerState<ResetarPermissoesDialog> createState() => _ResetarPermissoesDialogState();
}

class _ResetarPermissoesDialogState extends ConsumerState<ResetarPermissoesDialog> {
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _confirmar() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(adminUsuarioDetalheControllerProvider(widget.userId).notifier).resetarPermissoes();
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
      title: const Text('Restaurar padrão do perfil'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Isto removerá todas as personalizações de permissão deste usuário, '
              'voltando ao padrão do perfil ${widget.perfil.label}.',
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
          child: _isSubmitting ? dialogButtonSpinner : const Text('Restaurar padrão'),
        ),
      ],
    );
  }
}
