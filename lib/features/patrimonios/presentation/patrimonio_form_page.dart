import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/routing/back_navigation.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/validation/app_validators.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../localizacoes/presentation/localizacoes_providers.dart';
import '../../setores/domain/setor.dart';
import '../domain/tipo_patrimonio.dart';
import 'patrimonio_reference_data.dart';
import 'patrimonios_controller.dart';
import 'widgets/confirm_discard_dialog.dart';
import 'widgets/date_only_field.dart';

/// Página dedicada (não dialog): o formulário de cadastro tem muitos
/// campos em duas seções — ver [_DadosEquipamentoSection] e
/// [_EntradaInicialSection].
class PatrimonioFormPage extends ConsumerStatefulWidget {
  const PatrimonioFormPage({super.key});

  @override
  ConsumerState<PatrimonioFormPage> createState() => _PatrimonioFormPageState();
}

class _PatrimonioFormPageState extends ConsumerState<PatrimonioFormPage> {
  // Permite consultar, sob demanda (ao sair), se o formulário tem dados não
  // salvos — sem isso o botão de voltar do cabeçalho (fora da árvore de
  // `_PatrimonioForm`) não teria como saber. `null` quando o formulário
  // ainda não foi montado (ex.: carregando tipos/setores, ou bloqueado por
  // falta de tipo/setor cadastrado) — nesse caso não há nada para perder.
  final _formStateKey = GlobalKey<_PatrimonioFormState>();

  /// Mesma lógica de saída para o botão "Voltar" do cabeçalho e o "Cancelar"
  /// do rodapé: nunca duplicar a checagem de dados não salvos.
  Future<void> _sair() async {
    final dirty = _formStateKey.currentState?.isDirty ?? false;
    if (dirty) {
      final descartar = await confirmarDescartarAlteracoes(context);
      if (!descartar) return;
    }
    if (!mounted) return;
    backOrGo(context, '/patrimonios');
  }

  @override
  Widget build(BuildContext context) {
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvTecPageHeader(
              title: 'Novo patrimônio',
              subtitle: 'Cadastre um novo equipamento e registre sua entrada inicial.',
              onBack: _sair,
            ),
            const SizedBox(height: AppSpacing.lg),
            _Conteudo(
              tiposAsync: tiposAsync,
              setoresAsync: setoresAsync,
              formStateKey: _formStateKey,
              onCancelar: _sair,
            ),
          ],
        ),
      ),
    );
  }
}

class _Conteudo extends ConsumerWidget {
  const _Conteudo({
    required this.tiposAsync,
    required this.setoresAsync,
    required this.formStateKey,
    required this.onCancelar,
  });

  final AsyncValue<List<TipoPatrimonio>> tiposAsync;
  final AsyncValue<List<Setor>> setoresAsync;
  final GlobalKey<_PatrimonioFormState> formStateKey;
  final VoidCallback onCancelar;

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

    return _PatrimonioForm(
      key: formStateKey,
      tipos: tipos,
      setores: setores,
      onCancelar: onCancelar,
    );
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
  const _PatrimonioForm({
    super.key,
    required this.tipos,
    required this.setores,
    required this.onCancelar,
  });

  final List<TipoPatrimonio> tipos;
  final List<Setor> setores;

  /// Mesma função de saída usada pelo botão "Voltar" do cabeçalho — aqui
  /// alimentada pelo botão "Cancelar" do rodapé. Nunca `context.pop()`
  /// direto: a checagem de dados não salvos vive só em [_sair] (em
  /// [_PatrimonioFormPageState]), nunca duplicada aqui.
  final VoidCallback onCancelar;

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
  String? _localizacaoOrigemId;
  String? _destinoId;
  String? _localizacaoDestinoId;
  DateTime? _dataAquisicao;
  DateTime _dataMovimentacao = DateTime.now();

  bool _isSubmitting = false;
  String? _errorMessage;

