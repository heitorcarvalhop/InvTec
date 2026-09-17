import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// "Mostrando 1–25 de 1.744 registros / ‹ 1 2 3 4 … 70 › / Itens por
/// página: [25 ▼]" — genérico o bastante para qualquer listagem paginada
/// server-side do InvTec (PROMPT 9.2, seção 9; visual ajustado no PROMPT
/// 9.3.2, seção 9, ao conceito aprovado no Figma).
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.paginaAtual,
    required this.totalPaginas,
    required this.onChanged,
    this.totalItens,
    this.tamanhoPagina,
    this.tamanhosPaginaPermitidos,
    this.onTamanhoPaginaChanged,
  });

  /// 0-based.
  final int paginaAtual;
  final int totalPaginas;
  final ValueChanged<int> onChanged;

  /// Total de itens depois de todos os filtros (não só o tamanho da
  /// página atual) — usado para montar o resumo "1–25 de N". Quando
  /// omitido, o resumo não é exibido (uso genérico sem esse dado).
  final int? totalItens;
  final int? tamanhoPagina;

  /// Quando informado junto com [onTamanhoPaginaChanged], mostra o
  /// seletor "Itens por página".
  final List<int>? tamanhosPaginaPermitidos;
  final ValueChanged<int>? onTamanhoPaginaChanged;

  @override
  Widget build(BuildContext context) {
    final podeVoltar = paginaAtual > 0;
    final podeAvancar = paginaAtual < totalPaginas - 1;

    final resumo = totalItens != null && tamanhoPagina != null
        ? _resumoIntervalo(
            paginaAtual: paginaAtual,
            tamanhoPagina: tamanhoPagina!,
            totalItens: totalItens!,
          )
        : null;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        if (resumo != null) Text(resumo, style: AppTypography.auxiliary(context)),
        Semantics(
          label: 'Página ${paginaAtual + 1} de $totalPaginas',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Página anterior',
                child: IconButton(
                  key: const ValueKey('pagination-prev'),
                  visualDensity: VisualDensity.compact,
                  onPressed: podeVoltar ? () => onChanged(paginaAtual - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
              for (final pagina in _paginasVisiveis(paginaAtual, totalPaginas))
                pagina == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: Text('…'),
                      )
                    : _PageNumberButton(
                        numero: pagina,
                        selecionada: pagina == paginaAtual + 1,
                        onPressed: () => onChanged(pagina - 1),
                      ),
              Tooltip(
                message: 'Próxima página',
                child: IconButton(
                  key: const ValueKey('pagination-next'),
                  visualDensity: VisualDensity.compact,
                  onPressed: podeAvancar ? () => onChanged(paginaAtual + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ],
          ),
        ),
        if (tamanhosPaginaPermitidos != null &&
            onTamanhoPaginaChanged != null &&
            tamanhoPagina != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Itens por página: ', style: AppTypography.auxiliary(context)),
              DropdownButton<int>(
                value: tamanhoPagina,
                items: [
                  for (final tamanho in tamanhosPaginaPermitidos!)
                    DropdownMenuItem(value: tamanho, child: Text('$tamanho')),
                ],
                onChanged: (valor) {
                  if (valor != null) onTamanhoPaginaChanged!(valor);
                },
              ),
            ],
          ),
      ],
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({required this.numero, required this.selecionada, required this.onPressed});

  final int numero;
  final bool selecionada;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        key: ValueKey('pagination-page-$numero'),
        color: selecionada ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: selecionada ? null : onPressed,
          child: Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              '$numero',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selecionada ? colorScheme.onPrimaryContainer : null,
                fontWeight: selecionada ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Páginas (1-based) a exibir como botões, com `null` marcando uma reticência
/// ("…") — sempre mostra a primeira, a última, a atual e as vizinhas
/// imediatas; condensa o restante para não estourar a largura em listas com
/// muitas páginas (ex.: 70 páginas -> "1 2 3 4 … 70").
List<int?> _paginasVisiveis(int paginaAtualZeroBased, int totalPaginas) {
  final atual = paginaAtualZeroBased + 1;
  if (totalPaginas <= 7) {
    return [for (var p = 1; p <= totalPaginas; p++) p];
  }

  final paginas = <int>{1, totalPaginas, atual};
  if (atual - 1 >= 1) paginas.add(atual - 1);
  if (atual + 1 <= totalPaginas) paginas.add(atual + 1);
  final ordenadas = paginas.toList()..sort();

  final resultado = <int?>[];
  for (var i = 0; i < ordenadas.length; i++) {
    if (i > 0 && ordenadas[i] - ordenadas[i - 1] > 1) {
      resultado.add(null);
    }
    resultado.add(ordenadas[i]);
  }
  return resultado;
}

String _resumoIntervalo({
  required int paginaAtual,
  required int tamanhoPagina,
  required int totalItens,
}) {
  if (totalItens == 0) return 'Nenhum registro';
  final inicio = paginaAtual * tamanhoPagina + 1;
  final fim = ((paginaAtual + 1) * tamanhoPagina).clamp(0, totalItens);
  return 'Mostrando ${_formatarMilhar(inicio)}–${_formatarMilhar(fim)} de ${_formatarMilhar(totalItens)} '
      '${totalItens == 1 ? 'registro' : 'registros'}';
}

/// Separador de milhar manual (ex.: 1744 -> "1.744") — evita adicionar a
/// dependência `intl` só para esta formatação pontual.
String _formatarMilhar(int valor) {
  final digitos = valor.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    final posicaoDaDireita = digitos.length - i;
    if (i > 0 && posicaoDaDireita % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return buffer.toString();
}
