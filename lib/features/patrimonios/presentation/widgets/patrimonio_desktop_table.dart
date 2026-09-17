import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/patrimonio.dart';
import '../../domain/patrimonio_detalhe.dart';
import 'patrimonio_status_chip.dart';

/// Lista estruturada (não `DataTable`, para não sofrer overflow horizontal
/// em janelas estreitas — cada célula usa `Expanded` normal). Colunas
/// pensadas para identificação rápida (PROMPT 9.3): Patrimônio em destaque,
/// Equipamento (tipo + descrição/modelo), Identificação (marca + série),
/// Localização (com setor como apoio), Responsável, Status, Ações.
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
    final style = AppTypography.label(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Patrimônio', style: style)),
          Expanded(flex: 3, child: Text('Equipamento', style: style)),
          Expanded(flex: 2, child: Text('Identificação', style: style)),
          Expanded(flex: 2, child: Text('Localização', style: style)),
          Expanded(flex: 2, child: Text('Responsável', style: style)),
          Expanded(flex: 2, child: Text('Status', style: style)),
          SizedBox(width: 88, child: Text('Ações', style: style)),
        ],
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({required this.detalhe, required this.canManage, required this.onTap, required this.onEdit});

  final PatrimonioDetalhe detalhe;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detalhe = widget.detalhe;
    final patrimonio = detalhe.patrimonio;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        color: _hovering ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    patrimonio.numeroPatrimonio ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(flex: 3, child: _EquipamentoCell(detalhe: detalhe)),
                Expanded(flex: 2, child: _IdentificacaoCell(patrimonio: patrimonio)),
                Expanded(flex: 2, child: _LocalizacaoCell(detalhe: detalhe)),
                Expanded(
                  flex: 2,
                  child: Text(
                    patrimonio.responsavelAtual ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PatrimonioStatusChip(status: patrimonio.status),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: 'Ver detalhes',
                        child: IconButton(
                          style: IconButton.styleFrom(
                            minimumSize: const Size(36, 36),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          iconSize: 18,
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: widget.onTap,
                        ),
                      ),
                      if (widget.canManage)
                        Tooltip(
                          message: 'Editar',
                          child: IconButton(
                            style: IconButton.styleFrom(
                              minimumSize: const Size(36, 36),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            iconSize: 18,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: widget.onEdit,
                          ),
                        ),
                    ],
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

/// Tipo em destaque + descrição resumida (ou modelo, se não houver
/// descrição) — nunca inventa texto quando os dois faltam.
class _EquipamentoCell extends StatelessWidget {
  const _EquipamentoCell({required this.detalhe});

  final PatrimonioDetalhe detalhe;

  @override
  Widget build(BuildContext context) {
    final patrimonio = detalhe.patrimonio;
    final linhaSecundaria = (patrimonio.descricao != null && patrimonio.descricao!.isNotEmpty)
        ? patrimonio.descricao!
        : patrimonio.modelo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(detalhe.tipoNome, overflow: TextOverflow.ellipsis, style: AppTypography.body(context)),
        if (linhaSecundaria != null && linhaSecundaria.isNotEmpty)
          Text(linhaSecundaria, overflow: TextOverflow.ellipsis, style: AppTypography.auxiliary(context)),
      ],
    );
  }
}

/// Marca em destaque + número de série — oculta a linha inteira quando o
/// dado não existe, nunca mostra "null".
class _IdentificacaoCell extends StatelessWidget {
  const _IdentificacaoCell({required this.patrimonio});

  final Patrimonio patrimonio;

  @override
  Widget build(BuildContext context) {
    final marca = patrimonio.marca;
    final serie = patrimonio.numeroSerie;

    if ((marca == null || marca.isEmpty) && (serie == null || serie.isEmpty)) {
      return Text('—', style: AppTypography.body(context));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (marca != null && marca.isNotEmpty)
          Text(marca.toUpperCase(), overflow: TextOverflow.ellipsis, style: AppTypography.body(context)),
        if (serie != null && serie.isNotEmpty)
          Text('Série: $serie', overflow: TextOverflow.ellipsis, style: AppTypography.auxiliary(context)),
      ],
    );
  }
}

/// Localização atual em destaque (nunca só "Gerência de Tecnologia" — quase
/// todos os patrimônios estão na mesma gerência, então o setor vira só
/// apoio) — "Sem localização" quando não há uma definida.
class _LocalizacaoCell extends StatelessWidget {
  const _LocalizacaoCell({required this.detalhe});

  final PatrimonioDetalhe detalhe;

  @override
  Widget build(BuildContext context) {
    final localizacao = detalhe.localizacaoNome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          localizacao ?? 'Sem localização',
          overflow: TextOverflow.ellipsis,
          style: localizacao == null
              ? AppTypography.auxiliary(context)?.copyWith(fontStyle: FontStyle.italic)
              : AppTypography.body(context),
        ),
        Text(detalhe.setorNome, overflow: TextOverflow.ellipsis, style: AppTypography.auxiliary(context)),
      ],
    );
  }
}
