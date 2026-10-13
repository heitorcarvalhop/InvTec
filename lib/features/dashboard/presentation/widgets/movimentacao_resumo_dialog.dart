import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/setor_display.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../movimentacoes/domain/movimentacao.dart';
import '../../../movimentacoes/presentation/widgets/movimentacao_tipo_visual.dart';
import '../../domain/movimentacao_resumo.dart';

/// Resumo rápido de uma movimentação, aberto ao clicar numa linha de
/// "Movimentações recentes" — usa só os campos que [MovimentacaoResumo] já
/// trouxe para o Dashboard (NENHUMA consulta extra: a listagem recente já
/// buscou isto). "Ver movimentação completa" é quem, só então, busca o
/// restante dos dados (por id) ao navegar para `/movimentacoes/:id`.
Future<void> showMovimentacaoResumoDialog(
  BuildContext context,
  MovimentacaoResumo item,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => MovimentacaoResumoDialog(item: item),
  );
}

class MovimentacaoResumoDialog extends StatelessWidget {
  const MovimentacaoResumoDialog({super.key, required this.item});

  final MovimentacaoResumo item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);
    final origem = siglaOuNomeSetor(
      sigla: item.origemSigla,
      nome: item.origemNome,
    );
    final destino = siglaOuNomeSetor(
      sigla: item.destinoSigla,
      nome: item.destinoNome,
    );

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Movimentação',
                      style: AppTypography.pageSubtitle(context),
                    ),
                  ),
                  StatusChip(label: item.tipo.label, kind: kind, icon: icon),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Field(label: 'Patrimônio', value: item.patrimonioLabel),
              if (origem != null) _Field(label: 'Origem', value: origem),
              if (destino != null) _Field(label: 'Destino', value: destino),
              if (item.autorNome != null)
                _Field(label: 'Realizado por', value: item.autorNome!),
              _Field(
                label: 'Data',
                value: _formatarDataHora(item.dataMovimentacao),
              ),
              const SizedBox(height: AppSpacing.sm),
              // `Wrap` (não `Row`) porque "Ver movimentação completa" é um
              // rótulo longo e o diálogo é compacto de propósito (420px) —
              // num espaço mais estreito, o botão quebra para a linha de
              // baixo em vez de estourar a largura do diálogo.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go('/movimentacoes/${item.id}');
                    },
                    child: const Text('Ver movimentação completa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.auxiliary(context)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body(context)),
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
