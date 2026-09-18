import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/setor.dart';
import 'setor_status_chip.dart';

/// Lista estruturada (não `DataTable`, para não sofrer overflow horizontal
/// em janelas estreitas — cada célula usa `Expanded`/`Flexible` normais).
class SetorDesktopTable extends StatelessWidget {
  const SetorDesktopTable({
    super.key,
    required this.setores,
    required this.canManage,
    required this.onEdit,
    required this.onToggleAtivo,
    required this.onLocalizacoes,
  });

  final List<Setor> setores;
  final bool canManage;
  final ValueChanged<Setor> onEdit;
  final ValueChanged<Setor> onToggleAtivo;
  final ValueChanged<Setor> onLocalizacoes;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          const Divider(height: 1),
          for (var i = 0; i < setores.length; i++) ...[
            _DataRow(
              setor: setores[i],
              canManage: canManage,
              onEdit: () => onEdit(setores[i]),
              onToggleAtivo: () => onToggleAtivo(setores[i]),
              onLocalizacoes: () => onLocalizacoes(setores[i]),
            ),
            if (i < setores.length - 1) const Divider(height: 1),
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
    return Container(
      color: Theme.of(context).surfaceColors.tableHeader,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Sigla', style: style)),
          Expanded(flex: 4, child: Text('Nome', style: style)),
          Expanded(flex: 4, child: Text('Descrição', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          Expanded(flex: 4, child: Text('Ações', style: style)),
        ],
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({
    required this.setor,
    required this.canManage,
    required this.onEdit,
    required this.onToggleAtivo,
    required this.onLocalizacoes,
  });

  final Setor setor;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggleAtivo;
  final VoidCallback onLocalizacoes;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final setor = widget.setor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: _hovering ? Theme.of(context).surfaceColors.rowHover : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(setor.sigla ?? '—', overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 4,
              child: Text(setor.nome, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 4,
              child: Text(
                (setor.descricao == null || setor.descricao!.isEmpty)
                    ? '—'
                    : setor.descricao!,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SetorStatusChip(ativo: setor.ativo),
              ),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Tooltip(
                    message: 'Localizações',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.place_outlined),
                      onPressed: widget.onLocalizacoes,
                    ),
                  ),
                  if (widget.canManage) ...[
                    Tooltip(
                      message: 'Editar',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: widget.onEdit,
                      ),
                    ),
                    Tooltip(
                      message: setor.ativo ? 'Desativar' : 'Reativar',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          setor.ativo
                              ? Icons.block_outlined
                              : Icons.check_circle_outline,
                        ),
                        onPressed: widget.onToggleAtivo,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
