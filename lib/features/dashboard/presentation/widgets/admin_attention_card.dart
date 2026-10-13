import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../dashboard_providers.dart';
import 'dashboard_async_section.dart';

/// "Atenção": só para ADMIN (ver [dashboardAtencaoAdminProvider] — oculto
/// por inteiro para qualquer outro perfil). Quando não há nenhuma
/// pendência, mostra um estado discreto em vez de desaparecer (seção 10 do
/// pedido: "preferência por esconder OU mostrar estado discreto — escolher
/// o que gerar melhor composição visual"; aqui, ao lado de "Ações
/// rápidas" no grid, escondido deixaria um buraco visual).
class AdminAttentionCard extends ConsumerWidget {
  const AdminAttentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dashboardAtencaoAdminProvider);

    return dashboardAsyncSection<DashboardAtencaoAdmin>(
      value: value,
      onRetry: () => ref.invalidate(dashboardAtencaoAdminProvider),
      minHeight: 72,
      builder: (atencao) => _Conteudo(atencao: atencao),
    );
  }
}

/// Visual de "aviso operacional" compacto (seção 4 do pedido de
/// refinamento) — um único card baixo com ícone + título inline, em vez do
/// antigo cabeçalho de seção separado + card grande por baixo.
class _Conteudo extends StatelessWidget {
  const _Conteudo({required this.atencao});

  final DashboardAtencaoAdmin atencao;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: Theme.of(context).surfaceColors.border),
    );

    return Card(
      shape: shape,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 18,
              color: Theme.of(context).statusColors.warningForeground,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Atenção', style: AppTypography.cardTitle(context)),
                  const SizedBox(height: AppSpacing.xs),
                  if (atencao.temAlgo) ...[
                    if (atencao.solicitacoesPendentes > 0)
                      _ItemAtencao(
                        icon: Icons.person_add_alt_outlined,
                        texto: atencao.solicitacoesPendentes == 1
                            ? '1 solicitação de acesso aguardando aprovação'
                            : '${atencao.solicitacoesPendentes} solicitações de acesso aguardando aprovação',
                        onTap: () => context.go('/administracao/usuarios'),
                      ),
                    if (atencao.solicitacoesPendentes > 0 &&
                        atencao.notificacoesNaoLidas > 0)
                      const SizedBox(height: AppSpacing.xs),
                    if (atencao.notificacoesNaoLidas > 0)
                      _ItemAtencao(
                        icon: Icons.notifications_outlined,
                        texto: atencao.notificacoesNaoLidas == 1
                            ? '1 notificação não lida'
                            : '${atencao.notificacoesNaoLidas} notificações não lidas',
                      ),
                  ] else
                    Text(
                      'Nenhuma pendência no momento.',
                      style: AppTypography.body(context)?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemAtencao extends StatelessWidget {
  const _ItemAtencao({required this.icon, required this.texto, this.onTap});

  final IconData icon;
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final linha = Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).statusColors.warningForeground,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(texto, style: AppTypography.body(context))),
        if (onTap != null) const Icon(Icons.chevron_right, size: 18),
      ],
    );

    if (onTap == null) return linha;
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: linha,
      ),
    );
  }
}