  /// `true` quando qualquer campo de texto foi preenchido ou qualquer
  /// seleção foi feita — consultado sob demanda (ao tentar sair), nunca
  /// armazenado em um campo próprio, para nunca ficar dessincronizado do
  /// que o usuário realmente digitou. A data da movimentação fica de fora:
  /// ela já nasce preenchida com "agora" (um padrão, não uma escolha do
  /// usuário), então não entra na checagem de "alterações".
  bool get isDirty =>
      _numeroController.text.isNotEmpty ||
      _serieController.text.isNotEmpty ||
      _marcaController.text.isNotEmpty ||
      _modeloController.text.isNotEmpty ||
      _descricaoController.text.isNotEmpty ||
      _observacaoController.text.isNotEmpty ||
      _responsavelOrigemController.text.isNotEmpty ||
      _responsavelDestinoController.text.isNotEmpty ||
      _motivoController.text.isNotEmpty ||
      _observacaoMovimentacaoController.text.isNotEmpty ||
      _tipoId != null ||
      _origemId != null ||
      _localizacaoOrigemId != null ||
      _destinoId != null ||
      _localizacaoDestinoId != null ||
      _dataAquisicao != null;

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
            localizacaoOrigemId: _localizacaoOrigemId,
            localizacaoDestinoId: _localizacaoDestinoId,
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
    // Grid de duas colunas só no desktop — tablet/mobile ficam em uma
    // coluna só, sem overflow e sem largura fixa nos campos.
    final duasColunas = context.screenSize == ScreenSize.desktop;

    final numeroField = TextFormField(
      controller: _numeroController,
      enabled: !_isSubmitting,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(labelText: 'Número patrimonial'),
      validator: AppValidators.numeroPatrimonio,
    );
    final tipoField = DropdownButtonFormField<String>(
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
      validator: (value) => value == null ? 'Selecione o tipo' : null,
    );
    final marcaField = TextFormField(
      controller: _marcaController,
      enabled: !_isSubmitting,
      decoration: const InputDecoration(labelText: 'Marca'),
    );
    final modeloField = TextFormField(
      controller: _modeloController,
      enabled: !_isSubmitting,
      decoration: const InputDecoration(labelText: 'Modelo'),
    );
    final serieField = TextFormField(
      controller: _serieController,
      enabled: !_isSubmitting,
      decoration: const InputDecoration(labelText: 'Número de série'),
    );
    final dataAquisicaoField = DateOnlyField(
      label: 'Data de aquisição',
      value: _dataAquisicao,
      enabled: !_isSubmitting,
      onChanged: (data) => setState(() => _dataAquisicao = data),
    );
    final descricaoField = TextFormField(
      controller: _descricaoController,
      enabled: !_isSubmitting,
      maxLines: 2,
      decoration: const InputDecoration(labelText: 'Descrição'),
    );
    final observacaoField = TextFormField(
      controller: _observacaoController,
      enabled: !_isSubmitting,
      maxLines: 2,
      decoration: const InputDecoration(labelText: 'Observação'),
    );

