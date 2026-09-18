import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../domain/sei_analise_resultado.dart';
import '../../domain/sei_documento_extraido.dart';
import '../../domain/sei_validacao_item.dart';
import '../sei_import_controller.dart';
import '../sei_status_visual.dart';
import 'sei_item_detalhe_dialog.dart';

/// Passo de revisão (PROMPT 11.1, seções 22/23) — resumo do documento +
/// contadores por status + tabela de prévia filtrável. Termina no botão
/// "Concluir análise" do diálogo pai; esta tela nunca dispara nenhuma
/// escrita sozinha.
class SeiRevisaoStep extends ConsumerWidget {
  const SeiRevisaoStep({super.key, required this.resultado});

  final SeiAnaliseResultado resultado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(seiImportControllerProvider).filtro;
    final itensFiltrados = switch (filtro) {
      SeiFiltroRevisao.todos => resultado.itens,
      SeiFiltroRevisao.prontos => resultado.itens.where((i) => i.status == SeiStatusLinha.pronto).toList(),
      SeiFiltroRevisao.avisos => resultado.itens.where((i) => i.status == SeiStatusLinha.aviso).toList(),
      SeiFiltroRevisao.bloqueados => resultado.itens.where((i) => i.status == SeiStatusLinha.bloqueado).toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResumoDocumento(documento: resultado.documento, resultado: resultado),
        const SizedBox(height: AppSpacing.md),
        _FiltroChips(filtroAtual: filtro),
        const SizedBox(height: AppSpacing.md),
        if (itensFiltrados.isEmpty)
          const Card(child: EmptyState(icon: Icons.filter_alt_off_outlined, message: 'Nenhum item neste filtro.'))
        else
          _TabelaPreview(itens: itensFiltrados),
      ],
    );
  }
}

class _ResumoDocumento extends StatelessWidget {
  const _ResumoDocumento({required this.documento, required this.resultado});

  final SeiDocumentoExtraido documento;
  final SeiAnaliseResultado resultado;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Documento SEI analisado', style: AppTypography.pageSubtitle(context)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (documento.numeroDocumentoFormatado != null)
              Text('Despacho ${documento.numeroDocumentoFormatado}', style: AppTypography.body(context)),
            if (documento.numeroDocumentoSei != null)
              Text('SEI ${documento.numeroDocumentoSei}', style: AppTypography.auxiliary(context)),
            if (documento.numeroProcesso != null)
              Text('Processo ${documento.numeroProcesso}', style: AppTypography.auxiliary(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              documento.tipoMovimentacaoInferido != null
                  ? 'Tipo detectado: ${_rotuloTipo(documento)}'
                  : 'Tipo de movimentação não identificado nesta versão.',
              style: AppTypography.body(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('${resultado.totalItens} bens encontrados', style: AppTypography.body(context)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                StatusChip(
                  label: '${resultado.totalProntos} prontos',
                  kind: AppStatusKind.success,
                  icon: Icons.check_circle_outline,
                ),
                StatusChip(
                  label: '${resultado.totalAvisos} avisos',
                  kind: AppStatusKind.warning,
                  icon: Icons.warning_amber_outlined,
                ),
                StatusChip(
                  label: '${resultado.totalBloqueados} bloqueados',
                  kind: AppStatusKind.error,
                  icon: Icons.block,
                ),
              ],
            ),
            if (documento.avisos.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final aviso in documento.avisos)
                Text('• $aviso', style: AppTypography.auxiliary(context)?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  String _rotuloTipo(SeiDocumentoExtraido documento) {
    // Só TRANSFERENCIA existe nesta V1 (seção 12) — rótulo fixo para o
    // único caso suportado, sem depender de um mapa genérico ainda inútil.
    return 'Transferência patrimonial';
  }
}

class _FiltroChips extends ConsumerWidget {
  const _FiltroChips({required this.filtroAtual});

  final SeiFiltroRevisao filtroAtual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget chip(String label, SeiFiltroRevisao valor) {
      return ChoiceChip(
        label: Text(label),
        selected: filtroAtual == valor,
        onSelected: (_) => ref.read(seiImportControllerProvider.notifier).filtrar(valor),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        chip('Todos', SeiFiltroRevisao.todos),
        chip('Prontos', SeiFiltroRevisao.prontos),
        chip('Avisos', SeiFiltroRevisao.avisos),
        chip('Bloqueados', SeiFiltroRevisao.bloqueados),
      ],
    );
  }
}

class _TabelaPreview extends StatelessWidget {
  const _TabelaPreview({required this.itens});

  final List<SeiValidacaoItem> itens;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          const Divider(height: 1),
          for (var i = 0; i < itens.length; i++) ...[
            _DataRow(item: itens[i]),
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
          const SizedBox(width: 110, child: Text('Status')),
          Expanded(flex: 2, child: Text('Patrimônio', style: style)),
          Expanded(flex: 3, child: Text('Equipamento', style: style)),
          Expanded(flex: 3, child: Text('Origem (doc./InvTec)', style: style)),
          Expanded(flex: 3, child: Text('Destino', style: style)),
          Expanded(flex: 2, child: Text('Chamado', style: style)),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({required this.item});

  final SeiValidacaoItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind, label) = visualDoStatusSei(item.status);

    return InkWell(
      onTap: () => showSeiItemDetalheDialog(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: StatusChip(label: label, kind: kind, icon: icon)),
            Expanded(
              flex: 2,
              child: Text(item.item.numeroPatrimonio ?? '(não identificado)', style: AppTypography.body(context)),
            ),
            Expanded(flex: 3, child: Text(item.item.equipamento ?? '—', style: AppTypography.body(context))),
            Expanded(
              flex: 3,
              child: Text(
                item.origem.entidadeEncontrada?.nome ?? item.item.unidadeOrigemTexto ?? '—',
                style: AppTypography.body(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                item.destino.entidadeEncontrada?.nome ?? item.item.unidadeDestinoTexto ?? 'Não encontrado',
                style: AppTypography.body(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(flex: 2, child: Text(item.item.numeroChamado ?? '—', style: AppTypography.body(context))),
          ],
        ),
      ),
    );
  }
}
