import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/patrimonio_detalhe.dart';
import 'patrimonio_mobile_list.dart';

/// Grid responsivo da visualização "Cards" de Patrimônios — usa EXATAMENTE
/// [itens] (já paginado pelo servidor, ver [PatrimoniosController]), nunca
/// busca itens extras só para preencher a última linha. Mesmo espírito do
/// grid de stat cards do Dashboard (`_colunasDeStatCards`): faixas discretas
/// de largura, nunca "o quanto couber" — evita tanto uma única coluna
/// sobrando sozinha quanto cards espremidos demais para caber todos numa
/// linha.
class PatrimonioCardsGrid extends StatelessWidget {
  const PatrimonioCardsGrid({
    super.key,
    required this.itens,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
  });

  final List<PatrimonioDetalhe> itens;
  final bool canManage;
  final ValueChanged<PatrimonioDetalhe> onTap;
  final ValueChanged<PatrimonioDetalhe> onEdit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = _colunas(constraints.maxWidth);
        final espacamentoTotal = AppSpacing.md * (colunas - 1);
        final largura = (constraints.maxWidth - espacamentoTotal) / colunas;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: PatrimonioCard(
                  detalhe: item,
                  canManage: canManage,
                  onTap: () => onTap(item),
                  onEdit: () => onEdit(item),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Colunas por faixa de largura disponível: desktop largo ~4, desktop comum
/// ~3, tablet ~2, estreito 1 — com uma largura mínima coerente por card
/// (nunca espremido), análogo a `_colunasDeStatCards` do Dashboard.
int _colunas(double larguraDisponivel) {
  if (larguraDisponivel >= 1200) return 4;
  if (larguraDisponivel >= 900) return 3;
  if (larguraDisponivel >= 560) return 2;
  return 1;
}