    final origemDropdown = DropdownButtonFormField<String>(
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
            // Sigla cadastrada, nome completo por tooltip.
            child: Tooltip(
              message: setor.nome,
              child: Text(setor.rotuloCompacto, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      onChanged: _isSubmitting
          ? null
          : (value) => setState(() {
              _origemId = value;
              // localização é sempre da MESMA gerência — trocar a
              // gerência invalida a localização escolhida (nunca mostrar
              // localização de outra gerência).
              _localizacaoOrigemId = null;
            }),
    );
    final destinoDropdown = DropdownButtonFormField<String>(
      initialValue: _destinoId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Destino / Setor atual *'),
      items: [
        for (final setor in widget.setores)
          DropdownMenuItem(
            value: setor.id,
            child: Tooltip(
              message: setor.nome,
              child: Text(setor.rotuloCompacto, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      onChanged: _isSubmitting
          ? null
          : (value) => setState(() {
              _destinoId = value;
              _localizacaoDestinoId = null;
            }),
      validator: (value) => value == null ? 'Selecione o destino' : null,
    );
    // Cada coluna carrega sua própria localização condicional — a mesma
    // regra de hoje (só aparece depois que a gerência é escolhida), só
    // organizada lado a lado com a coluna irmã em vez de sequencial.
    final origemColuna = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        origemDropdown,
        if (_origemId != null) ...[
          const SizedBox(height: AppSpacing.md),
          _LocalizacaoSelector(
            setorId: _origemId!,
            label: 'Localização de origem',
            value: _localizacaoOrigemId,
            enabled: !_isSubmitting,
            onChanged: (value) => setState(() => _localizacaoOrigemId = value),
          ),
        ],
      ],
    );
    final destinoColuna = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        destinoDropdown,
        if (_destinoId != null) ...[
          const SizedBox(height: AppSpacing.md),
          _LocalizacaoSelector(
            setorId: _destinoId!,
            label: 'Localização',
            value: _localizacaoDestinoId,
            enabled: !_isSubmitting,
            onChanged: (value) => setState(() => _localizacaoDestinoId = value),
          ),
        ],
      ],
    );
    final responsavelOrigemField = TextFormField(
      controller: _responsavelOrigemController,
      enabled: !_isSubmitting,
      decoration: const InputDecoration(labelText: 'Responsável na origem'),
    );
    final responsavelDestinoField = TextFormField(
      controller: _responsavelDestinoController,
      enabled: !_isSubmitting,
      decoration: const InputDecoration(labelText: 'Responsável no destino'),
    );
    final motivoField = TextFormField(
      controller: _motivoController,
      enabled: !_isSubmitting,
      decoration: const InputDecoration(labelText: 'Motivo'),
    );
    final dataMovimentacaoField = InkWell(
      onTap: _isSubmitting ? null : _selecionarDataMovimentacao,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Data da movimentação',
          suffixIcon: Icon(Icons.event_outlined),
        ),
        child: Text(_formatarDataHora(_dataMovimentacao)),
      ),
    );
    final observacaoMovimentacaoField = TextFormField(
      controller: _observacaoMovimentacaoController,
      enabled: !_isSubmitting,
      maxLines: 2,
      decoration: const InputDecoration(labelText: 'Observação da movimentação'),
    );

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
                  _FieldPair(duasColunas: duasColunas, first: numeroField, second: tipoField),
                  const SizedBox(height: AppSpacing.md),
                  _FieldPair(duasColunas: duasColunas, first: marcaField, second: modeloField),
                  const SizedBox(height: AppSpacing.md),
                  _FieldPair(duasColunas: duasColunas, first: serieField, second: dataAquisicaoField),
                  const SizedBox(height: AppSpacing.md),
                  descricaoField,
                  const SizedBox(height: AppSpacing.md),
                  observacaoField,
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
                  _FieldPair(duasColunas: duasColunas, first: origemColuna, second: destinoColuna),
                  const SizedBox(height: AppSpacing.md),
                  _FieldPair(
                    duasColunas: duasColunas,
                    first: responsavelOrigemField,
                    second: responsavelDestinoField,
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
                  _FieldPair(duasColunas: duasColunas, first: motivoField, second: dataMovimentacaoField),
                  const SizedBox(height: AppSpacing.md),
                  observacaoMovimentacaoField,
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
            child: Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _isSubmitting ? null : widget.onCancelar,
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cadastrar patrimônio'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// Dois campos lado a lado no desktop (cada um ocupando metade da largura);
/// empilhados em tablet/mobile. Nunca usa largura fixa — sempre `Expanded`
/// dentro do `Row`, para nunca gerar overflow horizontal.
class _FieldPair extends StatelessWidget {
  const _FieldPair({
    required this.duasColunas,
    required this.first,
    required this.second,
  });

  final bool duasColunas;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (!duasColunas) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [first, const SizedBox(height: AppSpacing.md), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: second),
      ],
    );
  }
}

/// Localizações ATIVAS de [setorId] — nunca mostra localização de outra
/// gerência. Quando a gerência não tem nenhuma, mostra a mensagem explícita
/// em vez de um seletor vazio confuso.
class _LocalizacaoSelector extends ConsumerWidget {
  const _LocalizacaoSelector({
    required this.setorId,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String setorId;
  final String label;
  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizacoesAsync = ref.watch(localizacoesAtivasPorSetorProvider(setorId));

    return localizacoesAsync.when(
      data: (localizacoes) {
        if (localizacoes.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: Text(
              'Esta gerência não possui localizações cadastradas.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: 'Opcional'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Sem localização')),
            for (final localizacao in localizacoes)
              DropdownMenuItem(value: localizacao.id, child: Text(localizacao.nome)),
          ],
          onChanged: enabled ? onChanged : null,
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(
        'Não foi possível carregar as localizações.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
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
