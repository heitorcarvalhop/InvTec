import 'dart:async';

import 'package:invtec/features/notificacoes/domain/app_notification.dart';
import 'package:invtec/features/notificacoes/domain/app_notification_repository.dart';

/// Fake em memória de [AppNotificationRepository] — sem Supabase real.
/// [emitirMudancaParaTeste] simula um evento Realtime chegando.
class FakeAppNotificationRepository implements AppNotificationRepository {
  FakeAppNotificationRepository({List<AppNotification> notificacoes = const []})
    : _notificacoes = List.of(notificacoes);

  List<AppNotification> _notificacoes;

  // Fonte única dos eventos "chegou algo novo" — cada chamada a
  // [observarMudancas] ganha seu PRÓPRIO StreamController relayado a partir
  // desta fonte, para que o cancelamento de UMA chamada (ex.: a sessão
  // anterior, ao deslogar) seja contável independentemente das demais —
  // ver [cancelamentosCount].
  final _mudancasSource = StreamController<void>.broadcast();

  int observarMudancasCallCount = 0;
  int marcarComoLidaCallCount = 0;
  int marcarTodasComoLidasCallCount = 0;

  /// Quantas vezes uma stream devolvida por [observarMudancas] foi
  /// cancelada (ex.: `ref.onDispose` do controller real cancelando a
  /// subscription Realtime da sessão anterior). Prova direta de que o
  /// logout/troca de usuário não deixa uma assinatura "pendurada".
  int cancelamentosCount = 0;
  String? destinatarioIdObservado;

  @override
  Future<List<AppNotification>> listarRecentes({int limite = 10}) async {
    final ordenadas = List.of(_notificacoes)..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
    return ordenadas.take(limite).toList();
  }

  @override
  Future<int> contarNaoLidas() async => _notificacoes.where((n) => !n.lida).length;

  @override
  Future<void> marcarComoLida(String id) async {
    marcarComoLidaCallCount++;
    _notificacoes = [
      for (final n in _notificacoes)
        if (n.id == id && n.lidaEm == null)
          AppNotification(
            id: n.id,
            eventId: n.eventId,
            tipo: n.tipo,
            titulo: n.titulo,
            corpo: n.corpo,
            alvoUsuarioId: n.alvoUsuarioId,
            lidaEm: DateTime(2026, 1, 1),
            resolvidaEm: n.resolvidaEm,
            criadaEm: n.criadaEm,
          )
        else
          n,
    ];
  }

  @override
  Future<void> marcarTodasComoLidas() async {
    marcarTodasComoLidasCallCount++;
    _notificacoes = [
      for (final n in _notificacoes)
        AppNotification(
          id: n.id,
          eventId: n.eventId,
          tipo: n.tipo,
          titulo: n.titulo,
          corpo: n.corpo,
          alvoUsuarioId: n.alvoUsuarioId,
          lidaEm: n.lidaEm ?? DateTime(2026, 1, 1),
          resolvidaEm: n.resolvidaEm,
          criadaEm: n.criadaEm,
        ),
    ];
  }

  @override
  Stream<void> observarMudancas({required String destinatarioId}) {
    observarMudancasCallCount++;
    destinatarioIdObservado = destinatarioId;

    late final StreamSubscription<void> relaySubscription;
    final controller = StreamController<void>.broadcast(
      onCancel: () {
        cancelamentosCount++;
        relaySubscription.cancel();
      },
    );
    relaySubscription = _mudancasSource.stream.listen(controller.add);

    return controller.stream;
  }

  void emitirMudancaParaTeste() => _mudancasSource.add(null);

  /// SÓ PARA TESTE — simula uma nova notificação chegando no servidor
  /// (sem emitir sozinho o evento Realtime — use junto de
  /// [emitirMudancaParaTeste]).
  void adicionarParaTeste(AppNotification notificacao) {
    _notificacoes = [..._notificacoes, notificacao];
  }

  void dispose() => _mudancasSource.close();
}
