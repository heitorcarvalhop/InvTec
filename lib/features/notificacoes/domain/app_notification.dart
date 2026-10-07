/// Tipos de notificação conhecidos nesta etapa — usados só para escolher
/// ícone/texto de apoio na UI. `tipo` em si é texto livre no banco (ver
/// `supabase/migrations/20261007100000_add_notifications.sql`): uma
/// categoria nova no futuro (ex. `EMAIL_CHANGE_REQUEST`) chega como string
/// desconhecida e cai no fallback — nunca quebra o app.
abstract final class TipoNotificacao {
  static const String acessoSolicitado = 'ACCESS_REQUEST_CREATED';
  static const String acessoReenviado = 'ACCESS_REQUEST_RESUBMITTED';
}

/// Aviso administrativo — nunca a fonte de verdade de nenhum estado (ver
/// `profiles.access_status`). Nome evita "Notification" (conflita com o
/// `Notification`/`ChangeNotifier` do próprio Flutter).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventId,
    required this.tipo,
    required this.titulo,
    required this.corpo,
    required this.alvoUsuarioId,
    this.lidaEm,
    this.resolvidaEm,
    required this.criadaEm,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      tipo: json['tipo'] as String,
      titulo: json['titulo'] as String,
      corpo: json['corpo'] as String,
      alvoUsuarioId: json['alvo_usuario_id'] as String,
      lidaEm: json['lida_em'] == null ? null : DateTime.parse(json['lida_em'] as String),
      resolvidaEm: json['resolvida_em'] == null ? null : DateTime.parse(json['resolvida_em'] as String),
      criadaEm: DateTime.parse(json['criado_em'] as String),
    );
  }

  final String id;
  final String eventId;
  final String tipo;
  final String titulo;
  final String corpo;
  final String alvoUsuarioId;
  final DateTime? lidaEm;
  final DateTime? resolvidaEm;
  final DateTime criadaEm;

  bool get lida => lidaEm != null;
  bool get resolvida => resolvidaEm != null;
}
