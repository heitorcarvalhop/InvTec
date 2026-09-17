import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/localizacao.dart';
import '../localizacoes_controller.dart';

/// Formulário de criação/edição de localização — nunca mostra/edita
/// `setorId` (imutável depois de criada, seção 5 da especificação; o
/// próprio banco rejeita a tentativa).
Future<bool?> showLocalizacaoFormDialog(
  BuildContext context, {
  required String setorId,
  Localizacao? localizacao,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => LocalizacaoFormDialog(setorId: setorId, localizacao: localizacao),
  );
}

class LocalizacaoFormDialog extends ConsumerStatefulWidget {
  const LocalizacaoFormDialog({super.key, required this.setorId, this.localizacao});

  final String setorId;
  final Localizacao? localizacao;

  @override
  ConsumerState<LocalizacaoFormDialog> createState() => _LocalizacaoFormDialogState();
}

class _LocalizacaoFormDialogState extends ConsumerState<LocalizacaoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _siglaController;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.localizacao != null;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.localizacao?.nome ?? '');
    _siglaController = TextEditingController(text: widget.localizacao?.sigla ?? '');
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _siglaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(localizacoesControllerProvider(widget.setorId).notifier);
      if (_isEditing) {
        await notifier.atualizar(
          id: widget.localizacao!.id,
          nome: _nomeController.text,
          sigla: _siglaController.text,
        );
      } else {
        await notifier.criar(nome: _nomeController.text, sigla: _siglaController.text);
      }
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditing ? 'Editar localização' : 'Nova localização',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _nomeController,
                  enabled: !_isSubmitting,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Informe o nome' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _siglaController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(labelText: 'Sigla'),
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
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
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEditing ? 'Salvar' : 'Cadastrar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
