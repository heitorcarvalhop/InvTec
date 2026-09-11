import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/patrimonio_detalhe.dart';
import 'patrimonio_status_chip.dart';

/// Lista estruturada (não `DataTable`, para não sofrer overflow horizontal
/// em janelas estreitas — cada célula usa `Expanded` normal).
class PatrimonioDesktopTable extends StatelessWidget {
  const PatrimonioDesktopTable({
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          const Divider(height: 1),
          for (var i = 0; i < itens.length; i++) ...[
            _DataRow(
              detalhe: itens[i],
              canManage: canManage,
              onTap: () => onTap(itens[i]),
              onEdit: () => onEdit(itens[i]),
            ),
            if (i < itens.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Patrimônio', style: style)),
          Expanded(flex: 2, child: Text('Tipo', style: style)),
          Expanded(flex: 3, child: Text('Equipamento', style: style)),
          Expanded(flex: 2, child: Text('Número de série', style: style)),
          Expanded(flex: 2, child: Text('Setor atual', style: style)),
          Expanded(flex: 2, child: Text('Responsável', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          Expanded(flex: 1, child: Text('Ações', style: style)),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.detalhe,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
  });

  final PatrimonioDetalhe detalhe;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final patrimonio = detalhe.patrimonio;
    final equipamento = [
      patrimonio.marca,
      patrimonio.modelo,
    ].where((v) => v != null && v.isNotEmpty).join(' ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                patrimonio.numeroPatrimonio ?? '—',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(detalhe.tipoNome, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 3,
              child: Text(
                equipamento.isEmpty ? '—' : equipamento,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                patrimonio.numeroSerie ?? '—',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(detalhe.setorNome, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 2,
              child: Text(
                patrimonio.responsavelAtual ?? '—',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: PatrimonioStatusChip(status: patrimonio.status),
            ),
            Expanded(
              flex: 1,
              child: canManage
                  ? IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: onEdit,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
