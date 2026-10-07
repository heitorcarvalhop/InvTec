import 'app_notification.dart';

abstract class AppNotificationRepository {
  /// Mais recentes primeiro. RLS já restringe ao próprio destinatário —
  /// nenhum filtro adicional é necessário aqui.
  Future<List<AppNotification>> listarRecentes({int limite = 10});

  /// Total não lido do destinatário atual (HEAD request — sem carregar as
  /// linhas).
  Future<int> contarNaoLidas();

  /// Idempotente: já lida não gera erro nem reseta `lidaEm`. Nunca aceita
  /// `userId` — a RPC usa `auth.uid()`.
  Future<void> marcarComoLida(String id);

  /// Só as notificações do próprio destinatário (resolvidas ou não).
  Future<void> marcarTodasComoLidas();

  /// Emite um sinal (sem payload) a cada INSERT/UPDATE relevante — o
  /// consumidor reage buscando o estado atual do servidor de novo, nunca
  /// tentando reconstruir o estado a partir do payload do evento. Mais
  /// simples e nunca diverge da verdade do servidor, mesmo se um evento for
  /// perdido.
  Stream<void> observarMudancas({required String destinatarioId});
}
