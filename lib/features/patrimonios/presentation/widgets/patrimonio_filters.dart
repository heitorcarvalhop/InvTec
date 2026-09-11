import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/patrimonio.dart';
import '../patrimonio_reference_data.dart';
import '../patrimonios_controller.dart';
import '../patrimonios_filtro.dart';

/// Filtros opcionais e combináveis (tipo + status + setor), sempre
/// resolvidos no servidor pelo [PatrimoniosController].
class PatrimonioFilters extends ConsumerWidget {
  const PatrimonioFilters({super.key, required this.filtro});

  final PatrimoniosFiltro filtro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final notifier = ref.read(patrimoniosControllerProvider.notifier);

    return Wrap(
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
        if (filtro.temFiltroAtivo)
          TextButton.icon(
            onPressed: notifier.limparFiltros,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Limpar filtros'),
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
