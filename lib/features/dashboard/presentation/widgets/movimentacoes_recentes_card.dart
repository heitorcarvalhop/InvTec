import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/utils/setor_display.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../movimentacoes/domain/movimentacao.dart';
import '../../../movimentacoes/presentation/widgets/movimentacao_tipo_visual.dart';
import '../../domain/movimentacao_resumo.dart';
import '../dashboard_providers.dart';
import 'dashboard_async_section.dart';
import 'dashboard_section_header.dart';
import 'movimentacao_resumo_dialog.dart';

/// "Movimentações recentes" — oculto por inteiro (nunca "vazio") quando o
/// usuário não tem `movimentacao.view` (ver [dashboardMovimentacoesRecentesProvider]).
class MovimentacoesRecentesCard extends ConsumerWidget {
  const MovimentacoesRecentesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dashboardMovimentacoesRecentesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionHeader(
          title: 'Movimentações recentes',
          trailing: TextButton(
            onPressed: () => context.go('/movimentacoes'),
            child: const Text('Ver todas'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        dashboardAsyncSection<List<MovimentacaoResumo>>(
          value: value,
          onRetry: () => ref.invalidate(dashboardMovimentacoesRecentesProvider),
          builder: (movimentacoes) => _Lista(movimentacoes: movimentacoes),
        ),
      ],
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.movimentacoes});

  final List<MovimentacaoResumo> movimentacoes;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: Theme.of(context).surfaceColors.border),
    );

    if (movimentacoes.isEmpty) {
      return Card(
        shape: shape,
        child: const EmptyState(
          icon: Icons.history_outlined,
          message: 'Nenhuma movimentação registrada.',
        ),
      );
    }

    return Card(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: movimentacoes.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            _MovementRow(item: movimentacoes[index]),
      ),
    );
  }
}

/// Cada linha abre [showMovimentacaoResumoDialog] ao clicar — zero consulta
/// extra, usa só os campos que [MovimentacaoResumo] já trouxe (ver seção 7
/// do pedido de refinamento). `InkWell` (em vez do antigo
/// `MouseRegion`+`setState` manual) já dá hover discreto, foco de teclado e
/// ativação por Enter/Espaço de fábrica (seção 8).
class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.item});

  final MovimentacaoResumo item;

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).statusColors;
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);
    final (badgeBackground, badgeForeground) = switch (kind) {
      AppStatusKind.success => (
        statusColors.successBackground,
        statusColors.successForeground,
      ),
      AppStatusKind.warning => (
        statusColors.warningBackground,
        statusColors.warningForeground,
      ),
      AppStatusKind.error => (
        statusColors.errorBackground,
        statusColors.errorForeground,
      ),
      AppStatusKind.info => (
        statusColors.infoBackground,
        statusColors.infoForeground,
      ),
      AppStatusKind.neutral => (
        statusColors.neutralBackground,
        statusColors.neutralForeground,
      ),
    };

    return InkWell(
      onTap: () => showMovimentacaoResumoDialog(context, item),
      hoverColor: Theme.of(context).surfaceColors.rowHover,
      mouseCursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: badgeBackground,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: badgeForeground),
            ),
            const SizedBox(width: AppSpacing.smd),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.patrimonioLabel,
                    style: AppTypography.body(
                      context,
                    )?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    item.tipo.label,
                    style: AppTypography.auxiliary(context),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${siglaOuNomeSetor(sigla: item.origemSigla, nome: item.origemNome) ?? '—'} → '
                    '${siglaOuNomeSetor(sigla: item.destinoSigla, nome: item.destinoNome) ?? '—'}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                  if (item.autorNome != null)
                    Text(
                      'por ${item.autorNome}',
                      style: AppTypography.auxiliary(context),
                    ),
                ],
              ),
            ),
            Text(
              _formatarData(item.dataMovimentacao),
              style: AppTypography.caption(context),
            ),
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
