import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/setor_display.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/movimentacao.dart';
import '../../domain/movimentacao_listagem_item.dart';
import 'movimentacao_tipo_visual.dart';

/// Detalhe somente leitura de uma movimentação — nenhum campo é editável
/// aqui; histórico é imutável (ver docs/database.md).
Future<void> showMovimentacaoDetailDialog(BuildContext context, MovimentacaoListagemItem item) {
  return showDialog<void>(
    context: context,
    builder: (context) => MovimentacaoDetailDialog(item: item),
  );
}

/// Abaixo desta largura de conteúdo (já descontado o padding do diálogo) os
/// pares de campo voltam a empilhar em coluna única — não há espaço
/// confortável para duas colunas.
const _larguraMinimaParaGrade = 440.0;

class MovimentacaoDetailDialog extends StatelessWidget {
  const MovimentacaoDetailDialog({super.key, required this.item});

  final MovimentacaoListagemItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);
    final localizacao = _resumoLocalizacao(item);

    // Agrupados em pares que fazem sentido lado a lado quando há espaço;
    // cada grupo com 1 ou 2 campos (os opcionais entram como `null` quando
    // ausentes — nunca dados inventados, só o arranjo muda). Motivo e
    // Observação ficam de fora: são texto livre, potencialmente longo, e
    // sempre ocupam a linha inteira.
    final grupos = <List<Widget?>>[
      [
        _Field(label: 'Patrimônio', value: item.patrimonioNumero),
        if (item.patrimonioTipoNome != null) _Field(label: 'Equipamento', value: item.patrimonioTipoNome),
      ],
      [
        // Sigla cadastrada, nome completo por tooltip.
        _Field(
          label: 'Origem',
          value: siglaOuNomeSetor(sigla: item.setorOrigemSigla, nome: item.setorOrigemNome),
          valueTooltip:
              siglaOuNomeSetor(sigla: item.setorOrigemSigla, nome: item.setorOrigemNome) == item.setorOrigemNome
              ? null
              : item.setorOrigemNome,
        ),
        _Field(
          label: 'Destino',
          value: siglaOuNomeSetor(sigla: item.setorDestinoSigla, nome: item.setorDestinoNome),
          valueTooltip:
              siglaOuNomeSetor(sigla: item.setorDestinoSigla, nome: item.setorDestinoNome) == item.setorDestinoNome
              ? null
              : item.setorDestinoNome,
        ),
      ],
      [
        if (localizacao != null) _Field(label: 'Localização', value: localizacao),
        _Field(label: 'Responsável', value: item.responsavelExibido),
      ],
      [
        _Field(label: 'Autor', value: item.autorExibido),
        _Field(label: 'Data/hora', value: _formatarDataHora(item.dataMovimentacao)),
      ],
      [if (item.motivo != null && item.motivo!.isNotEmpty) _Field(label: 'Motivo', value: item.motivo)],
      [if (item.observacao != null && item.observacao!.isNotEmpty) _Field(label: 'Observação', value: item.observacao)],
      [
        if (item.numeroDocumento != null && item.numeroDocumento!.isNotEmpty)
          _Field(label: 'Documento', value: item.numeroDocumento),
        if (item.numeroChamado != null && item.numeroChamado!.isNotEmpty)
          _Field(label: 'Chamado', value: item.numeroChamado),
      ],
    ];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Movimentação', style: AppTypography.pageSubtitle(context))),
                  StatusChip(label: item.tipo.label, kind: kind, icon: icon),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final emGrade = constraints.maxWidth >= _larguraMinimaParaGrade;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final grupo in grupos) _linhaDoGrupo(grupo, emGrade: emGrade)],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Em grade: um grupo com dois campos vira uma `Row` lado a lado; com um só,
/// ocupa a linha inteira. Em coluna (estreito ou grupo sem campos visíveis),
/// cada campo do grupo empilha normalmente, na mesma ordem de sempre.
Widget _linhaDoGrupo(List<Widget?> grupo, {required bool emGrade}) {
  final campos = grupo.whereType<Widget>().toList();
  if (campos.isEmpty) return const SizedBox.shrink();
  if (!emGrade || campos.length == 1) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: campos);
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: campos[0]),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: campos[1]),
    ],
  );
}

/// "origem → destino" quando os dois lados existem; só um dos nomes quando
/// só um existe; `null` (linha ocultada) quando nenhum dos dois existe.
String? _resumoLocalizacao(MovimentacaoListagemItem item) {
  final origem = item.localizacaoOrigemNome;
  final destino = item.localizacaoDestinoNome;
  if (origem != null && destino != null && origem != destino) return '$origem → $destino';
  return destino ?? origem;
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.valueTooltip});

  final String label;
  final String? value;

  /// nome completo de um setor exibido pela sigla.
  final String? valueTooltip;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(value ?? '—', style: AppTypography.body(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.auxiliary(context)),
          const SizedBox(height: 2),
          valueTooltip == null ? valueText : Tooltip(message: valueTooltip, child: valueText),
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
