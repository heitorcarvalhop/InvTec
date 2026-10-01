import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../domain/patrimonio_comparacao.dart';
import '../../domain/patrimonio_decisao.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Comparar e Atualizar" — modo ADMIN, alcançado a partir do MESMO
/// assistente de importação (nunca um segundo importador): mostra
/// [ComparacaoResumo], a lista filtrável de
/// [PatrimonioImportState.itensComparacaoFiltrados] (idênticos JÁ excluídos)
/// e a comparação campo a campo de cada divergência, consumindo
/// [CampoDivergente] diretamente — nenhum widget aqui recompara nada:
/// [PatrimonioComparador] já fez isso.
///
/// Só prepara decisões em memória. Nenhum botão aqui chama
/// `cadastrar`/`atualizar`/qualquer RPC de escrita.
class ImportComparacaoStep extends ConsumerWidget {
  const ImportComparacaoStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final lote = state.comparacao;

    if (state.carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (lote == null) {
      return const EmptyState(
        icon: Icons.error_outline,
        message: 'Nenhuma comparação disponível — volte e analise a planilha novamente.',
      );
    }

    final itens = state.itensComparacaoFiltrados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AvisoSomenteRevisao(),
        const SizedBox(height: AppSpacing.md),
        _ResumoComparacao(resumo: lote.resumo),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('comparacao-busca-numero'),
          decoration: const InputDecoration(
            labelText: 'Buscar por número patrimonial',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: controller.definirBuscaNumeroPatrimonio,
        ),
        const SizedBox(height: AppSpacing.md),
        _FiltrosComparacao(state: state, onFiltrar: controller.definirFiltroComparacao),
        const SizedBox(height: AppSpacing.md),
        _AcoesEmMassa(controller: controller),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: SizedBox(
            height: 480,
            child: itens.isEmpty
                ? const Center(child: Text('Nenhum item para esta categoria/busca.'))
                : ListView.builder(
                    key: const Key('comparacao-lista'),
                    itemCount: itens.length,
                    itemBuilder: (context, index) =>
                        _ItemComparacaoTile(item: itens[index], state: state, controller: controller),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
            FilledButton.icon(
              key: const Key('comparacao-ver-resumo'),
              onPressed: controller.abrirResumoDeDecisoes,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Ver resumo das decisões'),
            ),
          ],
        ),
      ],
    );
  }
}

/// deixa claro, em toda a tela, que nada aqui
/// executa uma alteração real. Sem isso, os controles de decisão poderiam
/// parecer um botão operacional de confirmação definitiva (proibido pela
/// seção 10).
class _AvisoSomenteRevisao extends StatelessWidget {
  const _AvisoSomenteRevisao();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Modo Comparar e Atualizar (ADMIN) — esta tela só prepara e revisa decisões. '
                'Nenhuma alteração é enviada ao banco aqui: a execução será habilitada somente '
                'após a integração segura da próxima etapa.',
                style: TextStyle(color: colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoComparacao extends StatelessWidget {
  const _ResumoComparacao({required this.resumo});

  final ComparacaoResumo resumo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo da comparação', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text('Total analisado: ${resumo.totalLinhas}', key: const Key('comparacao-resumo-total')),
                Text('Divergentes: ${resumo.divergentes}', key: const Key('comparacao-resumo-divergentes')),
                Text('Novos: ${resumo.novos}', key: const Key('comparacao-resumo-novos')),
                Text('Bloqueados: ${resumo.bloqueados}', key: const Key('comparacao-resumo-bloqueados')),
              ],
            ),
            if (resumo.identicos > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                key: const Key('comparacao-aviso-identicos'),
                '${resumo.identicos} ${resumo.identicos == 1 ? 'patrimônio possui informações idênticas e foi' : 'patrimônios possuem informações idênticas e foram'} '
                'ignorados automaticamente.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (resumo.divergenciasPorCampo.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Divergências por campo', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final entry in resumo.divergenciasPorCampo.entries)
                    Chip(label: Text('${entry.key}: ${entry.value}')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FiltrosComparacao extends StatelessWidget {
  const _FiltrosComparacao({required this.state, required this.onFiltrar});

  final PatrimonioImportState state;
  final ValueChanged<ComparacaoFiltroRevisao> onFiltrar;

  /// Contagem de cada filtro respeitando a BUSCA atual (mas nunca o filtro
  /// em si — senão o próprio chip selecionado silenciaria os outros).
  int _contagemPara(ComparacaoFiltroRevisao filtro) {
    // `itensComparacaoFiltrados` é um getter puro: calcular a contagem de
    // outro filtro é só reconstruir o mesmo cálculo com um
    // `filtroComparacao` diferente, via `copyWith` (nunca muta [state]).
    return state.copyWith(filtroComparacao: filtro).itensComparacaoFiltrados.length;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final filtro in ComparacaoFiltroRevisao.values)
          FilterChip(
            key: Key('comparacao-filtro-${filtro.name}'),
            label: Text('${filtro.label}: ${_contagemPara(filtro)}'),
            selected: state.filtroComparacao == filtro,
            onSelected: (_) => onFiltrar(filtro),
          ),
      ],
    );
  }
}

class _AcoesEmMassa extends StatelessWidget {
  const _AcoesEmMassa({required this.controller});

  final PatrimonioImportController controller;

