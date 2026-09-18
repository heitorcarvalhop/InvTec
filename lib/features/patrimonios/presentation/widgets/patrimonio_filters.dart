import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../domain/patrimonio.dart';
import '../patrimonio_reference_data.dart';
import '../patrimonios_controller.dart';
import '../patrimonios_filtro.dart';

/// Valor de item do dropdown de Localização usado só para representar
/// "Sem localização" (`localizacao_atual_id IS NULL`) sem confundir com
/// `null` (que, no dropdown, já significa "Todas as localizações").
const _semLocalizacaoValor = '__sem_localizacao__';

/// Filtros principais (tipo + status + setor + localização) e avançados
/// (marca/modelo/responsável/datas), sempre resolvidos no servidor pelo
/// [PatrimoniosController] (PROMPT 9.2). Os campos de texto avançados
/// vivem como estado local (controllers) para não perder o que o usuário
/// digitou entre um debounce e outro.
class PatrimonioFilters extends ConsumerStatefulWidget {
  const PatrimonioFilters({
    super.key,
    required this.filtro,
    required this.onLimparFiltros,
  });

  final PatrimoniosFiltro filtro;

  /// Seção 7: limpar filtros zera TUDO — texto/campo de busca (que vive na
  /// página, fora deste widget), Tipo/Status/Setor/Localização e os
  /// avançados (marca/modelo/responsável/datas, que vivem aqui).
  final VoidCallback onLimparFiltros;

  @override
  ConsumerState<PatrimonioFilters> createState() => _PatrimonioFiltersState();
}

