import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'status_chip.dart';

/// Card de métrica (ícone + valor + descrição) usado no Dashboard. [kind]
/// tinge só o pequeno badge do ícone com uma cor contextual discreta
/// (nunca o card inteiro), coerente com o resto dos status da aplicação.
///
/// [onTap] é opcional: quando informado, o card todo fica clicável (cursor
/// de ponteiro + highlight de hover/toque, via [InkWell]) — usado pelos
/// cards do Dashboard que têm uma rota de destino natural (ex.: "Patrimônios"
/// → `/patrimonios`). Sem destino, o card permanece estático: nunca fica
/// com aparência clicável sem navegar para lugar nenhum.
class InvTecStatCard extends StatelessWidget {
  const InvTecStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.kind = AppStatusKind.info,
    this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final AppStatusKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).statusColors;
    final (tintBackground, tintForeground) = switch (kind) {
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

    // Card "principal" de destaque do Dashboard: raio um pouco maior
    // (AppRadius.lg) que o padrão de card do app (AppRadius.md, usado em
    // formulários/tabelas/dialogs) para reforçar a hierarquia visual sem
    // alterar o `cardTheme` global. Mesma cor/borda do tema, só o raio muda.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: Theme.of(context).surfaceColors.border),
    );

    // Mobile (Fase 2 — densidade): o mesmo card em 2 colunas numa tela de
    // ~390px fica alto demais com o padding/ícone do desktop — aqui só o
    // "chrome" ao redor (padding, caixa do ícone, gaps) encolhe; o número
    // (`AppTypography.metric`) e o rótulo continuam do mesmo tamanho de
    // fonte, legibilidade preservada.
    final mobile = context.screenSize == ScreenSize.mobile;
    final iconBoxSize = mobile ? 28.0 : 36.0;
    final iconSize = mobile ? 15.0 : 18.0;

    final conteudo = Padding(
      padding: EdgeInsets.all(mobile ? AppSpacing.smd : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
              color: tintBackground,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: iconSize, color: tintForeground),
          ),
          SizedBox(height: mobile ? AppSpacing.xs : AppSpacing.sm),
          Text('$value', style: AppTypography.metric(context)),
          const SizedBox(height: AppSpacing.xs),
          // Label em estilo "eyebrow" (menor, tracking amplo) — fica
          // acima/abaixo do número como metadado discreto, sem precisar de
          // caixa alta (o rótulo em português tende a ficar mais longo que
          // o padrão de referência e perde legibilidade em CAPS).
          Text(label, style: AppTypography.eyebrow(context)),
        ],
      ),
    );

    return Card(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? conteudo
          : InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              child: conteudo,
            ),
    );
  }
}
