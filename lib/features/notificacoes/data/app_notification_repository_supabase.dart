import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/app_notification.dart';
import '../domain/app_notification_repository.dart';

class AppNotificationRepositorySupabase implements AppNotificationRepository {
  AppNotificationRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> listarRecentes({int limite = 10}) async {
    try {
      final rows = await _client
          .from('notifications')
          .select()
          .order('criado_em', ascending: false)
          .limit(limite);
      return rows.map(AppNotification.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException('Não foi possível carregar as notificações.', cause: e);
    }
  }

  @override
  Future<int> contarNaoLidas() async {
    try {
      final response = await _client
          .from('notifications')
          .select('id')
          .filter('lida_em', 'is', null)
          .count(CountOption.exact);
      return response.count;
    } on PostgrestException catch (e) {
      throw AppException('Não foi possível contar notificações não lidas.', cause: e);
    }
  }

  @override
  Future<void> marcarComoLida(String id) async {
    try {
      await _client.rpc('marcar_notificacao_lida', params: {'p_notification_id': id});
    } on PostgrestException catch (e) {
      throw AppException('Não foi possível marcar a notificação como lida.', cause: e);
    }
  }

  @override
  Future<void> marcarTodasComoLidas() async {
    try {
      await _client.rpc('marcar_todas_notificacoes_lidas');
    } on PostgrestException catch (e) {
      throw AppException('Não foi possível marcar as notificações como lidas.', cause: e);
    }
  }

  // Sinal puro (sem payload): o consumidor reage buscando o estado atual do
  // servidor de novo — nunca tenta remontar o estado a partir do payload do
  // evento. `filter` por `destinatario_id` é defesa em profundidade (além da
  // RLS, que já garante que só o próprio ADMIN recebe o evento): o Realtime
  // do Supabase avalia a policy de SELECT antes de emitir, então mesmo sem
  // este filtro nenhum outro usuário jamais veria o evento de outro.
  @override
  Stream<void> observarMudancas({required String destinatarioId}) {
    late final StreamController<void> controller;
    late final RealtimeChannel channel;

    controller = StreamController<void>.broadcast(
      onCancel: () => unawaited(_client.removeChannel(channel)),
    );

    channel = _client
        .channel('notifications:$destinatarioId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'destinatario_id',
            value: destinatarioId,
          ),
          callback: (payload) => controller.add(null),
        )
        .subscribe();

    return controller.stream;
  }
}

final appNotificationRepositoryProvider = Provider<AppNotificationRepository>((ref) {
  return AppNotificationRepositorySupabase(Supabase.instance.client);
});
