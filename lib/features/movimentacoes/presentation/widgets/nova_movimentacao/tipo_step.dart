import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../patrimonios/domain/patrimonio.dart';
import '../../../domain/movimentacao.dart';
import '../../nova_movimentacao_regras.dart';
import '../movimentacao_tipo_visual.dart';

/// Passo 2 do wizard (PROMPT 10.2, seção 5): só oferece tipos que a matriz
/// de transição documentada permite para o status ATUAL do patrimônio —
/// puramente cosmético (item 16 do prompt): a RPC valida de novo e é quem
/// decide de verdade.
class TipoStep extends StatelessWidget {
  const TipoStep({super.key, required this.status, required this.selecionado, required this.onSelecionar});

  final PatrimonioStatus status;
  final MovimentacaoTipo? selecionado;
  final ValueChanged<MovimentacaoTipo> onSelecionar;

  @override
  Widget build(BuildContext context) {
    final tipos = tiposCompativeisComStatus(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de movimentação', style: AppTypography.pageSubtitle(context)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Status atual do patrimônio: ${status.label}.',
          style: AppTypography.auxiliary(context),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < tipos.length; i++) ...[
                _TipoTile(
                  tipo: tipos[i],
                  selecionado: tipos[i] == selecionado,
                  onTap: () => onSelecionar(tipos[i]),
                ),
                if (i < tipos.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TipoTile extends StatelessWidget {
  const _TipoTile({required this.tipo, required this.selecionado, required this.onTap});

  final MovimentacaoTipo tipo;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, _) = visualDoTipoMovimentacao(tipo);
    return ListTile(
      leading: Icon(icon),
      title: Text(tipo.label),
      trailing: selecionado ? const Icon(Icons.check_circle) : null,
      selected: selecionado,
      onTap: onTap,
    );
  }
}
