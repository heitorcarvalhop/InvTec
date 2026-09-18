import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/movimentacao.dart';
import '../../domain/movimentacao_listagem_item.dart';
import 'movimentacao_tipo_visual.dart';

/// Lista estruturada (não `DataTable`, mesmo padrão de
/// `PatrimonioDesktopTable`) — colunas: Data, Patrimônio, Tipo, Origem,
/// Destino, Responsável, Autor, Ações (PROMPT 10.1).
class MovimentacoesDesktopTable extends StatelessWidget {
  const MovimentacoesDesktopTable({super.key, required this.itens, required this.onVisualizar});

  final List<MovimentacaoListagemItem> itens;
  final ValueChanged<MovimentacaoListagemItem> onVisualizar;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          const Divider(height: 1),
          for (var i = 0; i < itens.length; i++) ...[
            _DataRow(item: itens[i], onVisualizar: () => onVisualizar(itens[i])),
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
    final style = AppTypography.label(context);
    return Container(
      color: Theme.of(context).surfaceColors.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Data', style: style)),
          Expanded(flex: 2, child: Text('Patrimônio', style: style)),
          Expanded(flex: 2, child: Text('Tipo', style: style)),
          Expanded(flex: 2, child: Text('Origem', style: style)),
          Expanded(flex: 2, child: Text('Destino', style: style)),
          Expanded(flex: 2, child: Text('Responsável', style: style)),
          Expanded(flex: 2, child: Text('Autor', style: style)),
          const SizedBox(width: 56, child: Text('')),
        ],
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({required this.item, required this.onVisualizar});

  final MovimentacaoListagemItem item;
  final VoidCallback onVisualizar;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        color: _hovering ? theme.surfaceColors.rowHover : null,
        child: InkWell(
          onTap: widget.onVisualizar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatarDataHora(item.dataMovimentacao),
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
                Expanded(flex: 2, child: _PatrimonioCell(item: item)),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(label: item.tipo.label, kind: kind, icon: icon),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.setorOrigemNome ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.setorDestinoNome ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.responsavelExibido ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    item.autorExibido,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Tooltip(
                    message: 'Visualizar',
                    child: IconButton(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(36, 36),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      iconSize: 18,
                      icon: const Icon(Icons.visibility_outlined),
                      onPressed: widget.onVisualizar,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Número do patrimônio em destaque + tipo/equipamento como apoio, quando
/// disponível (PROMPT 10.1) — nunca mostra "null".
class _PatrimonioCell extends StatelessWidget {
  const _PatrimonioCell({required this.item});

  final MovimentacaoListagemItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.patrimonioNumero ?? '—',
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (item.patrimonioTipoNome != null)
          Text(item.patrimonioTipoNome!, overflow: TextOverflow.ellipsis, style: AppTypography.auxiliary(context)),
      ],
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}
