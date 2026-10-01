import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/setor_compact_text.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../application/sei_plano_execucao_builder.dart';
import '../../domain/sei_analise_resultado.dart';
import '../../domain/sei_documento_extraido.dart';
import '../../domain/sei_duplicidade.dart';
import '../../domain/sei_item_execucao_estado.dart';
import '../../domain/sei_validacao_item.dart';
import '../sei_import_controller.dart';
import '../sei_status_visual.dart';
import 'sei_item_detalhe_dialog.dart';

/// Passo de revisão — resumo do documento + contadores por status + tabela
/// de prévia filtrável. Termina no botão "Concluir análise" do diálogo
/// pai; esta tela nunca dispara nenhuma escrita sozinha.
class SeiRevisaoStep extends ConsumerWidget {
  const SeiRevisaoStep({super.key, required this.resultado});

  final SeiAnaliseResultado resultado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seiImportControllerProvider);
    final filtro = state.filtro;
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
        const _AvisoAutorizacao(),
        const SizedBox(height: AppSpacing.md),
        _FiltroChips(filtroAtual: filtro),
        const SizedBox(height: AppSpacing.md),
        if (itensFiltrados.isEmpty)
          const Card(
            child: EmptyState(icon: Icons.filter_alt_off_outlined, message: 'Nenhum item neste filtro.'),
          )
        else
          _TabelaPreview(itens: itensFiltrados, execucao: state.execucao),
        const SizedBox(height: AppSpacing.md),
        _RodapeSelecao(resultado: resultado, execucao: state.execucao, revalidando: state.revalidando),
      ],
    );
  }
}

/// Aviso obrigatório — PRONTO no parser é só validação técnica, nunca
/// autorização administrativa. Uma checkbox explícita registra a
/// confirmação do usuário (`SeiEstagioPreparacao.autorizado`), mas mesmo
/// confirmada NENHUM botão de escrita aparece nesta versão.
class _AvisoAutorizacao extends ConsumerWidget {
  const _AvisoAutorizacao();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seiImportControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Este documento foi analisado com sucesso. Confirme que o procedimento patrimonial foi '
                    'efetivamente autorizado e que as movimentações devem ser registradas no InvTec.',
                    style: AppTypography.body(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            CheckboxListTile(
              value: state.autorizacaoConfirmada,
              onChanged: (v) => ref.read(seiImportControllerProvider.notifier).confirmarAutorizacao(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Confirmo que o procedimento patrimonial foi efetivamente autorizado.'),
            ),
            Text(
              'Esta versão do InvTec não registra nenhuma movimentação a partir desta tela, mesmo com esta '
              'confirmação — a análise é somente leitura.',
              style: AppTypography.auxiliary(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _RodapeSelecao extends StatelessWidget {
  const _RodapeSelecao({required this.resultado, required this.execucao, required this.revalidando});

  final SeiAnaliseResultado resultado;
  final Map<int, SeiItemExecucaoEstado> execucao;
  final bool revalidando;

  @override
  Widget build(BuildContext context) {
    final selecionados = execucao.values.where((e) => e.selecionado).length;
    // "Documento analisado", "documento autorizado" e "itens efetivamente
    // aptos" são três coisas distintas — aptos nunca é resolvido pela
    // autorização geral do documento.
    final aptos = itensElegiveis(resultado: resultado, execucao: execucao).length;
    // `Expanded` (não um `Text` solto no `Row`) — sem largura limitada o
    // texto estourava o diálogo em janelas estreitas/texto maior.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            '$selecionados de ${resultado.totalItens} itens selecionados para um futuro lote · $aptos aptos '
            'tecnicamente (nenhum registrado agora).',
            style: AppTypography.auxiliary(context),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Consumer(
          builder: (context, ref, _) => OutlinedButton.icon(
            onPressed: revalidando ? null : () => ref.read(seiImportControllerProvider.notifier).revalidar(),
            icon: revalidando
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 18),
            label: const Text('Revalidar estado atual'),
          ),
        ),
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
                Expanded(child: Text('Documento SEI analisado', style: AppTypography.pageSubtitle(context))),
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
                Text(
                  '• $aviso',
                  style: AppTypography.auxiliary(context)?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _rotuloTipo(SeiDocumentoExtraido documento) {
    // Só TRANSFERENCIA existe nesta V1 — rótulo fixo para o único caso
    // suportado, sem depender de um mapa genérico ainda inútil.
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
  const _TabelaPreview({required this.itens, required this.execucao});

  final List<SeiValidacaoItem> itens;
  final Map<int, SeiItemExecucaoEstado> execucao;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _HeaderRow(),
          const Divider(height: 1),
          for (var i = 0; i < itens.length; i++) ...[
            _DataRow(item: itens[i], estado: execucao[itens[i].item.linha] ?? const SeiItemExecucaoEstado()),
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
          const SizedBox(width: 40, child: Text('')),
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

class _DataRow extends ConsumerWidget {
  const _DataRow({required this.item, required this.estado});

  final SeiValidacaoItem item;
  final SeiItemExecucaoEstado estado;

  /// Mesmo critério único de elegibilidade do controller/plano
  /// (`itemEstaApto`) — nunca duplicado aqui, para a checkbox e a seleção
  /// real nunca divergirem. Desmarcar é sempre permitido.
  bool get _podeSelecionar => estado.selecionado || itemEstaApto(validacao: item, estado: estado);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, kind, label) = visualDoStatusSei(item.status);

    return InkWell(
      onTap: () => showSeiItemDetalheDialog(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                value: estado.selecionado,
                onChanged: !_podeSelecionar
                    ? null
                    : (_) => ref.read(seiImportControllerProvider.notifier).alternarSelecao(item.item.linha),
              ),
            ),
            SizedBox(
              width: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(label: label, kind: kind, icon: icon),
                  if (estado.duplicidade != null &&
                      estado.duplicidade!.status != SeiDuplicidadeStatus.semCorrespondencia)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(switch (estado.duplicidade!.status) {
                        SeiDuplicidadeStatus.jaRegistrada => 'Já registrada',
                        SeiDuplicidadeStatus.possivelDuplicidade => 'Possível duplicidade',
                        SeiDuplicidadeStatus.exigeRevisao => 'Exige revisão (tipo)',
                        SeiDuplicidadeStatus.semCorrespondencia => '',
                      }, style: AppTypography.auxiliary(context)?.copyWith(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(item.item.numeroPatrimonio ?? '(não identificado)', style: AppTypography.body(context)),
            ),
            Expanded(flex: 3, child: Text(item.item.equipamento ?? '—', style: AppTypography.body(context))),
            Expanded(
              flex: 3,
              // Setor RESOLVIDO no InvTec mostra a sigla (nome completo por
              // tooltip); setor não resolvido continua mostrando o texto
              // original extraído do documento.
              child: item.origem.entidadeEncontrada != null
                  ? SetorCompactText(
                      nome: item.origem.entidadeEncontrada!.nome,
                      sigla: item.origem.entidadeEncontrada!.sigla,
                      style: AppTypography.body(context),
                      maxLines: 2,
                    )
                  : Text(
                      item.item.unidadeOrigemTexto ?? '—',
                      style: AppTypography.body(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            Expanded(
              flex: 3,
              child: item.destino.entidadeEncontrada != null
                  ? SetorCompactText(
                      nome: item.destino.entidadeEncontrada!.nome,
                      sigla: item.destino.entidadeEncontrada!.sigla,
                      style: AppTypography.body(context),
                      maxLines: 2,
                    )
                  : Text(
                      item.item.unidadeDestinoTexto ?? 'Não encontrado',
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
