import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import 'dialog_helpers.dart';

/// Diálogo genérico de "ação com motivo obrigatório" — reaproveitado por
/// Rejeitar solicitação (seção 30) e Bloquear acesso (seção 32): mesma
/// validação (motivo não pode ser vazio), mesmo diálogo de erro inline,
/// mesmo botão destrutivo; só o título/rótulo do botão/aviso extra e a
/// AÇÃO final (passada via [onConfirmar]) mudam entre os dois usos — evita
/// duplicar o formulário duas vezes.
///
/// Segue o mesmo padrão de `SetorFormDialog`: a própria ação de escrita é
/// chamada DAQUI (não delegada a quem abriu o diálogo), com erro tratado
/// inline e o diálogo permanecendo aberto em caso de falha para o ADMIN
/// corrigir e tentar de novo.
class MotivoActionDialog extends ConsumerStatefulWidget {
  const MotivoActionDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.onConfirmar,
    this.aviso,
    this.destructive = true,
  });

  final String title;
  final String confirmLabel;

  /// Executa a ação real (chama o método certo do controller) — lança
  /// `AppException`/outro erro normalmente, que este diálogo já trata.
  final Future<void> Function(WidgetRef ref, String motivo) onConfirmar;

  /// Conteúdo extra acima do campo de motivo (ex.: contagem de rejeições).
  final Widget? aviso;
  final bool destructive;

  @override
  ConsumerState<MotivoActionDialog> createState() => _MotivoActionDialogState();
}

class _MotivoActionDialogState extends ConsumerState<MotivoActionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _motivoController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
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

    try {
      await widget.onConfirmar(ref, _motivoController.text.trim());
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
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.aviso != null) ...[widget.aviso!, const SizedBox(height: AppSpacing.md)],
              TextFormField(
                controller: _motivoController,
                enabled: !_isSubmitting,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Motivo *'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Informe o motivo.' : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                buildErroInlineDialog(context, _errorMessage!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError)
              : null,
          onPressed: _isSubmitting ? null : _confirmar,
          child: _isSubmitting ? dialogButtonSpinner : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
