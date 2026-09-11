import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../domain/movimentacao_resumo.dart';
import '../../movimentacoes/domain/movimentacao.dart';
import 'dashboard_providers.dart';
import 'widgets/dashboard_stat_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider);

    return dashboardAsync.when(
      data: (data) => _DashboardContent(data: data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: EmptyState(
          icon: Icons.error_outline,
          message: 'Não foi possível carregar os dados do dashboard.',
          actionLabel: 'Tentar novamente',
          onAction: () => ref.invalidate(dashboardDataProvider),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final stats = data.stats;

    final cards = [
      DashboardStatCard(
        label: 'Total de patrimônios',
        value: stats.total,
        icon: Icons.inventory_2_outlined,
      ),
      DashboardStatCard(
        label: 'Patrimônios ativos',
        value: stats.ativos,
        icon: Icons.check_circle_outline,
      ),
      DashboardStatCard(
        label: 'Em uso',
        value: stats.emUso,
        icon: Icons.person_outline,
      ),
      DashboardStatCard(
        label: 'Emprestados',
        value: stats.emprestados,
        icon: Icons.handshake_outlined,
      ),
      DashboardStatCard(
        label: 'Em manutenção',
        value: stats.emManutencao,
        icon: Icons.build_outlined,
      ),
      DashboardStatCard(
        label: 'Baixados',
        value: stats.baixados,
        icon: Icons.remove_circle_outline,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final card in cards) SizedBox(width: 200, child: card),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Movimentações recentes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            _RecentMovements(movimentacoes: data.movimentacoesRecentes),
          ],
        ),
      ),
    );
  }
}

class _RecentMovements extends StatelessWidget {
  const _RecentMovements({required this.movimentacoes});

  final List<MovimentacaoResumo> movimentacoes;

  @override
  Widget build(BuildContext context) {
    if (movimentacoes.isEmpty) {
      return const Card(
        child: EmptyState(
          icon: Icons.history_outlined,
          message: 'Nenhuma movimentação registrada.',
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: movimentacoes.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = movimentacoes[index];
          return ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text('${item.patrimonioLabel} · ${item.tipo.label}'),
            subtitle: Text(
              '${item.origemNome ?? '—'} → ${item.destinoNome ?? '—'}',
            ),
            trailing: Text(
              _formatarData(item.dataMovimentacao),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    );
  }
}

String _formatarData(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}
