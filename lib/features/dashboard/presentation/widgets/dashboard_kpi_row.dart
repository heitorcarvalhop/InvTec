import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../domain/dashboard_kpis.dart';
import '../dashboard_providers.dart';
import 'dashboard_async_section.dart';

/// Primeira faixa do Dashboard: até 5 contagens (seção 4 do pedido), cada
/// uma só aparecendo se o usuário atual tiver a permissão correspondente
/// ([DashboardKpis], já filtrado por permissão em [dashboardKpisProvider]).
/// "Setores" e "Patrimônios" navegam para a respectiva página (destino
/// natural existente); "Localizações" e "Tipos" não têm uma rota própria
/// hoje (localizações vivem dentro de Setores, tipos não têm tela de
/// gestão) — ficam não clicáveis em vez de uma navegação frágil.
class DashboardKpiRow extends ConsumerWidget {
  const DashboardKpiRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(dashboardKpisProvider);

    return dashboardAsyncSection<DashboardKpis>(
      value: kpisAsync,
      onRetry: () => ref.invalidate(dashboardKpisProvider),
      minHeight: 96,
      builder: (kpis) {
        final cards = <Widget>[
          if (kpis.totalPatrimonios != null)
            InvTecStatCard(
              label: 'Patrimônios',
              value: kpis.totalPatrimonios!,
              icon: Icons.inventory_2_outlined,
              kind: AppStatusKind.info,
              onTap: () => context.go('/patrimonios'),
            ),
          if (kpis.totalSetores != null)
            InvTecStatCard(
              label: 'Setores',
              value: kpis.totalSetores!,
              icon: Icons.apartment_outlined,
              kind: AppStatusKind.neutral,
              onTap: () => context.go('/setores'),
            ),
          if (kpis.totalLocalizacoes != null)
            InvTecStatCard(
              label: 'Localizações',
              value: kpis.totalLocalizacoes!,
              icon: Icons.place_outlined,
              kind: AppStatusKind.neutral,
            ),
          if (kpis.totalTipos != null)
            InvTecStatCard(
              label: 'Tipos',
              value: kpis.totalTipos!,
              icon: Icons.category_outlined,
              kind: AppStatusKind.neutral,
            ),
          if (kpis.movimentacoesUltimos30Dias != null)
            InvTecStatCard(
              label: 'Movimentações (30 dias)',
              value: kpis.movimentacoesUltimos30Dias!,
              icon: Icons.swap_horiz_outlined,
              kind: AppStatusKind.success,
              onTap: () => context.go('/movimentacoes'),
            ),
        ];

        if (cards.isEmpty) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            // Mobile (melhoria de interface Android): a faixa de KPIs cabia
            // em só 1 coluna em telas de celular reais (~360-412px — depois
            // do padding da página, `constraints.maxWidth` fica abaixo dos
            // 420px que `_colunas` normalmente exige para liberar 2
            // colunas), empilhando até 5 cards em 5 linhas inteiras e
            // ocupando espaço vertical excessivo. Em telas de celular,
            // sempre 2 colunas (nunca a faixa de largura do desktop/tablet,
            // que já funciona bem) — "Windows" não é afetado: a janela
            // precisaria ser redimensionada para menos de 600px de largura
            // para cair neste caso, o mesmo limiar que "Ações rápidas" já
            // usa para a própria grade mobile.
            final mobile = context.screenSize == ScreenSize.mobile;
            final colunas = mobile
                ? (cards.length <= 1 ? 1 : 2)
                : _colunas(constraints.maxWidth, cards.length);
            final espacamento = mobile ? AppSpacing.sm : AppSpacing.md;
            final espacamentoTotal = espacamento * (colunas - 1);
            final largura = (constraints.maxWidth - espacamentoTotal) / colunas;
            return Wrap(
              spacing: espacamento,
              runSpacing: espacamento,
              children: [for (final card in cards) SizedBox(width: largura, child: card)],
            );
          },
        );
      },
    );
  }
}

/// Faixas discretas de largura (nunca "o quanto couber") combinadas com
/// [total] (varia de 1 a 5, conforme quantos KPIs o usuário pode ver) para
/// nunca deixar exatamente 1 card sozinho na última linha.
int _colunas(double larguraDisponivel, int total) {
  if (total <= 0) return 1;

  int maximo;
  if (larguraDisponivel >= 1100) {
    maximo = 5;
  } else if (larguraDisponivel >= 700) {
    maximo = 3;
  } else if (larguraDisponivel >= 420) {
    maximo = 2;
  } else {
    maximo = 1;
  }
  if (total <= maximo) return total;

  var colunas = maximo;
  if (total % colunas == 1 && colunas > 1) colunas -= 1;
  return colunas;
}
