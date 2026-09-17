import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/tipo_patrimonio.dart';
import '../../../presentation/patrimonio_reference_data.dart';
import '../../domain/import_column_field.dart';
import '../../domain/import_row.dart';
import '../../domain/profiles/getec_tipo_pendente_sugestoes.dart';
import '../../domain/text_similarity.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Tipos pendentes" (PROMPT 8.13): linhas bloqueadas por "Tipo é
/// obrigatório e está vazio" — o classificador automático não conseguiu
/// inferir um tipo pela descrição, então o usuário precisa decidir. Cada
/// decisão fica só nesta sessão de importação (ver
/// [PatrimonioImportController.definirTipoPendente]); nunca vira uma regra
/// nova do classificador.
class ImportTiposPendentesStep extends ConsumerWidget {
  const ImportTiposPendentesStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final grupos = _agruparPorDescricao(state.linhasTipoPendente);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estas linhas não têm um tipo definido e o classificador automático '
          'não conseguiu inferir um pela descrição. Escolha um tipo do catálogo '
          'ativo para cada uma, ou aplique a mesma escolha a todo um grupo '
          'semelhante de uma vez. Nenhuma decisão aqui vira uma regra global — '
          'ela vale só para esta importação.',
        ),
        const SizedBox(height: AppSpacing.md),
        _ProgressoPendencias(state: state),
        const SizedBox(height: AppSpacing.md),
        tiposAsync.when(
          data: (tipos) => Card(
            child: SizedBox(
              height: 520,
              child: grupos.isEmpty
                  ? const Center(child: Text('Nenhuma linha pendente de tipo.'))
                  : ListView.separated(
                      itemCount: grupos.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _GrupoPendente(grupo: grupos[index], tipos: tipos),
                    ),
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Não foi possível carregar os tipos ativos.')),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
            FilledButton(
              // PROMPT 8.13.1: nunca liberar o avanço enquanto houver
              // pendências — o controller também rejeita a chamada por
              // segurança, mas a UI não deve nem oferecer o botão habilitado.
              onPressed: state.tipoPendenteRestantes == 0
                  ? controller.avancarDeTiposPendentesParaRevisao
                  : null,
              child: const Text('Continuar para revisão'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Agrupa as linhas pendentes pela descrição normalizada — mesma definição
/// usada em [PatrimonioImportController.linhasSemelhantesPendentes], só que
/// já materializada para a lista da UI.
List<_GrupoTipoPendente> _agruparPorDescricao(List<ImportRow> linhas) {
  final porChave = <String, List<ImportRow>>{};
  final semDescricao = <ImportRow>[];
  for (final linha in linhas) {
    final descricao = linha.descricao;
    if (descricao == null || descricao.trim().isEmpty) {
      semDescricao.add(linha);
      continue;
    }
    porChave.putIfAbsent(normalizarTextoComparacao(descricao), () => []).add(linha);
  }

  final grupos = [
    for (final entrada in porChave.entries) _GrupoTipoPendente(descricao: entrada.value.first.descricao, linhas: entrada.value),
    for (final linha in semDescricao) _GrupoTipoPendente(descricao: null, linhas: [linha]),
  ];
  grupos.sort((a, b) => b.linhas.length.compareTo(a.linhas.length));
  return grupos;
}

class _GrupoTipoPendente {
  const _GrupoTipoPendente({required this.descricao, required this.linhas});

  final String? descricao;
  final List<ImportRow> linhas;
}

class _ProgressoPendencias extends StatelessWidget {
  const _ProgressoPendencias({required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context) {
    final total = state.totalTipoPendente;
    final resolvidos = state.tipoPendenteResolvidos;
    final restantes = state.tipoPendenteRestantes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: [
            Text('Tipos pendentes: $total'),
            Text('Resolvidos manualmente: $resolvidos'),
            Text(
              'Restantes: $restantes',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: restantes == 0
                    ? Theme.of(context).statusColors.successForeground
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrupoPendente extends ConsumerWidget {
  const _GrupoPendente({required this.grupo, required this.tipos});

  final _GrupoTipoPendente grupo;
  final List<TipoPatrimonio> tipos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final sugestoes = sugerirTiposNaoVinculantes(grupo.descricao);
    final restantesNoGrupo = grupo.linhas.where((l) => l.tipoIdResolvido == null).length;

    return ExpansionTile(
      key: ValueKey('grupo-tipo-pendente-${grupo.descricao ?? grupo.linhas.first.numeroLinha}'),
      title: Text(grupo.descricao ?? '(sem descrição)'),
      subtitle: Text(
        '${grupo.linhas.length} patrimônio(s) — $restantesNoGrupo ainda sem tipo',
      ),
      children: [
        if (sugestoes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sugestão (não vinculante): ${sugestoes.join(' ou ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (grupo.linhas.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Row(
              children: [
                const Text('Aplicar aos semelhantes:'),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButton<String>(
                    key: ValueKey('lote-tipo-pendente-${grupo.descricao}'),
                    isExpanded: true,
                    hint: const Text('Selecionar tipo'),
                    items: [
                      for (final tipo in tipos) DropdownMenuItem(value: tipo.id, child: Text(tipo.nome)),
                    ],
                    onChanged: (tipoId) {
                      if (tipoId == null) return;
                      _confirmarAplicacaoEmLote(context, controller, grupo, tipoId, tipos);
                    },
                  ),
                ),
              ],
            ),
          ),
        for (final linha in grupo.linhas) _LinhaPendenteTile(linha: linha, tipos: tipos),
      ],
    );
  }

  Future<void> _confirmarAplicacaoEmLote(
    BuildContext context,
    PatrimonioImportController controller,
    _GrupoTipoPendente grupo,
    String tipoId,
    List<TipoPatrimonio> tipos,
  ) async {
    final nomeTipo = tipos.firstWhere((t) => t.id == tipoId).nome;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aplicar tipo em lote?'),
        content: Text(
          'Esta decisão será aplicada a ${grupo.linhas.length} patrimônios '
          '(todos com a descrição "${grupo.descricao}"), atribuindo o tipo '
          '"$nomeTipo". Isto vale só para esta importação — não altera o '
          'classificador automático.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (confirmar == true) {
      controller.aplicarTipoEmLote(grupo.linhas, tipoId);
    }
  }
}

class _LinhaPendenteTile extends ConsumerWidget {
  const _LinhaPendenteTile({required this.linha, required this.tipos});

  final ImportRow linha;
  final List<TipoPatrimonio> tipos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final resolvida = linha.tipoIdResolvido != null;

    final tombamentoAnterior = linha.celulas[ImportColumnField.tombamentoAnterior];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                resolvida ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: resolvida ? Theme.of(context).statusColors.successForeground : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Patrimônio: ${linha.numeroPatrimonio ?? '(sem número)'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Descrição completa, sem truncar — precisa de espaço suficiente
          // para o usuário decidir o tipo corretamente (PROMPT 8.13, seção 1).
          Text('Descrição: ${linha.descricao ?? '(sem descrição)'}', softWrap: true),
          if (tombamentoAnterior != null) Text('Tombamento anterior: $tombamentoAnterior'),
          if (linha.marca != null) Text('Marca: ${linha.marca}'),
          if (linha.numeroSerie != null) Text('Número de série: ${linha.numeroSerie}'),
          if (linha.localizacaoTexto != null) Text('Localização original: ${linha.localizacaoTexto}'),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String?>(
            // Chave incorpora o valor atual: força recriar o FormField
            // quando o tipo muda por uma ação externa à própria linha (ex.:
            // "Aplicar aos semelhantes") — sem isto, `initialValue` só é
            // aplicado uma vez e o dropdown pode ficar visualmente
            // desatualizado (PROMPT 8.13.1).
            key: ValueKey('tipo-pendente-${linha.numeroLinha}-${linha.tipoIdResolvido}'),
            initialValue: linha.tipoIdResolvido,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Tipo selecionado'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Deixar pendente')),
              for (final tipo in tipos) DropdownMenuItem(value: tipo.id, child: Text(tipo.nome)),
            ],
            onChanged: (tipoId) => controller.definirTipoPendente(linha, tipoId),
          ),
        ],
      ),
    );
  }
}
