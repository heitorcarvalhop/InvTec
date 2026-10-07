import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_status.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/app_notification_repository_supabase.dart';
import '../domain/app_notification.dart';

final notificacoesControllerProvider =
    AsyncNotifierProvider<NotificacoesController, NotificacoesState>(NotificacoesController.new);

class NotificacoesState {
  const NotificacoesState({required this.recentes, required this.naoLidas});

  const NotificacoesState.vazio() : this(recentes: const [], naoLidas: 0);

  final List<AppNotification> recentes;
  final int naoLidas;
}

/// Estado administrativo de notificações — só existe de verdade para ADMIN.
///
/// Observa `authControllerProvider` via `ref.read` + `ref.listen` — NUNCA
/// `ref.watch` — mesmo padrão (e mesmo motivo) de
/// `SeiConclusaoLoteController`: `ref.watch` recriaria este `build()` a
/// CADA transição assíncrona do provider de auth (inclusive o próprio
/// carregamento inicial dele, antes de resolver), não só quando o usuário
/// resolvido realmente muda — e, combinado com a assinatura Realtime aberta
/// dentro de `build()`, isso é terreno fértil para o tipo de problema de
/// reentrância documentado no projeto (ver nota sobre o "ReplaySubject
/// gotcha" do gotrue). `ref.listen` só invalida quando a identidade/perfil
/// do usuário resolvido de fato muda — login, logout e troca de usuário
/// recriam este notifier (a subscription Realtime da sessão anterior é
/// sempre cancelada via `ref.onDispose` antes da nova rodar), mas um
/// refresh trivial do MESMO usuário não.
///
/// Infraestrutura administrativa (repositório + canal Realtime) só é
/// inicializada quando o profile atual é ADMIN **E** a conta está
/// `ACTIVE` — chegar a este `build` com qualquer outra combinação devolve
/// estado vazio sem abrir nada. Desde a Etapa 5, [AuthStatus.profile] fica
/// preenchido também em PENDING/REJECTED/BLOCKED (não é mais exclusivo de
/// ACTIVE) — por isso a comparação abaixo precisa incluir `status` além de
/// `perfil`/`id`: um ADMIN que é bloqueado continua com `perfil == admin` e
/// o mesmo `id`, então sem checar `status` este controller nunca invalidaria
/// a si mesmo, deixando a assinatura Realtime de `notifications` da sessão
/// anterior "pendurada" (sem efeito de segurança — a RLS `notifications_select`
/// já exige `has_perfil('ADMIN')`, que por sua vez exige `access_status =
/// 'ACTIVE'` — mas uma inconsistência de lógica real; achado da revisão de
/// QA da Etapa 5).
class NotificacoesController extends AsyncNotifier<NotificacoesState> {
  StreamSubscription<void>? _subscription;
  String? _profileIdConhecido;
  bool _eraAdminAtivoConhecido = false;

  @override
  Future<NotificacoesState> build() async {
    ref.onDispose(() => _subscription?.cancel());

    final authStatus = ref.read(authControllerProvider).value;
    final profile = authStatus?.profile;
    final ehAdminAtivo =
        authStatus?.status == AuthAccountStatus.active && profile?.perfil == ProfilePerfil.admin;
    _profileIdConhecido = profile?.id;
    _eraAdminAtivoConhecido = ehAdminAtivo;

    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return; // carregando/erro sem valor — nada a comparar ainda
      final novoStatus = next.value;
      final novoProfile = novoStatus?.profile;
      final novoId = novoProfile?.id;
      final novoEhAdminAtivo =
          novoStatus?.status == AuthAccountStatus.active && novoProfile?.perfil == ProfilePerfil.admin;
      if (novoId == _profileIdConhecido && novoEhAdminAtivo == _eraAdminAtivoConhecido) return;
      _profileIdConhecido = novoId;
      _eraAdminAtivoConhecido = novoEhAdminAtivo;
      ref.invalidateSelf();
    });

    if (!ehAdminAtivo || profile == null) {
      return const NotificacoesState.vazio();
    }

    final repository = ref.watch(appNotificationRepositoryProvider);

    // Fallback explícito (seção 23 do pedido): o Realtime só dispara um
    // refresh — o carregamento inicial (e qualquer reabertura do painel)
    // sempre busca o estado atual do servidor, nunca depende de um evento
    // já ter chegado.
    _subscription = repository.observarMudancas(destinatarioId: profile.id).listen((_) {
      ref.invalidateSelf();
    });

    final recentesFuture = repository.listarRecentes();
    final naoLidasFuture = repository.contarNaoLidas();
    final recentes = await recentesFuture;
    final naoLidas = await naoLidasFuture;

    return NotificacoesState(recentes: recentes, naoLidas: naoLidas);
  }

  Future<void> marcarComoLida(String id) async {
    await ref.read(appNotificationRepositoryProvider).marcarComoLida(id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> marcarTodasComoLidas() async {
    await ref.read(appNotificationRepositoryProvider).marcarTodasComoLidas();
    ref.invalidateSelf();
    await future;
  }

  /// Revalida a partir do servidor — usado ao abrir o painel, para nunca
  /// depender só de um evento Realtime já ter chegado.
  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}
