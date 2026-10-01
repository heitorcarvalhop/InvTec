import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/setor_compact_text.dart';
import '../../domain/patrimonio_detalhe.dart';
import 'patrimonio_status_chip.dart';

/// Altura mínima confortável de uma linha da lista.
const double _alturaMinimaLinha = 56;

/// Lista estruturada (não `DataTable`, para não sofrer overflow horizontal
/// em janelas estreitas — cada célula usa `Expanded` normal).
///
/// LISTAGEM = identificação e consulta rápida; DETALHE =
/// informações completas. Colunas: Patrimônio (em destaque), Equipamento
/// (tipo + marca/modelo), Setor (sigla, nome completo por tooltip), Status,
/// Ações. Série, localização, responsável e a descrição
/// integral continuam disponíveis na ficha (`PatrimonioDetailPage`) — a
/// MESMA que "Ver detalhes" e o clique na linha abrem (`onTap`); `onEdit` é
/// um botão à parte e nunca dispara `onTap` junto.
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
    return Container(
      color: Theme.of(context).surfaceColors.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Patrimônio', style: style)),
          Expanded(flex: 5, child: Text('Equipamento', style: style)),
          Expanded(flex: 2, child: Text('Setor', style: style)),
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
        color: _hovering ? theme.surfaceColors.rowHover : null,
        child: InkWell(
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _alturaMinimaLinha),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      patrimonio.numeroPatrimonio ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(flex: 5, child: _EquipamentoCell(detalhe: detalhe)),
                  Expanded(
                    flex: 2,
                    child: SetorCompactText(
                      nome: detalhe.setorNome,
                      sigla: detalhe.setorSigla,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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
      ),
    );
  }
}

/// Tamanho máximo do trecho da descrição usado como linha secundária
/// quando marca e modelo não existem.
const int _tamanhoTrechoDescricao = 48;

/// O que a célula Equipamento mostra para um patrimônio:
/// [tipo] na primeira linha; [secundaria] na segunda — "marca modelo" quando
/// existirem (sem repetir o tipo), senão um trecho curto da descrição, senão
/// nada (nunca inventa texto); [tooltip] guarda tudo sem reticências,
/// inclusive a descrição integral. Número de série, localização, responsável
/// e observação NÃO entram: têm campo próprio na ficha.
@visibleForTesting
({String tipo, String? secundaria, String tooltip}) resumoEquipamento(PatrimonioDetalhe detalhe) {
  final patrimonio = detalhe.patrimonio;
  final tipo = detalhe.tipoNome;

  String? limpar(String? valor) {
    final texto = valor?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (texto == null || texto.isEmpty) ? null : texto;
  }

  // "Notebook Latitude 5440" com tipo "Notebook" vira "Latitude 5440" — o
  // tipo já está na primeira linha.
  String semTipo(String texto) {
    final tipoMinusculo = tipo.toLowerCase();
    if (texto.toLowerCase() == tipoMinusculo) return '';
    if (texto.toLowerCase().startsWith('$tipoMinusculo ')) {
      return texto.substring(tipo.length + 1).trim();
    }
    return texto;
  }

  final marca = limpar(patrimonio.marca);
  final modelo = limpar(patrimonio.modelo);
  final descricao = limpar(patrimonio.descricao);

  final marcaModelo = semTipo([marca, modelo].whereType<String>().join(' '));

  String? secundaria;
  if (marcaModelo.isNotEmpty) {
    secundaria = marcaModelo;
  } else if (descricao != null) {
    // Trecho literal da descrição — sem reescrever nada do que foi cadastrado.
    secundaria = descricao.length > _tamanhoTrechoDescricao
        ? '${descricao.substring(0, _tamanhoTrechoDescricao).trimRight()}…'
        : descricao;
  }

  final tooltip = [tipo, if (marcaModelo.isNotEmpty) marcaModelo, ?descricao].join('\n');

  return (tipo: tipo, secundaria: secundaria, tooltip: tooltip);
}

/// Tipo em destaque + marca/modelo (ou trecho curto da descrição). O padding
/// à direita separa visualmente a coluna Equipamento da coluna Setor: o texto
/// longo termina com reticências DENTRO desta célula.
class _EquipamentoCell extends StatelessWidget {
  const _EquipamentoCell({required this.detalhe});

  final PatrimonioDetalhe detalhe;

  @override
  Widget build(BuildContext context) {
    final resumo = resumoEquipamento(detalhe);

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Tooltip(
        message: resumo.tooltip,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(resumo.tipo, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body(context)),
            if (resumo.secundaria != null)
              Text(
                resumo.secundaria!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.auxiliary(context),
              ),
          ],
        ),
      ),
    );
  }
}
