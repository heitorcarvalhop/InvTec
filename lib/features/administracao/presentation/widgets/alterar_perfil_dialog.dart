import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/profile.dart';
import '../admin_usuario_detalhe_controller.dart';
import 'confirmar_perfil_admin_dialog.dart';
import 'dialog_helpers.dart';

/// Diálogo "Alterar perfil" (seção 33) de um usuário já ACTIVE — perfil
/// atual pré-selecionado. Selecionar ADMIN exige a mesma confirmação
/// reforçada usada na aprovação.
class AlterarPerfilDialog extends ConsumerStatefulWidget {
  const AlterarPerfilDialog({super.key, required this.userId, required this.perfilAtual});

  final String userId;
  final ProfilePerfil perfilAtual;

  @override
  ConsumerState<AlterarPerfilDialog> createState() => _AlterarPerfilDialogState();
}

class _AlterarPerfilDialogState extends ConsumerState<AlterarPerfilDialog> {
  late ProfilePerfil _perfil;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _perfil = widget.perfilAtual;
  }

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
      await ref.read(adminUsuarioDetalheControllerProvider(widget.userId).notifier).alterarPerfil(_perfil);
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
      title: const Text('Alterar perfil'),
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
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Permissões personalizadas serão preservadas.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
          child: _isSubmitting ? dialogButtonSpinner : const Text('Salvar'),
        ),
      ],
    );
  }
}