class _PatrimonioFiltersState extends ConsumerState<PatrimonioFilters> {
  late final _marcaController = TextEditingController(text: widget.filtro.marca);
  late final _modeloController = TextEditingController(text: widget.filtro.modelo);
  late final _responsavelController = TextEditingController(text: widget.filtro.responsavel);
  bool _avancadoExpandido = false;

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _responsavelController.dispose();
    super.dispose();
  }

  void _limparTudo() {
    _marcaController.clear();
    _modeloController.clear();
    _responsavelController.clear();
    widget.onLimparFiltros();
  }

  /// Seção 5: valida "data inicial <= data final" ANTES de aplicar — se
  /// inválido, mostra o erro e nunca chama [onValido] (nunca dispara uma
  /// consulta com intervalo invertido).
  void _aplicarIntervaloData({
    required DateTime? de,
    required DateTime? ate,
    required void Function(DateTime? de, DateTime? ate) onValido,
  }) {
    if (!intervaloDeDataValido(de, ate)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('A data inicial deve ser anterior ou igual à data final.'),
          ),
        );
      return;
    }
    onValido(de, ate);
  }

  @override
  Widget build(BuildContext context) {
    final filtro = widget.filtro;
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final localizacoesAsync = ref.watch(localizacoesParaFiltroProvider(filtro.setorId));
    final notifier = ref.read(patrimoniosControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: tiposAsync.when(
                data: (tipos) => DropdownButtonFormField<String?>(
                  initialValue: filtro.tipoId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos os tipos')),
                    for (final tipo in tipos)
                      DropdownMenuItem(
                        value: tipo.id,
                        child: Text(tipo.nome, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: notifier.filtrarPorTipo,
                ),
                loading: () => const _CampoDesabilitado(label: 'Tipo'),
                error: (error, stackTrace) => const _CampoDesabilitado(label: 'Tipo'),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<PatrimonioStatus?>(
                initialValue: filtro.status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos os status')),
                  for (final status in PatrimonioStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: notifier.filtrarPorStatus,
              ),
            ),
            SizedBox(
              width: 220,
              child: setoresAsync.when(
                data: (setores) => DropdownButtonFormField<String?>(
                  initialValue: filtro.setorId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Setor atual'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos os setores')),
                    for (final setor in setores)
                      DropdownMenuItem(
                        value: setor.id,
                        child: Text(setor.nome, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: notifier.filtrarPorSetor,
                ),
                loading: () => const _CampoDesabilitado(label: 'Setor atual'),
                error: (error, stackTrace) =>
                    const _CampoDesabilitado(label: 'Setor atual'),
              ),
            ),
            SizedBox(
              width: 240,
              child: localizacoesAsync.when(
                data: (localizacoes) => DropdownButtonFormField<String>(
                  initialValue: filtro.semLocalizacao ? _semLocalizacaoValor : (filtro.localizacaoId ?? ''),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Localização'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todas as localizações')),
                    const DropdownMenuItem(
                      value: _semLocalizacaoValor,
                      child: Text('Sem localização'),
                    ),
                    for (final localizacao in localizacoes)
                      DropdownMenuItem(
                        value: localizacao.id,
                        child: Text(localizacao.nome, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (valor) {
                    if (valor == _semLocalizacaoValor) {
                      notifier.filtrarPorLocalizacao(null, semLocalizacao: true);
                    } else if (valor == '') {
                      notifier.filtrarPorLocalizacao(null);
                    } else {
                      notifier.filtrarPorLocalizacao(valor);
                    }
                  },
                ),
                loading: () => const _CampoDesabilitado(label: 'Localização'),
                error: (error, stackTrace) => const _CampoDesabilitado(label: 'Localização'),
              ),
            ),
            if (filtro.temFiltroAtivo)
              TextButton.icon(
                onPressed: _limparTudo,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpar filtros'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () => setState(() => _avancadoExpandido = !_avancadoExpandido),
          icon: Icon(_avancadoExpandido ? Icons.expand_less : Icons.expand_more),
          label: Text(
            filtro.quantidadeFiltrosAvancados > 0
                ? 'Filtros avançados (${filtro.quantidadeFiltrosAvancados})'
                : 'Filtros avançados',
          ),
        ),
        if (_avancadoExpandido)
          Container(
            // Sem Card/borda própria: este bloco já vive dentro do painel
            // de busca+filtros (PROMPT 9.3.3, seção 6) — um tom
            // ligeiramente diferente do fundo do painel basta para
            // demarcar a seção "afundada", sem duplicar bordas.
            margin: const EdgeInsets.only(top: AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).surfaceColors.pageBackground,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _marcaController,
                      decoration: const InputDecoration(labelText: 'Marca'),
                      onChanged: notifier.definirMarca,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _modeloController,
                      decoration: const InputDecoration(labelText: 'Modelo'),
                      onChanged: notifier.definirModelo,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _responsavelController,
                      decoration: const InputDecoration(labelText: 'Responsável'),
                      onChanged: notifier.definirResponsavel,
                    ),
                  ),
                  _DateRangeFilter(
                    label: 'Data de cadastro',
                    de: filtro.dataCadastroDe,
                    ate: filtro.dataCadastroAte,
                    onChanged: (de, ate) => _aplicarIntervaloData(
                      de: de,
                      ate: ate,
                      onValido: notifier.definirDataCadastro,
                    ),
                  ),
                  _DateRangeFilter(
                    label: 'Data de aquisição',
                    de: filtro.dataAquisicaoDe,
                    ate: filtro.dataAquisicaoAte,
                    onChanged: (de, ate) => _aplicarIntervaloData(
                      de: de,
                      ate: ate,
                      onValido: notifier.definirDataAquisicao,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CampoDesabilitado extends StatelessWidget {
  const _CampoDesabilitado({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: const [],
      onChanged: null,
    );
  }
}

/// Um intervalo De/Até (seção 5) — os limites exibidos são sempre o último
/// valor VÁLIDO aplicado (nunca um valor rejeitado pela validação, que só
/// gera um aviso e não é armazenado em lugar nenhum).
class _DateRangeFilter extends StatelessWidget {
  const _DateRangeFilter({
    required this.label,
    required this.de,
    required this.ate,
    required this.onChanged,
  });

  final String label;
  final DateTime? de;
  final DateTime? ate;
  final void Function(DateTime? de, DateTime? ate) onChanged;

  Future<void> _selecionar(BuildContext context, {required bool inicio}) async {
    final selecionado = await showDatePicker(
      context: context,
      initialDate: (inicio ? de : ate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selecionado == null) return;
    onChanged(inicio ? selecionado : de, inicio ? ate : selecionado);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _DateChip(
              label: 'De',
              data: de,
              onTap: () => _selecionar(context, inicio: true),
              onClear: de == null ? null : () => onChanged(null, ate),
            ),
            _DateChip(
              label: 'Até',
              data: ate,
              onTap: () => _selecionar(context, inicio: false),
              onClear: ate == null ? null : () => onChanged(de, null),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.data,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? data;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final texto = data == null ? label : '$label: ${_formatarData(data!)}';
    return InputChip(label: Text(texto), onPressed: onTap, onDeleted: onClear);
  }
}

String _formatarData(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
