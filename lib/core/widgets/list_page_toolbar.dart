import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'list_view_mode.dart';

/// Acima desta largura, busca e os controles de ação (Filtros, Lista/Cards,
/// ação secundária, ação principal) dividem uma única linha: a busca cresce
/// (`Expanded`) e os controles ficam com sua largura natural. Calibrada pelo
/// PIOR CASO real do app — Movimentações, com "Filtros" + Lista/Cards +
/// "Importar documento SEI" + "Nova movimentação" (os rótulos mais longos) —
/// mais folga para a busca nunca ficar espremida mesmo nesse caso.
const _larguraUmaLinha = 1040.0;

/// Barra de ações compartilhada por listagens paginadas do InvTec: busca +
/// filtros + alternância Lista/Cards + ação principal (+ ações secundárias
/// opcionais) — `[ Busca.......... ] [ Filtros ] [ Lista | Cards ] [ + Ação ]`.
/// Mesmo padrão em Patrimônios e Movimentações, para as duas telas nunca
/// divergirem visualmente.
///
/// Estratégia de layout — duas composições DELIBERADAS, nunca uma
/// consequência acidental de `Wrap`:
/// - **Largura >= [_larguraUmaLinha]**: tudo numa linha só (busca cresce,
///   controles com largura natural).
/// - **Abaixo disso**: duas linhas — busca ocupando a linha toda, controles
///   em uma segunda linha própria, também com a largura TODA do toolbar à
///   disposição (nunca espremidos ao lado da busca). Só quebram em MAIS de
///   uma sublinha em larguras muito estreitas (celular) — nunca um botão
///   sozinho e aparentemente órfão: a própria ordem dos controles
///   (Filtros, Lista/Cards, ações secundárias, ação principal) é preservada
///   em qualquer quebra.
///
/// Não é dona do PAINEL de filtros em si (cada tela continua com seus
/// próprios filtros/dropdowns) — só do botão que abre/fecha esse painel e do
/// contador de filtros ativos.
class ListPageToolbar extends StatelessWidget {
  const ListPageToolbar({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    this.searchLeading,
    required this.filterCount,
    required this.onFiltersPressed,
    required this.viewMode,
    required this.onViewModeChanged,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.secondaryActions = const [],
  });

  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;

  /// Controle compacto, SEM borda/decoração própria (ex.: o seletor "Buscar
  /// em" de Patrimônios) — desenhado DENTRO do mesmo campo de busca, à
  /// esquerda do ícone de lupa, para parecer um único controle integrado em
  /// vez de dois campos lado a lado disputando espaço. `null` quando a tela
  /// não tem esse refinamento (ex.: Movimentações).
  final Widget? searchLeading;

  final int filterCount;
  final VoidCallback onFiltersPressed;

  final ListViewMode viewMode;
  final ValueChanged<ListViewMode> onViewModeChanged;

  /// Ação principal (ex.: "+ Novo patrimônio") — omitida quando
  /// [onPrimaryAction] é `null` (ex.: perfil sem permissão de escrita),
  /// nunca desenhada desabilitada.
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;

  /// Ações secundárias (ex.: "Importar planilha") — ficam entre a
  /// alternância Lista/Cards e a ação principal (ver ordem conceitual fixa
  /// na documentação da classe).
  final List<Widget> secondaryActions;

  @override
  Widget build(BuildContext context) {
    final busca = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: searchHint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (searchLeading != null) ...[
                searchLeading!,
                const SizedBox(
                  height: 20,
                  child: VerticalDivider(width: AppSpacing.sm, thickness: 1),
                ),
              ],
              const Icon(Icons.search),
            ],
          ),
        ),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
              ),
      ),
    );

    // Ordem conceitual fixa — Busca | Filtros | Lista/Cards | ação(ões)
    // secundária(s) | ação principal — preservada em qualquer composição
    // (linha única, duas linhas ou quebra adicional em mobile).
    final controles = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onFiltersPressed,
          icon: const Icon(Icons.filter_list),
          label: Text(filterCount > 0 ? 'Filtros ($filterCount)' : 'Filtros'),
        ),
        _ViewModeToggle(viewMode: viewMode, onChanged: onViewModeChanged),
        ...secondaryActions,
        if (onPrimaryAction != null && primaryActionLabel != null && primaryActionIcon != null)
          FilledButton.icon(
            onPressed: onPrimaryAction,
            icon: Icon(primaryActionIcon),
            label: Text(primaryActionLabel!),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _larguraUmaLinha) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: busca),
              const SizedBox(width: AppSpacing.md),
              // `Flexible` como rede de segurança: numa linha única, os
              // controles já têm espaço de sobra pelo cálculo de
              // `_larguraUmaLinha` — isto só evita overflow num caso
              // extremo (ex.: fonte do sistema aumentada), nunca é o
              // mecanismo normal de quebra.
              Flexible(child: controles),
            ],
          );
        }

        // Duas linhas DELIBERADAS: a busca ocupa a linha toda; os
        // controles recebem a largura TODA do toolbar na linha de baixo
        // (nunca ficam espremidos ao lado da busca) — é só aqui, em
        // larguras realmente estreitas, que o próprio `Wrap` de controles
        // pode precisar de mais de uma sublinha.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [busca, const SizedBox(height: AppSpacing.sm), controles],
        );
      },
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.viewMode, required this.onChanged});

  final ListViewMode viewMode;
  final ValueChanged<ListViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ListViewMode>(
      segments: const [
        ButtonSegment(value: ListViewMode.list, icon: Icon(Icons.view_list_outlined), tooltip: 'Lista'),
        ButtonSegment(value: ListViewMode.cards, icon: Icon(Icons.grid_view_outlined), tooltip: 'Cards'),
      ],
      selected: {viewMode},
      showSelectedIcon: false,
      onSelectionChanged: (selecionados) => onChanged(selecionados.first),
    );
  }
}
