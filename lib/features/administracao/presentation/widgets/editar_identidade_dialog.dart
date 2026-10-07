import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/profile.dart';
import '../../../auth/domain/signup_validators.dart';
import '../admin_usuario_detalhe_controller.dart';
import 'admin_usuario_formatters.dart';
import 'dialog_helpers.dart';

/// Diálogo "Editar identidade" (seção 35) — corrige nome/CPF de outro
/// usuário. Reaproveita os validators PUROS de `signup_validators.dart`
/// (feature `auth`, só funções sem widget) para não duplicar a regex de CPF
/// nem a validação de nome. O e-mail aparece como texto fixo, nunca
/// editável — alterações de e-mail são tratadas por fora deste fluxo.
class EditarIdentidadeDialog extends ConsumerStatefulWidget {
  const EditarIdentidadeDialog({super.key, required this.usuario});

  final Profile usuario;

  @override
  ConsumerState<EditarIdentidadeDialog> createState() => _EditarIdentidadeDialogState();
}

class _EditarIdentidadeDialogState extends ConsumerState<EditarIdentidadeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _cpfController;
  final _motivoController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.usuario.nome);
    final cpf = widget.usuario.cpf;
    _cpfController = TextEditingController(text: cpf == null ? '' : formatarCpfCompleto(cpf));
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final cpfDigitos = _cpfController.text.replaceAll(RegExp(r'[^0-9]'), '');

    try {
      await ref
          .read(adminUsuarioDetalheControllerProvider(widget.usuario.id).notifier)
          .alterarIdentidade(
            nome: _nomeController.text.trim(),
            cpf: cpfDigitos,
            motivo: _motivoController.text.trim(),
          );
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
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Editar identidade', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    initialValue: widget.usuario.email ?? 'Não informado',
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Alterações de e-mail serão realizadas por solicitação.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _nomeController,
                    enabled: !_isSubmitting,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nome *'),
                    textInputAction: TextInputAction.next,
                    validator: validarNome,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _cpfController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(labelText: 'CPF *'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    validator: validarCpf,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _motivoController,
                    enabled: !_isSubmitting,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Motivo da alteração *'),
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Informe o motivo da alteração.' : null,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    buildErroInlineDialog(context, _errorMessage!),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _confirmar,
                        child: _isSubmitting ? dialogButtonSpinner : const Text('Salvar'),
                      ),
                    ],
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
