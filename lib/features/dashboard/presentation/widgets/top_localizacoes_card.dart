import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/categoria_contagem.dart';
import 'dashboard_section_header.dart';

/// "Locais com mais patrimônios": lista numerada (1º, 2º, 3º...), sem
/// barra — forma visual diferente de [CategoriaBarrasCard] de propósito,
/// para distinguir "ranking de lugares" de "distribuição por categoria".
/// Sem navegação ao clicar: o filtro de Patrimônios por localização ainda
/// não aceita um valor inicial vindo de outra tela (ver relatório, item de
/// melhoria futura) — não vale a pena uma navegação frágil.
class TopLocalizacoesCard extends StatelessWidget {
  const TopLocalizacoesCard({super.key, required this.itens});

  final List<CategoriaContagem> itens;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: Theme.of(context).surfaceColors.border),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardSectionHeader(title: 'Locais com mais patrimônios'),
        const SizedBox(height: AppSpacing.sm),
        Card(
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: itens.isEmpty
              ? const EmptyState(icon: Icons.place_outlined, message: 'Nenhuma localização com patrimônio.')
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: itens.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = itens[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${index + 1}º',
                              style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(item.nome, style: AppTypography.body(context), overflow: TextOverflow.ellipsis),
                          ),
                          Text(
                            '${item.quantidade}',
                            style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
