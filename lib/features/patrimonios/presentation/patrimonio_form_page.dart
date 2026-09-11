import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../setores/domain/setor.dart';
import '../domain/tipo_patrimonio.dart';
import 'patrimonio_reference_data.dart';
import 'patrimonios_controller.dart';
import 'widgets/date_only_field.dart';

/// Página dedicada (não dialog): o formulário de cadastro tem muitos
/// campos em duas seções — ver [_DadosEquipamentoSection] e
/// [_EntradaInicialSection].
class PatrimonioFormPage extends ConsumerWidget {
  const PatrimonioFormPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Novo patrimônio', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cadastre um novo equipamento e registre sua entrada inicial.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _Conteudo(tiposAsync: tiposAsync, setoresAsync: setoresAsync),
          ],
        ),
      ),
    );
  }
}

class _Conteudo extends ConsumerWidget {
  const _Conteudo({required this.tiposAsync, required this.setoresAsync});

  final AsyncValue<List<TipoPatrimonio>> tiposAsync;
  final AsyncValue<List<Setor>> setoresAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tiposAsync.isLoading || setoresAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (tiposAsync.hasError || setoresAsync.hasError) {
      return Center(
        child: EmptyState(
          icon: Icons.error_outline,
          message: 'Não foi possível carregar tipos/setores. Tente novamente.',
          actionLabel: 'Tentar novamente',
          onAction: () {
            ref.invalidate(tiposAtivosProvider);
            ref.invalidate(setoresAtivosParaPatrimonioProvider);
          },
        ),
      );
    }

    final tipos = tiposAsync.requireValue;
    final setores = setoresAsync.requireValue;

    if (tipos.isEmpty) {
      return const _BloqueioCadastro(
        mensagem:
            'Nenhum tipo de patrimônio está ativo no momento. Um '
            'administrador precisa cadastrar ao menos um tipo de '
            'patrimônio para que novos equipamentos possam ser registrados.',
        rotaConfiguracao: null,
      );
    }

    if (setores.isEmpty) {
      final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
      final podeConfigurar =
          perfil == ProfilePerfil.admin || perfil == ProfilePerfil.gestor;
      return _BloqueioCadastro(
        mensagem: podeConfigurar
            ? 'Cadastre pelo menos um setor antes de registrar patrimônios.'
            : 'Ainda não há setores cadastrados. Um administrador ou '
                  'gestor precisa configurá-los antes que patrimônios '
                  'possam ser registrados.',
        rotaConfiguracao: podeConfigurar ? '/setores' : null,
      );
    }

    return _PatrimonioForm(tipos: tipos, setores: setores);
  }
}

class _BloqueioCadastro extends StatelessWidget {
  const _BloqueioCadastro({required this.mensagem, this.rotaConfiguracao});

  final String mensagem;
  final String? rotaConfiguracao;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(mensagem)),
              ],
            ),
            if (rotaConfiguracao != null) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => context.push(rotaConfiguracao!),
                  child: const Text('Ir para Setores'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatrimonioForm extends ConsumerStatefulWidget {
  const _PatrimonioForm({required this.tipos, required this.setores});

  final List<TipoPatrimonio> tipos;
  final List<Setor> setores;

  @override
  ConsumerState<_PatrimonioForm> createState() => _PatrimonioFormState();
}

class _PatrimonioFormState extends ConsumerState<_PatrimonioForm> {
  final _formKey = GlobalKey<FormState>();

  final _numeroController = TextEditingController();
  final _serieController = TextEditingController();
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _responsavelOrigemController = TextEditingController();
  final _responsavelDestinoController = TextEditingController();
  final _motivoController = TextEditingController();
  final _observacaoMovimentacaoController = TextEditingController();

  String? _tipoId;
  String? _origemId;
  String? _destinoId;
  DateTime? _dataAquisicao;
  DateTime _dataMovimentacao = DateTime.now();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _numeroController.dispose();
    _serieController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _descricaoController.dispose();
    _observacaoController.dispose();
    _responsavelOrigemController.dispose();
    _responsavelDestinoController.dispose();
    _motivoController.dispose();
    _observacaoMovimentacaoController.dispose();
    super.dispose();
  }

  Future<void> _selecionarDataMovimentacao() async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: _dataMovimentacao,
      firstDate: DateTime(2000),
      lastDate: agora,
    );
    if (data == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dataMovimentacao),
    );
    if (hora == null) return;

    final combinada = DateTime(
      data.year,
      data.month,
      data.day,
      hora.hour,
      hora.minute,
    );
    setState(() => _dataMovimentacao = combinada.isAfter(agora) ? agora : combinada);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_origemId != null && _origemId == _destinoId) {
      setState(
        () => _errorMessage = 'Verifique a origem e o destino informados.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final patrimonio = await ref
          .read(patrimoniosControllerProvider.notifier)
          .cadastrar(
            tipoId: _tipoId!,
            destinoId: _destinoId!,
            numeroPatrimonio: _numeroController.text,
            numeroSerie: _serieController.text,
            marca: _marcaController.text,
            modelo: _modeloController.text,
            descricao: _descricaoController.text,
            observacao: _observacaoController.text,
            dataAquisicao: _dataAquisicao,
            origemId: _origemId,
            responsavelOrigem: _responsavelOrigemController.text,
            responsavelDestino: _responsavelDestinoController.text,
            motivo: _motivoController.text,
            observacaoMovimentacao: _observacaoMovimentacaoController.text,
            dataMovimentacao: _dataMovimentacao,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Patrimônio cadastrado com sucesso.')),
        );
      context.pushReplacement('/patrimonios/${patrimonio.id}');
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

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DADOS DO EQUIPAMENTO', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _numeroController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Número patrimonial',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _tipoId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tipo *'),
                    items: [
                      for (final tipo in widget.tipos)
                        DropdownMenuItem(
                          value: tipo.id,
                          child: Text(tipo.nome, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _tipoId = value),
                    validator: (value) =>
                        value == null ? 'Selecione o tipo' : null,
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
                    controller: _serieController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Número de série',
                    ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ENTRADA INICIAL', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _origemId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Origem',
                      helperText: 'De onde o patrimônio veio (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Não informar')),
                      for (final setor in widget.setores)
                        DropdownMenuItem(
                          value: setor.id,
                          child: Text(setor.nome, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _origemId = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _destinoId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Destino / Setor atual *',
                    ),
                    items: [
                      for (final setor in widget.setores)
                        DropdownMenuItem(
                          value: setor.id,
                          child: Text(setor.nome, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _destinoId = value),
                    validator: (value) =>
                        value == null ? 'Selecione o destino' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _responsavelOrigemController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Responsável na origem',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _responsavelDestinoController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(
                      labelText: 'Responsável no destino',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Se um responsável for informado, o patrimônio será '
                    'registrado como Em uso. Caso contrário, ficará '
                    'Disponível.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _motivoController,
                    enabled: !_isSubmitting,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _observacaoMovimentacaoController,
                    enabled: !_isSubmitting,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observação da movimentação',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  InkWell(
                    onTap: _isSubmitting ? null : _selecionarDataMovimentacao,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data da movimentação',
                        suffixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(_formatarDataHora(_dataMovimentacao)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _errorMessage!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cadastrar patrimônio'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