  void _executar(BuildContext context, String rotulo, int Function() acao) {
    final quantidade = acao();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          quantidade == 0
              ? 'Nenhuma decisão elegível foi afetada.'
              : '$rotulo: $quantidade ${quantidade == 1 ? 'decisão afetada' : 'decisões afetadas'}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton(
          key: const Key('comparacao-acao-selecionar-todos'),
          onPressed: () => _executar(context, 'Selecionar todos os elegíveis', controller.selecionarTodosOsElegiveis),
          child: const Text('Selecionar todos os elegíveis'),
        ),
        OutlinedButton(
          key: const Key('comparacao-acao-ignorar-todos'),
          onPressed: () => _executar(context, 'Ignorar todos os elegíveis', controller.ignorarTodosOsElegiveis),
          child: const Text('Ignorar todos os elegíveis'),
        ),
        OutlinedButton(
          key: const Key('comparacao-acao-so-localizacao'),
          onPressed: () =>
              _executar(context, 'Selecionar só localização/setor', controller.selecionarSomenteLocalizacaoOuSetor),
          child: const Text('Só localização/setor'),
        ),
        OutlinedButton(
          key: const Key('comparacao-acao-so-metadados'),
          onPressed: () => _executar(context, 'Selecionar só metadados', controller.selecionarSomenteMetadados),
          child: const Text('Só metadados'),
        ),
        OutlinedButton(
          key: const Key('comparacao-acao-limpar'),
          onPressed: () => _executar(context, 'Limpar decisões', controller.limparDecisoes),
          child: const Text('Limpar decisões'),
        ),
      ],
    );
  }
}

class _ItemComparacaoTile extends StatelessWidget {
  const _ItemComparacaoTile({required this.item, required this.state, required this.controller});

  final PatrimonioComparacao item;
  final PatrimonioImportState state;
  final PatrimonioImportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: Key('comparacao-item-${item.numeroLinha}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.numeroPatrimonio ?? '(sem número)',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _BadgeClassificacao(classificacao: item.classificacao),
            ],
          ),
          switch (item.classificacao) {
            ClassificacaoComparacao.novo => const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Número patrimonial novo — este modo NUNCA cadastra automaticamente; '
                'use a importação convencional para criar este patrimônio.',
              ),
            ),
            ClassificacaoComparacao.bloqueado => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                item.motivoBloqueio ?? 'Não é possível comparar este item com segurança.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            ClassificacaoComparacao.identico => const SizedBox.shrink(),
            ClassificacaoComparacao.divergente => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xs),
                for (final campo in item.divergencias) _CampoDivergenteTile(patrimonioId: item.patrimonioId!, campo: campo, state: state, controller: controller),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => controller.ignorarTodosOsCamposDoPatrimonio(item.patrimonioId!),
                    child: const Text('Ignorar todas as divergências deste patrimônio'),
                  ),
                ),
              ],
            ),
          },
          const Divider(),
        ],
      ),
    );
  }
}

class _BadgeClassificacao extends StatelessWidget {
  const _BadgeClassificacao({required this.classificacao});

  final ClassificacaoComparacao classificacao;

  @override
  Widget build(BuildContext context) {
    final (label, kind) = switch (classificacao) {
      ClassificacaoComparacao.identico => ('Idêntico', AppStatusKind.neutral),
      ClassificacaoComparacao.divergente => ('Divergente', AppStatusKind.warning),
      ClassificacaoComparacao.novo => ('Novo', AppStatusKind.info),
      ClassificacaoComparacao.bloqueado => ('Bloqueado', AppStatusKind.error),
    };
    return StatusChip(label: label, kind: kind);
  }
}

/// Comparação campo a campo (seção 4) — consome [CampoDivergente]
/// diretamente, sem recomparar nada. Mostra "InvTec" e "Planilha" sempre
/// rotulados e SEPARADOS (seção 9: nunca apresentar o valor da planilha
/// como se já fosse o valor atual do banco).
class _CampoDivergenteTile extends StatelessWidget {
  const _CampoDivergenteTile({
    required this.patrimonioId,
    required this.campo,
    required this.state,
    required this.controller,
  });

  final String patrimonioId;
  final CampoDivergente campo;
  final PatrimonioImportState state;
  final PatrimonioImportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decisao = state.decisaoDe(patrimonioId, campo.campo);

    return Container(
      key: Key('comparacao-campo-$patrimonioId-${campo.campo}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(campo.campo.toUpperCase(), style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('InvTec: ${campo.valorInvtec ?? '—'}'),
          Text('Planilha: ${campo.valorPlanilha ?? '—'}'),
          const SizedBox(height: AppSpacing.xs),
          if (campo.exigeResolucao)
            Text(
              'Resolução manual necessária antes de decidir este campo.',
              style: TextStyle(color: theme.colorScheme.error),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                ChoiceChip(
                  key: Key('comparacao-aplicar-$patrimonioId-${campo.campo}'),
                  label: const Text('Aplicar valor da planilha'),
                  selected: decisao == DecisaoCampoValor.aplicar,
                  onSelected: (_) => controller.decidirCampo(patrimonioId, campo.campo, DecisaoCampoValor.aplicar),
                ),
                ChoiceChip(
                  key: Key('comparacao-ignorar-$patrimonioId-${campo.campo}'),
                  label: const Text('Ignorar e manter atual'),
                  selected: decisao == DecisaoCampoValor.ignorar,
                  onSelected: (_) => controller.decidirCampo(patrimonioId, campo.campo, DecisaoCampoValor.ignorar),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
