import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/compact_icon_button.dart';
import '../navigation_items.dart';
import 'nav_tile.dart';

void _semAcaoDeRecolher() {}

/// Sidebar fixa usada em tablet/desktop (largura de janela >= 600) — fundo
/// azul-marinho fixo (mesma identidade nos dois temas, ver
/// [AppColors.sidebarBackground]), independente do restante da tela estar
/// clara ou escura.
///
/// Tem dois estados: expandida (largura [AppSpacing.sidebarWidth], ícone +
/// texto) e recolhida (largura [AppSpacing.sidebarWidthCollapsed], só
/// ícones com tooltip) — ver [collapsed]. Quem decide o estado efetivo e
/// persiste a escolha é o chamador (`AppShell`), não este widget.
class NavigationSidebar extends StatefulWidget {
  const NavigationSidebar({
    super.key,
    required this.currentRoute,
    required this.items,
    required this.onNavigate,
    required this.onLogout,
    this.collapsed = false,
    this.onToggleCollapse = _semAcaoDeRecolher,
  });

  final String currentRoute;
  final List<NavigationItem> items;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  static const _duracaoAnimacao = Duration(milliseconds: 200);

  @override
  State<NavigationSidebar> createState() => _NavigationSidebarState();
}

/// Rótulos (texto dos itens, "InvTec" por extenso) só aparecem depois que a
/// largura termina de animar — nunca junto com ela. Ao RECOLHER, esconder o
/// rótulo de imediato é sempre seguro (um conteúdo estreito nunca estoura um
/// container ainda largo, encolhendo). Ao EXPANDIR, o inverso não é seguro:
/// se o rótulo aparecesse de imediato, o `Row` com ícone+texto seria
/// forçado a caber numa largura ainda próxima da recolhida, estourando
/// (`RenderFlex overflowed`) nos primeiros frames da animação — por isso o
/// rótulo só reaparece quando a largura já terminou de crescer.
class _NavigationSidebarState extends State<NavigationSidebar> {
  late bool _mostrarRotulos = !widget.collapsed;

  @override
  void didUpdateWidget(NavigationSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed == oldWidget.collapsed) return;
    if (widget.collapsed) {
      setState(() => _mostrarRotulos = false);
    } else {
      Future.delayed(NavigationSidebar._duracaoAnimacao, () {
        if (mounted && !widget.collapsed) setState(() => _mostrarRotulos = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final mostrarConteudoRecolhido = !_mostrarRotulos;

    return AnimatedContainer(
      duration: NavigationSidebar._duracaoAnimacao,
      curve: Curves.easeInOut,
      width: collapsed ? AppSpacing.sidebarWidthCollapsed : AppSpacing.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(right: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BrandHeader(
              collapsed: mostrarConteudoRecolhido,
              sidebarRecolhida: collapsed,
              onToggleCollapse: widget.onToggleCollapse,
            ),
            Divider(height: 1, color: AppColors.sidebarBorder),
            const SizedBox(height: AppSpacing.sm),
            // A lista de navegação e o bloco fixo de "Configurações"/"Sair"
            // dividem o mesmo `SingleChildScrollView`: quando cabe tudo,
            // nada rola; numa janela baixa, a área inteira passa a rolar em
            // vez de cortar essas ações.
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: mostrarConteudoRecolhido ? AppSpacing.xs : AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in widget.items)
                        NavTile(
                          item: item,
                          selected: item.ativoPara(widget.currentRoute),
                          onTap: () => widget.onNavigate(item.route),
                          collapsed: mostrarConteudoRecolhido,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Divider(height: 1, color: AppColors.sidebarBorder),
                      const SizedBox(height: AppSpacing.sm),
                      NavTile(
                        item: configuracoesItem,
                        selected: configuracoesItem.ativoPara(widget.currentRoute),
                        onTap: () => widget.onNavigate(configuracoesItem.route),
                        collapsed: mostrarConteudoRecolhido,
                      ),
                      _SignOutTile(onTap: widget.onLogout, collapsed: mostrarConteudoRecolhido),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.collapsed,
    required this.sidebarRecolhida,
    required this.onToggleCollapse,
  });

  /// Controla o layout do conteúdo (ícone só vs. ícone + texto) — pode
  /// ficar um instante atrás de [sidebarRecolhida] durante a animação.
  final bool collapsed;

  /// Estado lógico real da sidebar, usado pelo botão de alternar (tooltip e
  /// direção da seta) — este nunca atrasa, mesmo enquanto o conteúdo ainda
  /// está em transição.
  final bool sidebarRecolhida;

  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final toggleButton = CompactIconButton(
      tooltip: sidebarRecolhida ? 'Expandir menu' : 'Recolher menu',
      onPressed: onToggleCollapse,
      icon: Icon(sidebarRecolhida ? Icons.chevron_right : Icons.chevron_left),
      color: AppColors.sidebarForegroundMuted,
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            const _BrandMark(),
            const SizedBox(height: AppSpacing.xs),
            toggleButton,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          const _BrandMark(),
          const SizedBox(width: AppSpacing.smd),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'InvTec',
                  style: TextStyle(color: AppColors.sidebarForeground, fontWeight: FontWeight.w700, fontSize: 20),
                ),
                Text('Gestão de Patrimônio', style: TextStyle(color: AppColors.sidebarForegroundMuted, fontSize: 12)),
              ],
            ),
          ),
          toggleButton,
        ],
      ),
    );
  }
}

/// Versão reduzida da marca ("I"), usada tanto no cabeçalho expandido
/// (ao lado do nome por extenso) quanto no recolhido (sozinha).
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.sidebarSelectedBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Text(
        'I',
        style: TextStyle(color: AppColors.sidebarSelectedForeground, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}

/// "Sair" reaproveita o mesmo visual de hover/foco de [NavTile], mas nunca
/// fica "selecionado" (não é uma rota).
class _SignOutTile extends StatefulWidget {
  const _SignOutTile({required this.onTap, required this.collapsed});

  final VoidCallback onTap;
  final bool collapsed;

  @override
  State<_SignOutTile> createState() => _SignOutTileState();
}

class _SignOutTileState extends State<_SignOutTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: _hovering ? AppColors.sidebarSurfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: widget.onTap,
          child: Padding(
            padding: widget.collapsed
                ? const EdgeInsets.symmetric(vertical: AppSpacing.smd)
                : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smd),
            child: widget.collapsed
                ? const Center(child: Icon(Icons.logout, size: 20, color: AppColors.sidebarForegroundMuted))
                : const Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: AppColors.sidebarForegroundMuted),
                      SizedBox(width: AppSpacing.smd),
                      Text('Sair', style: TextStyle(color: AppColors.sidebarForegroundMuted, fontSize: 14)),
                    ],
                  ),
          ),
        ),
      ),
    );

    return widget.collapsed ? Tooltip(message: 'Sair', child: tile) : tile;
  }
}
