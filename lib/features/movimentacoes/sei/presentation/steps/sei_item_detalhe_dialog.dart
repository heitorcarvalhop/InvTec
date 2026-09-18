import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../../../patrimonios/domain/patrimonio.dart';
import '../../domain/sei_validacao_item.dart';
import '../sei_status_visual.dart';

/// Detalhe de uma linha da revisão (PROMPT 11.1, seção 24) — três blocos:
/// dados do documento, estado atual no InvTec, validação (checks/avisos/
/// bloqueios). Somente leitura: nenhuma ação de escrita aqui.
Future<void> showSeiItemDetalheDialog(BuildContext context, SeiValidacaoItem item) {
  return showDialog<void>(context: context, builder: (context) => _SeiItemDetalheDialog(item: item));
}

class _SeiItemDetalheDialog extends StatelessWidget {
  const _SeiItemDetalheDialog({required this.item});

  final SeiValidacaoItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind, label) = visualDoStatusSei(item.status);
    final patrimonio = item.patrimonioEncontrado?.patrimonio;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.item.numeroPatrimonio ?? 'Patrimônio não identificado',
                        style: AppTypography.pageSubtitle(context),
                      ),
                    ),
                    StatusChip(label: label, kind: kind, icon: icon),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Secao(
                  titulo: 'DADOS DO DOCUMENTO',
                  children: [
                    _Campo('Patrimônio', item.item.numeroPatrimonio),
                    _Campo('Equipamento', item.item.equipamento),
                    _Campo('Origem', item.item.unidadeOrigemTexto),
                    _Campo('Destino', item.item.unidadeDestinoTexto),
                    _Campo('Chamado', item.item.numeroChamado),
                    _Campo('Página', 'pg. ${item.item.paginaOrigem}'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Secao(
                  titulo: 'ESTADO ATUAL NO INVTEC',
                  children: patrimonio == null
                      ? [const _Campo('Patrimônio', 'Não encontrado no InvTec')]
                      : [
                          _Campo('Status', patrimonio.status.label),
                          _Campo('Setor', item.patrimonioEncontrado!.setorNome),
                          _Campo('Localização', item.patrimonioEncontrado!.localizacaoNome ?? 'Não informada'),
                          _Campo('Responsável', patrimonio.responsavelAtual ?? 'Nenhum'),
                        ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Secao(
                  titulo: 'VALIDAÇÃO',
                  children: [
                    for (final check in item.checks) _ItemLista(icon: Icons.check, texto: check, cor: Colors.green),
                    for (final aviso in item.avisos)
                      _ItemLista(
                        icon: Icons.warning_amber_outlined,
                        texto: aviso,
                        cor: Theme.of(context).statusColors.warningForeground,
                      ),
                    for (final bloqueio in item.bloqueios)
                      _ItemLista(icon: Icons.block, texto: bloqueio, cor: Theme.of(context).colorScheme.error),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: AppTypography.label(context)?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: AppSpacing.xs),
        ...children,
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo(this.rotulo, this.valor);

  final String rotulo;
  final String? valor;

  @override
  Widget build(BuildContext context) {
    if (valor == null || valor!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(rotulo, style: AppTypography.auxiliary(context))),
          Expanded(child: Text(valor!, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}

class _ItemLista extends StatelessWidget {
  const _ItemLista({required this.icon, required this.texto, required this.cor});

  final IconData icon;
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(texto, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}
