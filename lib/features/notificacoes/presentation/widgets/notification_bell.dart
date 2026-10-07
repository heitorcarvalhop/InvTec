import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/compact_icon_button.dart';
import '../notificacoes_controller.dart';
import 'notification_panel.dart';

/// Largura do popover no desktop/tablet — folga para título + 2 linhas de
/// corpo sem quebrar em muitas linhas, mas sem virar um painel enorme colado
/// na topbar (ver `_DesktopTopBar` em `lib/core/shell/app_shell.dart`, que
/// integra este widget; não editado por este arquivo).
const double _larguraPopover = 360;

/// Altura máxima do popover — abaixo disso o painel encolhe para o
/// conteúdo real (poucas notificações, ou os estados vazio/erro/loading);
/// acima disso a lista interna rola (ver `ListView.separated` com
/// `shrinkWrap: true` em [NotificationPanel]).
const double _alturaMaximaPopover = 420;

/// Formata a contagem de não lidas para o badge — nunca mais que 3
/// caracteres visíveis ("1", "42", "99+").
String formatarContagemNaoLidas(int naoLidas) => naoLidas > 99 ? '99+' : '$naoLidas';

/// Sino de notificações administrativas do topbar — só é útil para quem já
/// tem um `NotificacoesController` de verdade (perfil ADMIN logado; ver
/// `NotificacoesController.build`), mas o widget em si não sabe nem precisa
/// saber disso: um estado vazio (`NotificacoesState.vazio()`) já faz o sino
/// aparecer sem badge, para quem integrar isto decidir livremente mostrá-lo
/// sempre ou só para ADMIN.
///
/// Loading/erro na revalidação nunca travam este widget nem assustam o
/// usuário: é um recurso secundário da topbar, então na pior hipótese o
/// sino aparece normal, sem badge, silenciosamente (o painel aberto por
/// toque, sim, mostra um estado de erro com "Tentar de novo" — lá faz
/// sentido, porque o usuário pediu para ver as notificações; aqui, no
/// ícone fechado, não).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(notificacoesControllerProvider);
    final naoLidas = asyncState.value?.naoLidas ?? 0;
    final temNaoLidas = naoLidas > 0;

    final tooltip = temNaoLidas
        ? 'Notificações, ${naoLidas == 1 ? '1 não lida' : '$naoLidas não lidas'}'
        : 'Notificações';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CompactIconButton(
          icon: Icon(temNaoLidas ? Icons.notifications : Icons.notifications_outlined),
          tooltip: tooltip,
          onPressed: () => _abrirPainel(context),
        ),
        if (temNaoLidas)
          Positioned(
            right: -2,
            top: -2,
            // Nunca intercepta toque: a área clicável continua sendo só o
            // `CompactIconButton` por baixo, mesmo no cantinho onde o badge
            // visualmente se sobrepõe a ele.
            child: IgnorePointer(child: _UnreadBadge(naoLidas: naoLidas)),
          ),
      ],
    );
  }

  void _abrirPainel(BuildContext context) {
    if (context.screenSize == ScreenSize.mobile) {
      _abrirComoBottomSheet(context);
    } else {
      _abrirComoPopover(context);
    }
  }

  /// Telas estreitas (mobile — ver `Breakpoints.mobileMax`): um popover de
  /// largura fixa correria risco de overflow horizontal ou de ficar
  /// espremido contra a borda da tela, então usamos a solução idiomática
  /// do Material para isso, que já ocupa a largura inteira disponível sem
  /// nenhum cálculo manual de posição.
  void _abrirComoBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final alturaTela = MediaQuery.sizeOf(sheetContext).height;
        return SafeArea(
          child: SizedBox(
            height: alturaTela * 0.75,
            child: const NotificationPanel(),
          ),
        );
      },
    );
  }

  /// Desktop/tablet: popover ancorado ao próprio sino via `showMenu` — o
  /// mesmo mecanismo usado internamente por `PopupMenuButton` (inclusive o
  /// cálculo de posição abaixo, igual ao da própria biblioteca Flutter),
  /// escolhido em vez de `OverlayPortal`/`MenuAnchor` por já vir com
  /// dismissal por toque fora, tecla Esc e reposicionamento para nunca
  /// sair da tela de graça — sem precisar implementar nada disso à mão.
  /// `PopupMenuItem.enabled: false` evita que qualquer toque dentro do
  /// painel feche o menu sozinho (os próprios itens/botões internos do
  /// [NotificationPanel] é que decidem o que acontece a cada toque).
  void _abrirComoPopover(BuildContext context) {
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
    );

    showMenu<void>(
      context: context,
      position: position,
      constraints: const BoxConstraints(maxWidth: _larguraPopover, minWidth: _larguraPopover),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _alturaMaximaPopover),
            child: NotificationPanel(),
          ),
        ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.naoLidas});

  final int naoLidas;

  @override
  Widget build(BuildContext context) {
    // Vermelho (`errorBackground`/`errorForeground`) em vez de
    // `infoBackground`: não é tecnicamente um erro, mas é a convenção
    // universal para contadores de pendência/não lidas (email, redes
    // sociais...) — maximiza a percepção do badge num sino pequeno no
    // canto da topbar, o que o azul de "info" (já usado para estados
    // neutros informativos no resto do app) não faria tão bem aqui.
    final colors = Theme.of(context).statusColors;

    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.errorBackground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Theme.of(context).surfaceColors.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        formatarContagemNaoLidas(naoLidas),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.errorForeground,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          height: 1,
        ),
      ),
    );
  }
}
