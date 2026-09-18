import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/movimentacao.dart';
import '../movimentacoes_controller.dart';
import '../movimentacoes_filtro.dart';
import '../movimentacoes_reference_data.dart';

/// Filtros da listagem geral de movimentações (PROMPT 10.1): tipo, setor
/// (origem OU destino) e período — todos imediatos (sem debounce; a busca
/// textual vive na página, como em Patrimônios). O filtro de Setor usa
/// `setoresParaFiltroMovimentacoesProvider` (PROMPT 10.1.1) — não o mesmo
/// provider de Patrimônios — porque o histórico pode referenciar um setor já
/// desativado, e esse setor precisa continuar filtrável.
class MovimentacoesFilters extends ConsumerWidget {
  const MovimentacoesFilters({super.key, required this.filtro, required this.onLimparFiltros});

  final MovimentacoesFiltro filtro;

  /// Limpar filtros também limpa o texto de busca (que vive na página, fora
  /// deste widget) — nunca só o lado do controller, senão o texto digitado
  /// ficaria visualmente "preso" no campo (mesmo raciocínio de
  /// `PatrimonioFilters.onLimparFiltros`).
  final VoidCallback onLimparFiltros;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setoresAsync = ref.watch(setoresParaFiltroMovimentacoesProvider);
    final notifier = ref.read(movimentacoesControllerProvider.notifier);

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
              child: DropdownButtonFormField<MovimentacaoTipo?>(
                initialValue: filtro.tipo,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos os tipos')),
                  for (final tipo in MovimentacaoTipo.values)
                    DropdownMenuItem(value: tipo, child: Text(tipo.label)),
                ],
                onChanged: notifier.filtrarPorTipo,
              ),
            ),
            SizedBox(
              width: 220,
              child: setoresAsync.when(
                data: (setores) => DropdownButtonFormField<String?>(
                  initialValue: filtro.setorId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Setor'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos os setores')),
                    for (final setor in setores)
                      DropdownMenuItem(
                        value: setor.id,
                        child: Text(setor.ativo ? setor.nome : '${setor.nome} (inativo)'),
                      ),
                  ],
                  onChanged: notifier.filtrarPorSetor,
                ),
                loading: () => const _CampoDesabilitado(label: 'Setor'),
                error: (error, stackTrace) => const _CampoDesabilitado(label: 'Setor'),
              ),
            ),
            _PeriodoFilter(
              de: filtro.periodoDe,
              ate: filtro.periodoAte,
              onChanged: (de, ate) {
                if (!intervaloPeriodoValido(de, ate)) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('A data inicial deve ser anterior ou igual à data final.'),
                      ),
                    );
                  return;
                }
                notifier.definirPeriodo(de, ate);
              },
            ),
            if (filtro.temFiltroAtivo)
              TextButton.icon(
                onPressed: onLimparFiltros,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Limpar filtros'),
              ),
          ],
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

/// Mesmo padrão visual do intervalo De/Até de Patrimônios (PROMPT 9.2,
/// seção 5): os limites exibidos são sempre o último valor VÁLIDO
/// aplicado.
class _PeriodoFilter extends StatelessWidget {
  const _PeriodoFilter({required this.de, required this.ate, required this.onChanged});

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
        Text('Período', style: Theme.of(context).textTheme.labelMedium),
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
  const _DateChip({required this.label, required this.data, required this.onTap, required this.onClear});

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

String _formatarData(DateTime data) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(data.day)}/${pad(data.month)}/${data.year}';
}
