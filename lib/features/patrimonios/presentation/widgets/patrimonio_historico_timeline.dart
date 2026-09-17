import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../movimentacoes/domain/movimentacao.dart';
import '../../../movimentacoes/domain/movimentacao_historico_item.dart';

/// Timeline de movimentações de um patrimônio (PROMPT 9.3.2, seção 10) —
/// somente leitura: o histórico é imutável e esta tela nunca oferece uma
/// ação de editar/excluir uma entrada (ver docs/database.md, seção
/// "Histórico imutável").
class PatrimonioHistoricoTimeline extends StatelessWidget {
  const PatrimonioHistoricoTimeline({super.key, required this.itens});

  final List<MovimentacaoHistoricoItem> itens;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itens.length; i++)
          _TimelineEntry(item: itens[i], isLast: i == itens.length - 1),
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.item, required this.isLast});

  final MovimentacaoHistoricoItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origem = item.setorOrigemNome ?? '—';
    final destino = item.setorDestinoNome ?? '—';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: theme.colorScheme.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.tipo.label.toUpperCase(),
                    style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 2),
                  Text('$origem → $destino', style: AppTypography.body(context)),
                  if (item.localizacaoDestinoNome != null)
                    Text(
                      'Localização: ${item.localizacaoDestinoNome}',
                      style: AppTypography.auxiliary(context),
                    ),
                  if (item.responsavelDestino != null)
                    Text('Responsável: ${item.responsavelDestino}', style: AppTypography.auxiliary(context)),
                  const SizedBox(height: 2),
                  Text(_formatarDataHora(item.dataMovimentacao), style: AppTypography.caption(context)),
                  if (item.motivo != null && item.motivo!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(item.motivo!, style: AppTypography.auxiliary(context)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} às ${pad(local.hour)}:${pad(local.minute)}';
}
