import 'package:flutter/material.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/categoria_contagem.dart';
import 'dashboard_section_header.dart';

/// "Patrimônios por setor" / "Patrimônios por tipo": barras horizontais
/// compactas construídas só com widgets nativos (sem biblioteca de
/// gráficos — seção 21 do pedido), nome + quantidade + percentual do
/// [total]. [itens] já vem ordenado e recortado (Top N) por quem chama.
class CategoriaBarrasCard extends StatelessWidget {
  const CategoriaBarrasCard({
    super.key,
    required this.titulo,
    required this.itens,
    required this.total,
    required this.corBarra,
    required this.mensagemVazio,
  });

  final String titulo;
  final List<CategoriaContagem> itens;
  final int total;
  final Color corBarra;
  final String mensagemVazio;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: Theme.of(context).surfaceColors.border),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardSectionHeader(title: titulo),
        const SizedBox(height: AppSpacing.sm),
        Card(
          shape: shape,
          child: itens.isEmpty
              ? EmptyState(icon: Icons.inventory_2_outlined, message: mensagemVazio)
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      for (var i = 0; i < itens.length; i++) ...[
                        _BarraItem(item: itens[i], total: total, cor: corBarra),
                        if (i < itens.length - 1) const SizedBox(height: AppSpacing.smd),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _BarraItem extends StatelessWidget {
  const _BarraItem({required this.item, required this.total, required this.cor});

  final CategoriaContagem item;
  final int total;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final fracao = total <= 0 ? 0.0 : (item.quantidade / total).clamp(0.0, 1.0);
    final percentual = total <= 0 ? 0 : (item.quantidade / total * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(item.nome, style: AppTypography.body(context), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${item.quantidade} · $percentual%',
              style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(height: 8, color: Theme.of(context).surfaceColors.tableHeader),
                  Container(height: 8, width: constraints.maxWidth * fracao, color: cor),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
