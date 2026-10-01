import 'package:flutter/material.dart';

import '../../../../../core/responsive/breakpoints.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_documento_situacao.dart';
import '../sei_situacao_visual.dart';

/// Largura mínima em que as 5 colunas cabem sem apertar o chip de situação.
/// Abaixo dela (janela fora do mínimo do Windows / tablet estreito) a lista
/// ganha rolagem horizontal com barra visível — mas na janela do Windows
/// (mínimo 1280) e maximizada ela cabe inteira, sem rolagem.
const double _larguraMinimaTabela = 900;

/// Larguras FIXAS das colunas cujo texto nunca pode ser espremido (só o
/// Assunto cede espaço, com reticências e tooltip).
/// Medido com Segoe UI (Windows): "999999/2026/TESTE-PROMPT1137" ≈ 213–228px
/// em negrito 14px; mais os 16px de folga.
const double _larguraColunaDocumento = 268;

/// "20 pendentes · 10 concluídos · 3 cancelados" ≈ 270px: cabe em 2 linhas.
const double _larguraColunaProgresso = 210;

/// Folga entre uma célula e a seguinte (padding à direita de cada célula de
/// texto, no cabeçalho e nas linhas — as colunas continuam alinhadas).
const double _folgaEntreColunas = AppSpacing.md;

/// Largura fixa da coluna Situação — comporta "Parcialmente concluído".
/// "Parcialmente concluído" (chip completo) ≈ 165px.
const double _larguraColunaSituacao = 176;

/// Largura da coluna do botão de abrir.
const double _larguraColunaAcao = 56;

/// Altura mínima confortável de uma linha da lista.
const double _alturaMinimaLinha = 56;

/// Lista de Documentos SEI pendentes.
///
/// LISTAGEM = identificação e consulta rápida; DETALHE
/// (`showSeiPendenciaDetalheDialog`, aberto por `onAbrir`) tem as
/// informações completas e é a única tela com ações de escrita.
///
/// Os contadores vêm SEMPRE dos totais do próprio [SeiDocumentoPendente]
/// (view `documentos_sei_com_situacao`), nunca de `itens` — numa linha de
/// listagem `itens` é `[]`.
///
/// Quando a largura não comporta as colunas, a lista ganha rolagem
/// horizontal com `Scrollbar` sempre visível.
class SeiPendenciasList extends StatefulWidget {
  const SeiPendenciasList({super.key, required this.itens, required this.onAbrir});

  final List<SeiDocumentoPendente> itens;
  final ValueChanged<SeiDocumentoPendente> onAbrir;

  @override
  State<SeiPendenciasList> createState() => _SeiPendenciasListState();
}

class _SeiPendenciasListState extends State<SeiPendenciasList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.screenSize == ScreenSize.mobile) {
      return Column(
        children: [
          for (final documento in widget.itens)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _PendenciaCard(documento: documento, onAbrir: () => widget.onAbrir(documento)),
            ),
        ],
      );
    }

    final tabela = Column(
      children: [
        const _HeaderRow(),
        const Divider(height: 1),
        for (var i = 0; i < widget.itens.length; i++) ...[
          _DataRow(documento: widget.itens[i], onAbrir: () => widget.onAbrir(widget.itens[i])),
          if (i < widget.itens.length - 1) const Divider(height: 1),
        ],
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= _larguraMinimaTabela) return tabela;
          return Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SizedBox(width: _larguraMinimaTabela, child: tabela),
            ),
          );
        },
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
          SizedBox(
            width: _larguraColunaDocumento,
            child: _Celula(child: Text('Documento SEI', style: style)),
          ),
          Expanded(
            child: _Celula(child: Text('Assunto', style: style)),
          ),
          SizedBox(
            width: _larguraColunaProgresso,
            child: _Celula(child: Text('Progresso', style: style)),
          ),
          SizedBox(
            width: _larguraColunaSituacao,
            child: Text('Situação', style: style),
          ),
          const SizedBox(width: _larguraColunaAcao),
        ],
      ),
    );
  }
}

class _DataRow extends StatefulWidget {
  const _DataRow({required this.documento, required this.onAbrir});

