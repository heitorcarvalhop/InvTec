import 'package:flutter/material.dart';

/// Destino da [InvTecBottomNav].
class BottomNavItem {
  const BottomNavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// Barra inferior do celular: destinos de largura igual, ícone de 24 dp,
/// legenda sempre em UMA linha (reduz a fonte em vez de quebrar, mesmo com
/// fonte ampliada) e respeito à área segura do sistema (barra de gestos/
/// botões do Android). O `Scaffold` reserva a altura total, então o conteúdo
/// da página nunca fica por baixo dela.
class InvTecBottomNav extends StatelessWidget {
  const InvTecBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double altura = 64;
  static const double _icone = 24;

  final List<BottomNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cores = theme.colorScheme;
    return Material(
      color: theme.navigationBarTheme.backgroundColor ?? cores.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cores.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: altura,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _Destino(
                      item: items[i],
                      selecionado: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Destino extends StatelessWidget {
  const _Destino({
    required this.item,
    required this.selecionado,
    required this.onTap,
  });

  final BottomNavItem item;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final cor = selecionado ? cores.onPrimaryContainer : cores.onSurfaceVariant;
    // Tamanho fixo de legenda: a barra tem altura fixa, então a fonte do
    // sistema não a cresce — o texto é reduzido para caber em uma linha.
    final estilo = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: selecionado ? cores.onSurface : cores.onSurfaceVariant,
      fontSize: 11,
      height: 1.1,
      fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
    );
    return Semantics(
      button: true,
      selected: selecionado,
      label: item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selecionado
                      ? cores.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  size: InvTecBottomNav._icone,
                  color: cor,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: estilo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
