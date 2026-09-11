import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/patrimonio.dart';
import '../../domain/patrimonio_detalhe.dart';
import '../../domain/tipo_patrimonio.dart';
import '../patrimonio_detalhe_providers.dart';
import '../patrimonio_reference_data.dart';
import '../patrimonios_controller.dart';
import 'date_only_field.dart';

/// Edição de metadados — nunca número/status/setor/responsável (esses só
/// mudam por movimentação registrada, ver docs/database.md). Retorna
/// `true` quando a edição é concluída com sucesso.
Future<bool?> showPatrimonioEditDialog(
  BuildContext context, {
  required PatrimonioDetalhe detalhe,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => PatrimonioEditDialog(detalhe: detalhe),
  );
}

class PatrimonioEditDialog extends ConsumerStatefulWidget {
  const PatrimonioEditDialog({super.key, required this.detalhe});

  final PatrimonioDetalhe detalhe;

  @override
  ConsumerState<PatrimonioEditDialog> createState() =>
      _PatrimonioEditDialogState();
}

class _PatrimonioEditDialogState extends ConsumerState<PatrimonioEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numeroController;
  late final TextEditingController _serieController;
  late final TextEditingController _marcaController;
  late final TextEditingController _modeloController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _observacaoController;

  DateTime? _dataAquisicao;
  late String _tipoId;
  bool _isSubmitting = false;
  String? _errorMessage;

  Patrimonio get _patrimonio => widget.detalhe.patrimonio;

  @override
  void initState() {
    super.initState();
    _numeroController = TextEditingController(
      text: _patrimonio.numeroPatrimonio ?? '',
    );
    _serieController = TextEditingController(
      text: _patrimonio.numeroSerie ?? '',
    );
    _marcaController = TextEditingController(text: _patrimonio.marca ?? '');
    _modeloController = TextEditingController(text: _patrimonio.modelo ?? '');
    _descricaoController = TextEditingController(
      text: _patrimonio.descricao ?? '',
    );
    _observacaoController = TextEditingController(
      text: _patrimonio.observacao ?? '',
    );
    _dataAquisicao = _patrimonio.dataAquisicao;
    _tipoId = _patrimonio.tipoId;
  }

  @override
  void dispose() {
    _numeroController.dispose();
    _serieController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _descricaoController.dispose();
    _observacaoController.dispose();
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
      await ref
          .read(patrimoniosControllerProvider.notifier)
          .atualizar(
            id: _patrimonio.id,
            numeroPatrimonio: _numeroController.text,
            numeroSerie: _serieController.text,
            tipoId: _tipoId,
            marca: _marcaController.text,
            modelo: _modeloController.text,
            descricao: _descricaoController.text,
            observacao: _observacaoController.text,
            dataAquisicao: _dataAquisicao,
          );
      ref.invalidate(patrimonioDetalheProvider(_patrimonio.id));
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
    final tiposAsync = ref.watch(tiposAtivosProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Editar patrimônio', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _numeroController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Número patrimonial',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                tiposAsync.when(
                  data: (tipos) => _TipoDropdown(
                    tipos: tipos,
                    tipoAtualId: _tipoId,
                    tipoAtualNome: widget.detalhe.tipoNome,
                    enabled: !_isSubmitting,
                    onChanged: (value) => setState(() => _tipoId = value!),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text(
                    'Não foi possível carregar os tipos de patrimônio.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _serieController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Número de série',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _marcaController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(labelText: 'Marca'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _modeloController,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(labelText: 'Modelo'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _descricaoController,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _observacaoController,
                  enabled: !_isSubmitting,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Observação'),
                ),
                const SizedBox(height: AppSpacing.md),
                DateOnlyField(
                  label: 'Data de aquisição',
                  value: _dataAquisicao,
                  enabled: !_isSubmitting,
                  onChanged: (data) => setState(() => _dataAquisicao = data),
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
                          : const Text('Salvar'),
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

/// Só permite escolher tipos ativos — mas se o tipo atual estiver inativo,
/// ele continua aparecendo (selecionado) para não perder o valor
/// silenciosamente, só não pode ser reescolhido depois de trocado.
class _TipoDropdown extends StatelessWidget {
  const _TipoDropdown({
    required this.tipos,
    required this.tipoAtualId,
    required this.tipoAtualNome,
    required this.enabled,
    required this.onChanged,
  });

  final List<TipoPatrimonio> tipos;
  final String tipoAtualId;
  final String tipoAtualNome;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tipoAtualInativo = !tipos.any((t) => t.id == tipoAtualId);

    return DropdownButtonFormField<String>(
      initialValue: tipoAtualId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tipo *'),
      items: [
        for (final tipo in tipos)
          DropdownMenuItem(
            value: tipo.id,
            child: Text(tipo.nome, overflow: TextOverflow.ellipsis),
          ),
        if (tipoAtualInativo)
          DropdownMenuItem(
            value: tipoAtualId,
            child: Text(
              '$tipoAtualNome (inativo)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (value) => value == null ? 'Selecione o tipo' : null,
    );
  }
}
