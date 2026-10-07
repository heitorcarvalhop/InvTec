import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/profile.dart';
import '../admin_usuario_detalhe_controller.dart';
import 'confirmar_perfil_admin_dialog.dart';
import 'dialog_helpers.dart';

/// Diálogo "Aprovar acesso" (seção 29) — perfil inicial sempre CONSULTA
/// (nunca pré-seleciona ADMIN). Selecionar ADMIN exige a confirmação
/// reforçada de [showConfirmarPerfilAdminDialog] antes de chamar
/// `AdminUsuarioDetalheController.aprovar`.
class AprovarUsuarioDialog extends ConsumerStatefulWidget {
  const AprovarUsuarioDialog({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<AprovarUsuarioDialog> createState() => _AprovarUsuarioDialogState();
}

class _AprovarUsuarioDialogState extends ConsumerState<AprovarUsuarioDialog> {
  ProfilePerfil _perfil = ProfilePerfil.consulta;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _confirmar() async {
    if (_isSubmitting) return;

    if (_perfil == ProfilePerfil.admin) {
      final confirmouAdmin = await showConfirmarPerfilAdminDialog(context);
      if (!confirmouAdmin || !mounted) return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(adminUsuarioDetalheControllerProvider(widget.userId).notifier).aprovar(_perfil);
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
      title: const Text('Aprovar acesso'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<ProfilePerfil>(
              initialValue: _perfil,
              decoration: const InputDecoration(labelText: 'Perfil'),
              items: [
                for (final perfil in ProfilePerfil.values)
                  DropdownMenuItem(value: perfil, child: Text(perfil.label)),
              ],
              onChanged: _isSubmitting ? null : (perfil) => setState(() => _perfil = perfil!),
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
          child: _isSubmitting ? dialogButtonSpinner : const Text('Aprovar acesso'),
        ),
      ],
    );
  }
}
