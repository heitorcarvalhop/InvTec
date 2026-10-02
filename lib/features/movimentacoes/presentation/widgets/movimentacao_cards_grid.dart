import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/setor_compact_text.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/movimentacao.dart';
import '../../domain/movimentacao_listagem_item.dart';
import 'movimentacao_tipo_visual.dart';

/// Grid responsivo de [MovimentacaoCard] para o modo "Cards" da listagem
/// geral de movimentações (alternativa a [MovimentacoesDesktopTable] em
/// telas tablet/desktop — mobile sempre usa `MovimentacoesMobileList`,
/// nunca este grid). Mesmo espírito do grid de stat cards do Dashboard
/// (`_colunasDeStatCards`): faixas discretas de largura em vez de "o quanto
/// couber", para nunca sobrar um card sozinho numa linha.
///
/// Usa EXATAMENTE os itens recebidos (já paginados pelo controller) — nunca
/// busca mais itens para "preencher" a grade; a paginação continua igual
/// nos dois modos de visualização.
class MovimentacaoCardsGrid extends StatelessWidget {
  const MovimentacaoCardsGrid({super.key, required this.itens, required this.onVisualizar});

  final List<MovimentacaoListagemItem> itens;
  final ValueChanged<MovimentacaoListagemItem> onVisualizar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = _colunasDoGrid(constraints.maxWidth);
        final espacamentoTotal = AppSpacing.md * (colunas - 1);
        final largura = (constraints.maxWidth - espacamentoTotal) / colunas;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final item in itens)
              SizedBox(
                width: largura,
                child: MovimentacaoCard(item: item, onVisualizar: () => onVisualizar(item)),
              ),
          ],
        );
      },
    );
  }
}

/// Colunas por faixa de largura disponível — a página limita o conteúdo a
/// `AppSpacing.contentMaxWidth` (1200), então "desktop largo" aqui já é o
/// teto prático dessa largura (4 colunas), "comum"/tablet descem para 3/2, e
/// qualquer coisa mais estreita (inclusive um teste isolado do widget, já
/// que mobile de verdade nunca chega a usar este grid) cai para 1.
int _colunasDoGrid(double larguraDisponivel) {
  if (larguraDisponivel >= 1100) return 4;
  if (larguraDisponivel >= 850) return 3;
  if (larguraDisponivel >= 600) return 2;
  return 1;
}

/// Card de uma movimentação orientado ao EVENTO (o que aconteceu, quando,
/// de onde para onde) — não repete a profundidade do diálogo de detalhe
/// (motivo, observação, documento, chamado, autor continuam só lá).
class MovimentacaoCard extends StatelessWidget {
  const MovimentacaoCard({super.key, required this.item, required this.onVisualizar});

  final MovimentacaoListagemItem item;
  final VoidCallback onVisualizar;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);
    // Mesmo critério de preferência "destino primeiro, cai para origem" de
    // `MovimentacaoListagemItem.responsavelExibido`: a localização de
    // destino é mais relevante (é onde o patrimônio está depois da
    // movimentação) e só cai para a de origem quando não há destino (ex.:
    // BAIXA).
    final localizacao = item.localizacaoDestinoNome ?? item.localizacaoOrigemNome;

    return Card(
      child: InkWell(
        onTap: onVisualizar,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(label: item.tipo.label, kind: kind, icon: icon),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _formatarDataHora(item.dataMovimentacao),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.auxiliary(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Patrimônio ${item.patrimonioNumero ?? '—'}',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.cardTitle(context),
              ),
              if (item.patrimonioTipoNome != null)
                Text(item.patrimonioTipoNome!, overflow: TextOverflow.ellipsis, style: AppTypography.auxiliary(context)),
              const SizedBox(height: AppSpacing.sm),
              _CampoCard(
                label: 'Origem',
                child: SetorCompactText(
                  nome: item.setorOrigemNome,
                  sigla: item.setorOrigemSigla,
                  style: AppTypography.body(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _CampoCard(
                label: 'Destino',
                child: SetorCompactText(
                  nome: item.setorDestinoNome,
                  sigla: item.setorDestinoSigla,
                  style: AppTypography.body(context),
                ),
              ),
              if (localizacao != null) ...[
                const SizedBox(height: AppSpacing.xs),
                _CampoCard(
                  label: 'Localização',
                  child: Text(localizacao, overflow: TextOverflow.ellipsis, style: AppTypography.body(context)),
                ),
              ],
              if (item.responsavelExibido != null) ...[
                const SizedBox(height: AppSpacing.xs),
                _CampoCard(
                  label: 'Responsável',
                  child: Text(
                    item.responsavelExibido!,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(context),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onVisualizar, child: const Text('Visualizar')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Rótulo: valor` compacto, usado pelas linhas de Origem/Destino/
/// Localização/Responsável do card — um único padrão visual para as quatro,
/// em vez de cada uma desenhar seu próprio `Row`.
class _CampoCard extends StatelessWidget {
  const _CampoCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: AppTypography.auxiliary(context)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}
