import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/tombamento_historico_item.dart';

/// Timeline de trocas de tombamento de um patrimônio — somente leitura:
/// o histórico é imutável (mesma garantia de [PatrimonioHistoricoTimeline],
/// nunca uma ação de editar/excluir uma entrada).
///
/// Apresentação COMPACTA de propósito (pedido explícito — a versão
/// anterior mostrava a justificativa/evidência documental da Fase 2
/// direto na linha, poluindo a tela): cada entrada mostra só
/// "anterior → atual" + "origem resumida • data curta". Nenhum dado é
/// descartado — observação, data efetiva e hora completas continuam
/// intactas no Supabase e acessíveis via "Ver detalhes".
///
/// [itens] já vem ordenado por `sequencia` DESC (mais recente primeiro) —
/// este widget só exibe, nunca reordena.
class PatrimonioTombamentoHistoricoTimeline extends StatelessWidget {
  const PatrimonioTombamentoHistoricoTimeline({super.key, required this.itens});

  final List<TombamentoHistoricoItem> itens;

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

  final TombamentoHistoricoItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Valores BRUTOS, nunca normalizados — zeros à esquerda preservados
    // exatamente como estão em patrimonio_tombamentos_historico.
    final anterior = item.numeroAnterior ?? '(sem número)';
    final novo = item.numeroNovo ?? '(sem número)';

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
                  Text('$anterior → $novo', style: AppTypography.body(context)),
                  const SizedBox(height: 2),
                  // Linha resumida: origem curta + data (sem hora) — a
                  // hora e o resto da auditoria ficam em "Ver detalhes",
                  // nunca aqui. `Wrap` (não `Row`) para nunca sofrer
                  // overflow em telas estreitas (Android/Windows
                  // redimensionado).
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: 2,
                    children: [
                      Text(
                        '${origemTombamentoHistoricoLabel(item.origem)} • ${_formatarDataCurta(item.registradoEm)}',
                        style: AppTypography.caption(context),
                      ),
                      _VerDetalhesButton(item: item),
                    ],
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

class _VerDetalhesButton extends StatelessWidget {
  const _VerDetalhesButton({required this.item});

  final TombamentoHistoricoItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: TextButton(
        onPressed: () => _abrirDetalhes(context, item),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          visualDensity: VisualDensity.compact,
          minimumSize: Size.zero,
          textStyle: AppTypography.caption(context),
        ),
        child: const Text('Ver detalhes'),
      ),
    );
  }
}

Future<void> _abrirDetalhes(BuildContext context, TombamentoHistoricoItem item) {
  final anterior = item.numeroAnterior ?? '(sem número)';
  final novo = item.numeroNovo ?? '(sem número)';

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Detalhes do histórico de tombamento'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetalheCampo(label: 'Tombamento anterior → atual', valor: '$anterior → $novo'),
            _DetalheCampo(label: 'Origem', valor: origemTombamentoHistoricoLabel(item.origem)),
            // "Registrado em" — explicitamente QUANDO o evento foi GRAVADO
            // no InvTec, nunca apresentado como a data da troca física/
            // administrativa (ver doc de TombamentoHistoricoItem.registradoEm).
            _DetalheCampo(
              label: 'Registrado em',
              valor: _formatarDataHora(item.registradoEm),
            ),
            if (item.dataEfetivaAlteracao != null)
              _DetalheCampo(
                label: 'Troca efetiva em',
                valor: _formatarDataHora(item.dataEfetivaAlteracao!),
              ),
            if (item.observacao != null && item.observacao!.isNotEmpty)
              _DetalheCampo(label: 'Evidência / observação', valor: item.observacao!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

class _DetalheCampo extends StatelessWidget {
  const _DetalheCampo({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.auxiliary(context)),
          const SizedBox(height: 2),
          Text(valor, style: AppTypography.body(context)),
        ],
      ),
    );
  }
}

String _formatarDataCurta(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year}';
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} às ${pad(local.hour)}:${pad(local.minute)}';
}