  final SeiDocumentoPendente documento;
  final VoidCallback onAbrir;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documento = widget.documento;
    final assunto = documento.assunto;
    final temAssunto = assunto != null && assunto.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        color: _hovering ? theme.surfaceColors.rowHover : null,
        child: InkWell(
          onTap: widget.onAbrir,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _alturaMinimaLinha),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _larguraColunaDocumento,
                    child: _Celula(
                      child: _TextoComTooltip(
                        texto: _numeroDoDocumento(documento),
                        tooltip: _numeroDoDocumento(documento),
                        style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _Celula(
                      child: _TextoComTooltip(
                        texto: temAssunto ? assunto : '—',
                        tooltip: temAssunto ? assunto : null,
                        style: AppTypography.body(context),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _larguraColunaProgresso,
                    child: _Celula(
                      child: _TextoComTooltip(
                        texto: progressoDoDocumento(documento),
                        tooltip: _totalDeItens(documento),
                        style: AppTypography.body(context),
                        maxLines: 2,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _larguraColunaSituacao,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SituacaoChip(situacao: documento.situacao),
                    ),
                  ),
                  SizedBox(
                    width: _larguraColunaAcao,
                    child: Tooltip(
                      message: 'Abrir documento',
                      child: IconButton(
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        iconSize: 18,
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: widget.onAbrir,
                      ),
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

/// Apresentação compacta (Android / janela estreita): número + situação no
/// topo, assunto e progresso embaixo — sem tentar reproduzir a tabela.
class _PendenciaCard extends StatelessWidget {
  const _PendenciaCard({required this.documento, required this.onAbrir});

  final SeiDocumentoPendente documento;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final assunto = documento.assunto;
    return Card(
      child: InkWell(
        onTap: onAbrir,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_numeroDoDocumento(documento), style: AppTypography.cardTitle(context)),
              if (assunto != null && assunto.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(assunto, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.body(context)),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SituacaoChip(situacao: documento.situacao),
                  Text(progressoDoDocumento(documento), style: AppTypography.auxiliary(context)),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onAbrir, child: const Text('Abrir documento')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Envolve o conteúdo de uma célula de texto com a folga à direita que
/// separa visualmente esta coluna da próxima.
class _Celula extends StatelessWidget {
  const _Celula({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: _folgaEntreColunas),
      child: child,
    );
  }
}

/// Texto com reticências; o texto completo (ou uma explicação) aparece
/// por tooltip quando houver.
class _TextoComTooltip extends StatelessWidget {
  const _TextoComTooltip({required this.texto, required this.tooltip, required this.style, this.maxLines = 1});

  final String texto;
  final String? tooltip;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final text = Text(texto, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    final mensagem = tooltip;
    if (mensagem == null || mensagem.isEmpty) return text;
    return Tooltip(message: mensagem, child: text);
  }
}

class _SituacaoChip extends StatelessWidget {
  const _SituacaoChip({required this.situacao});

  final SeiDocumentoSituacao situacao;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDaSituacaoDocumentoSei(situacao);
    return StatusChip(label: situacao.label, kind: kind, icon: icon);
  }
}

String _numeroDoDocumento(SeiDocumentoPendente documento) =>
    documento.numeroDocumentoFormatado ?? documento.numeroDocumentoSei ?? '—';

String _totalDeItens(SeiDocumentoPendente documento) {
  final total = documento.totalItens;
  return '$total ${total == 1 ? 'item' : 'itens'} no documento';
}

/// "2 pendentes · 0 concluídos" — cancelados só entram quando existem, para
/// não poluir a maioria dos documentos (que nunca teve cancelamento). Sempre
/// calculado dos totais do documento, nunca de `documento.itens`.
String progressoDoDocumento(SeiDocumentoPendente documento) {
  String parte(int n, String singular, String plural) => '$n ${n == 1 ? singular : plural}';

  final partes = [
    parte(documento.totalPendentes, 'pendente', 'pendentes'),
    parte(documento.totalConcluidos, 'concluído', 'concluídos'),
    if (documento.totalCancelados > 0) parte(documento.totalCancelados, 'cancelado', 'cancelados'),
  ];
  return partes.join(' · ');
}
