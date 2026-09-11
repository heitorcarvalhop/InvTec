import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/setor.dart';
import '../setores_controller.dart';

/// Abre o formulário de criação/edição de setor. Retorna `true` se a
/// operação foi concluída com sucesso (para o chamador decidir a mensagem
/// de feedback), `false`/`null` se foi cancelado.
Future<bool?> showSetorFormDialog(BuildContext context, {Setor? setor}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => SetorFormDialog(setor: setor),
  );
}

/// Formulário único reutilizado para criar e editar — evita duplicar a
/// lógica entre desktop e mobile (section 18 do pedido): sempre um Dialog,
/// com largura máxima limitada, que se ajusta sozinho a telas estreitas.
class SetorFormDialog extends ConsumerStatefulWidget {
  const SetorFormDialog({super.key, this.setor});

  final Setor? setor;

  @override
  ConsumerState<SetorFormDialog> createState() => _SetorFormDialogState();
}

class _SetorFormDialogState extends ConsumerState<SetorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _siglaController;
  late final TextEditingController _descricaoController;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEditing => widget.setor != null;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.setor?.nome ?? '');
    _siglaController = TextEditingController(text: widget.setor?.sigla ?? '');
    _descricaoController = TextEditingController(
      text: widget.setor?.descricao ?? '',
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _siglaController.dispose();
    _descricaoController.dispose();
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
      final notifier = ref.read(setoresControllerProvider.notifier);
      if (_isEditing) {
        await notifier.atualizar(
          id: widget.setor!.id,
          nome: _nomeController.text,
          sigla: _siglaController.text,
          descricao: _descricaoController.text,
        );
      } else {
        await notifier.criar(
          nome: _nomeController.text,
          sigla: _siglaController.text,
          descricao: _descricaoController.text,
        );
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
                  _isEditing ? 'Editar setor' : 'Novo setor',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _nomeController,
                  enabled: !_isSubmitting,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o nome';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _siglaController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(labelText: 'Sigla'),
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _descricaoController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
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
