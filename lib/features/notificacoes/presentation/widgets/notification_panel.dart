import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/app_notification.dart';
import '../notificacoes_controller.dart';

/// Quantos itens o painel desenha no máximo — defesa extra além do limite
/// que `repository.listarRecentes()` já aplica no servidor (ver
/// `NotificacoesController.build`): nunca confiar só no lado de dentro.
const int _maximoExibido = 10;

/// Formata a diferença entre [quando] e [agora] (padrão `DateTime.now()`)
/// como tempo relativo em português — "há 2 min", "há 3h", "há 2 dias"...
/// Função pura, sem dependências externas, para não precisar de nenhum
/// pacote de i18n/data só para isto.
String formatarTempoRelativo(DateTime quando, {DateTime? agora}) {
  final referencia = agora ?? DateTime.now();
  final diferenca = referencia.difference(quando);

  if (diferenca.inSeconds < 60) return 'agora mesmo';
  if (diferenca.inMinutes < 60) return 'há ${diferenca.inMinutes} min';
  if (diferenca.inHours < 24) return 'há ${diferenca.inHours}h';
  if (diferenca.inDays < 30) {
    final dias = diferenca.inDays;
    return 'há $dias ${dias == 1 ? 'dia' : 'dias'}';
  }
  if (diferenca.inDays < 365) {
    final meses = (diferenca.inDays / 30).floor();
    return 'há $meses ${meses == 1 ? 'mês' : 'meses'}';
  }
  final anos = (diferenca.inDays / 365).floor();
  return 'há $anos ${anos == 1 ? 'ano' : 'anos'}';
}

/// Painel de notificações administrativas — conteúdo puro, sem decidir
/// *como* é ancorado na tela: o popover do desktop/tablet (`showMenu`) e o
/// `BottomSheet` do mobile (ver [NotificationBell]) só impõem uma largura/
/// altura máxima de fora; este widget nunca fixa a própria largura, para
/// nunca dar overflow horizontal em nenhum dos dois usos.
class NotificationPanel extends ConsumerWidget {
  const NotificationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(notificacoesControllerProvider);
    final notifier = ref.read(notificacoesControllerProvider.notifier);

    // Preferimos sempre o último valor conhecido (ainda que uma revalidação
    // esteja em andamento ou tenha falhado) a trocar a lista já visível por
    // um spinner/erro — o painel só foi aberto porque havia algo para ver.
    final estado = asyncState.value;

    final Widget corpo;
    if (estado != null) {
      corpo = estado.recentes.isEmpty
          ? const _VazioState()
          : _ListaNotificacoes(notificacoes: estado.recentes.take(_maximoExibido).toList());
    } else if (asyncState.hasError) {
      corpo = _ErroState(onTentarDeNovo: notifier.recarregar);
    } else {
      corpo = const _CarregandoState();
    }

    return Material(
      color: Theme.of(context).surfaceColors.surfaceElevated,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            naoLidas: estado?.naoLidas ?? 0,
            onMarcarTodasComoLidas: notifier.marcarTodasComoLidas,
          ),
          Divider(height: 1, color: Theme.of(context).surfaceColors.border),
          Flexible(child: corpo),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.naoLidas, required this.onMarcarTodasComoLidas});

  final int naoLidas;
  final Future<void> Function() onMarcarTodasComoLidas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.smd, AppSpacing.sm, AppSpacing.smd),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Notificações',
              style: AppTypography.cardTitle(context),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Padding/tamanho de texto reduzidos (em vez do `TextButton`
          // padrão) para o rótulo comprido nunca disputar espaço com o
          // título a ponto de causar overflow em painéis estreitos (ex.
          // bottom sheet mobile) — ainda um alvo de toque confortável.
          TextButton(
            onPressed: naoLidas == 0 ? null : () => onMarcarTodasComoLidas(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
            child: const Text(
              'Marcar todas como lidas',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarregandoState extends StatelessWidget {
  const _CarregandoState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErroState extends StatelessWidget {
  const _ErroState({required this.onTentarDeNovo});

  final Future<void> Function() onTentarDeNovo;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      message: 'Não foi possível carregar as notificações.',
      actionLabel: 'Tentar de novo',
      onAction: () => onTentarDeNovo(),
    );
  }
}

class _VazioState extends StatelessWidget {
  const _VazioState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(icon: Icons.notifications_none, message: 'Nenhuma notificação por aqui');
  }
}

class _ListaNotificacoes extends StatelessWidget {
  const _ListaNotificacoes({required this.notificacoes});

  final List<AppNotification> notificacoes;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: notificacoes.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: Theme.of(context).surfaceColors.border),
      itemBuilder: (context, index) => _NotificationTile(notificacao: notificacoes[index]),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notificacao});

  final AppNotification notificacao;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lida = notificacao.lida;
    final resolvida = notificacao.resolvida;
    final colorScheme = Theme.of(context).colorScheme;

    void aoTocar() {
      // Idempotente no backend de qualquer forma, mas evitamos a chamada
      // (e o `invalidateSelf` que ela dispara) quando já está lida.
      if (!lida) {
        ref.read(notificacoesControllerProvider.notifier).marcarComoLida(notificacao.id);
      }

      // Navegação (seção 44): só para os tipos de solicitação de acesso —
      // os únicos com um `alvoUsuarioId` que hoje tem uma tela real para
      // onde ir. Uma notificação resolvida continua navegável (histórico);
      // se o usuário-alvo não existir mais, a própria tela de detalhe trata
      // isso como erro amigável (ver `AdminUsuarioDetalhePage`), sem crash
      // aqui. `Navigator.pop` fecha o popover/bottom sheet que hospeda este
      // painel (`showMenu`/`showModalBottomSheet`, ver `NotificationBell`)
      // antes de navegar — sem isso o painel ficaria aberto por cima da
      // nova rota.
      if (notificacao.tipo == TipoNotificacao.acessoSolicitado ||
          notificacao.tipo == TipoNotificacao.acessoReenviado) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        context.push('/administracao/usuarios/${notificacao.alvoUsuarioId}');
      }
    }

    final tile = ListTile(
      onTap: aoTocar,
      leading: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: SizedBox(
          width: 8,
          height: 8,
          child: lida
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                ),
        ),
      ),
      title: Text(
        notificacao.titulo,
        style: AppTypography.body(context)?.copyWith(fontWeight: lida ? FontWeight.w500 : FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notificacao.corpo, style: AppTypography.auxiliary(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(formatarTempoRelativo(notificacao.criadaEm), style: AppTypography.caption(context)),
          if (resolvida) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Solicitação analisada', style: AppTypography.caption(context)),
          ],
        ],
      ),
    );

    // Opacidade reduzida (nunca escondida) para sinalizar que a solicitação
    // já foi analisada — combinável com lida/não lida: uma notificação
    // resolvida e ainda não lida mantém o indicador de não lida, só com
    // menos destaque geral do item.
    final conteudo = resolvida ? Opacity(opacity: 0.6, child: tile) : tile;

    // Tooltip só faz sentido quando tocar tem efeito de verdade — uma
    // notificação já lida não ganha ação nenhuma ao ser tocada.
    return lida ? conteudo : Tooltip(message: 'Marcar como lida', child: conteudo);
  }
}
