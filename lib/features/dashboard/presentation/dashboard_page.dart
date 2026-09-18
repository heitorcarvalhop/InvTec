import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/stat_card.dart';
import '../domain/movimentacao_resumo.dart';
import '../../movimentacoes/domain/movimentacao.dart';
import '../../movimentacoes/presentation/widgets/movimentacao_tipo_visual.dart';
import 'dashboard_providers.dart';

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
      InvTecStatCard(
        label: 'Total de patrimônios',
        value: stats.total,
        icon: Icons.inventory_2_outlined,
        kind: AppStatusKind.neutral,
      ),
      InvTecStatCard(
        label: 'Disponíveis',
        value: stats.disponiveis,
        icon: Icons.check_circle_outline,
        kind: AppStatusKind.success,
      ),
      InvTecStatCard(
        label: 'Em uso',
        value: stats.emUso,
        icon: Icons.person_outline,
        kind: AppStatusKind.info,
      ),
      InvTecStatCard(
        label: 'Emprestados',
        value: stats.emprestados,
        icon: Icons.handshake_outlined,
        kind: AppStatusKind.warning,
      ),
      InvTecStatCard(
        label: 'Em manutenção',
        value: stats.emManutencao,
        icon: Icons.build_outlined,
        kind: AppStatusKind.warning,
      ),
      InvTecStatCard(
        label: 'Baixados',
        value: stats.baixados,
        icon: Icons.remove_circle_outline,
        kind: AppStatusKind.neutral,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const InvTecPageHeader(title: 'Dashboard', subtitle: 'Visão geral do patrimônio.'),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [for (final card in cards) SizedBox(width: 200, child: card)],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Movimentações recentes', style: AppTypography.cardTitle(context)),
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
        child: EmptyState(icon: Icons.history_outlined, message: 'Nenhuma movimentação registrada.'),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: movimentacoes.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) => _MovementRow(item: movimentacoes[index]),
      ),
    );
  }
}

class _MovementRow extends StatefulWidget {
  const _MovementRow({required this.item});

  final MovimentacaoResumo item;

  @override
  State<_MovementRow> createState() => _MovementRowState();
}

class _MovementRowState extends State<_MovementRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final statusColors = Theme.of(context).statusColors;
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);
    final (badgeBackground, badgeForeground) = switch (kind) {
      AppStatusKind.success => (statusColors.successBackground, statusColors.successForeground),
      AppStatusKind.warning => (statusColors.warningBackground, statusColors.warningForeground),
      AppStatusKind.error => (statusColors.errorBackground, statusColors.errorForeground),
      AppStatusKind.info => (statusColors.infoBackground, statusColors.infoForeground),
      AppStatusKind.neutral => (statusColors.neutralBackground, statusColors.neutralForeground),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: _hovering ? Theme.of(context).surfaceColors.rowHover : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smd),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: badgeBackground, borderRadius: BorderRadius.circular(AppRadius.sm)),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: badgeForeground),
            ),
            const SizedBox(width: AppSpacing.smd),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.patrimonioLabel, style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700)),
                  Text(item.tipo.label, style: AppTypography.auxiliary(context)),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                '${item.origemNome ?? '—'} → ${item.destinoNome ?? '—'}',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body(context),
              ),
            ),
            Text(_formatarData(item.dataMovimentacao), style: AppTypography.caption(context)),
          ],
        ),
      ),
    );
  }
}

String _formatarData(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}
