import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/page_header.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import 'dashboard_providers.dart';
import 'widgets/admin_attention_card.dart';
import 'widgets/categoria_barras_card.dart';
import 'widgets/dashboard_kpi_row.dart';
import 'widgets/distribuicao_async_card.dart';
import 'widgets/movimentacoes_recentes_card.dart';
import 'widgets/quick_actions_card.dart';
import 'widgets/top_localizacoes_card.dart';

/// Dashboard 3.0: central operacional do InvTec — cada seção carrega (e
/// falha) de forma independente, só aparece se a permissão efetiva do
/// usuário atual permitir, e nunca inventa um número que o banco atual
/// não consegue fornecer (ver docs do pedido original). Sem
/// `ConsumerWidget` único cobrindo tudo: cada seção é seu próprio
/// `ConsumerWidget`/provider — uma falha isolada numa seção nunca derruba
/// as outras.
///
/// Hierarquia (refinamento visual): KPIs → Ações rápidas (logo abaixo,
/// área de maior uso diário) → Atenção ADMIN (quando aplicável) → área
/// operacional em duas colunas INDEPENDENTES (~60/40): a coluna principal
/// (Movimentações recentes + Patrimônios por setor) nunca é forçada a
/// crescer para acompanhar a coluna secundária (Patrimônios por tipo + Top
/// localizações) — é exatamente esse pareamento lado a lado de conteúdos
/// com alturas diferentes que antes deixava "Patrimônios por setor" com um
/// vão vazio enorme quando havia só 1 setor; aqui cada coluna soma a
/// altura dos seus próprios cards, sem nivelar com a outra.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(authControllerProvider).value?.profile?.perfil ==
        ProfilePerfil.admin;

    // Mobile (Fase 2 — densidade): mesma hierarquia de seções do desktop,
    // só com padding/gaps verticais menores entre elas — nenhuma seção é
    // removida/reordenada.
    final mobile = context.screenSize == ScreenSize.mobile;
    final gapEntreSecoes = mobile ? AppSpacing.md : AppSpacing.lg;

    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? AppSpacing.md : AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvTecPageHeader(
              title: 'Dashboard',
              subtitle: 'Visão geral do patrimônio da GETEC',
              actions: const [_UpdatedAtLabel()],
            ),
            SizedBox(height: gapEntreSecoes),
            const DashboardKpiRow(),
            SizedBox(height: gapEntreSecoes),
            const QuickActionsCard(),
            if (isAdmin) ...[
              SizedBox(height: gapEntreSecoes),
              const AdminAttentionCard(),
            ],
            SizedBox(height: mobile ? AppSpacing.lg : AppSpacing.xl),
            _TwoColumnRow(
              leftFlex: 3,
              rightFlex: 2,
              left: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MovimentacoesRecentesCard(),
                  SizedBox(height: mobile ? AppSpacing.lg : AppSpacing.xl),
                  DistribuicaoAsyncCard(
                    builder: (d) => CategoriaBarrasCard(
                      titulo: 'Patrimônios por setor',
                      itens: d.porSetor,
                      total: d.totalConsiderado,
                      corBarra: Theme.of(context).dataVizColors.cyan,
                      mensagemVazio: 'Nenhum patrimônio cadastrado.',
                    ),
                  ),
                ],
              ),
              right: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DistribuicaoAsyncCard(
                    builder: (d) => CategoriaBarrasCard(
                      titulo: 'Patrimônios por tipo',
                      itens: d.porTipo,
                      total: d.totalConsiderado,
                      corBarra: Theme.of(context).dataVizColors.teal,
                      mensagemVazio: 'Nenhum patrimônio cadastrado.',
                    ),
                  ),
                  SizedBox(height: mobile ? AppSpacing.lg : AppSpacing.xl),
                  DistribuicaoAsyncCard(
                    builder: (d) =>
                        TopLocalizacoesCard(itens: d.topLocalizacoes),
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

/// Indicador discreto de "última carga" (seção 3 do pedido) — sem polling:
/// só mostra a hora em que [dashboardKpisProvider] resolveu com sucesso da
/// última vez (recalculada quando o provider é invalidado/recarregado,
/// nunca por um timer).
class _UpdatedAtLabel extends ConsumerWidget {
  const _UpdatedAtLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(dashboardKpisProvider);
    return kpisAsync.when(
      data: (_) => Text(
        'Atualizado às ${_horaAtual()}',
        style: AppTypography.caption(context),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

String _horaAtual() {
  final agora = DateTime.now();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(agora.hour)}:${pad(agora.minute)}';
}

/// Duas colunas lado a lado em telas largas, empilhadas em telas estreitas
/// — mesmo padrão de largura mínima usado pela faixa de KPIs (nunca
/// scroll horizontal; ver seção 12 do pedido). [leftFlex]/[rightFlex]
/// permitem uma proporção assimétrica (~60/40 para a área operacional,
/// onde a coluna de Movimentações recentes merece mais destaque) sem
/// forçar as DUAS colunas a crescerem até a mesma altura — cada
/// `Expanded` só reparte LARGURA; a altura de cada coluna continua sendo a
/// soma natural do conteúdo dela.
class _TwoColumnRow extends StatelessWidget {
  const _TwoColumnRow({
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;

  static const _larguraMinimaDuasColunas = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _larguraMinimaDuasColunas) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: leftFlex, child: left),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: rightFlex, child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            left,
            // Mobile (Fase 2 — densidade): gap menor entre as duas colunas
            // empilhadas do que o usado quando é só o tablet empilhando
            // (mobile já reduziu outros gaps da página, este acompanha).
            SizedBox(
              height: context.screenSize == ScreenSize.mobile
                  ? AppSpacing.lg
                  : AppSpacing.xl,
            ),
            right,
          ],
        );
      },
    );
  }
}
