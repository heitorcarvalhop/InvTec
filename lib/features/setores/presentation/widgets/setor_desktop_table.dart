import 'package:flutter/material.dart';

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
  });

  final List<Setor> setores;
  final bool canManage;
  final ValueChanged<Setor> onEdit;
  final ValueChanged<Setor> onToggleAtivo;

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
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Sigla', style: style)),
          Expanded(flex: 4, child: Text('Nome', style: style)),
          Expanded(flex: 5, child: Text('Descrição', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          Expanded(flex: 3, child: Text('Ações', style: style)),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.setor,
    required this.canManage,
    required this.onEdit,
    required this.onToggleAtivo,
  });

  final Setor setor;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onToggleAtivo;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            flex: 5,
            child: Text(
              (setor.descricao == null || setor.descricao!.isEmpty)
                  ? '—'
                  : setor.descricao!,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 2, child: SetorStatusChip(ativo: setor.ativo)),
          Expanded(
            flex: 3,
            child: canManage
                ? Row(
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit,
                      ),
                      IconButton(
                        tooltip: setor.ativo ? 'Desativar' : 'Reativar',
                        icon: Icon(
                          setor.ativo
                              ? Icons.block_outlined
                              : Icons.check_circle_outline,
                        ),
                        onPressed: onToggleAtivo,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
