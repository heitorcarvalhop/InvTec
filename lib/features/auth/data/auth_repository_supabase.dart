import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error_messages.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/auth_repository.dart';
import '../domain/profile.dart';
import 'auth_error_mapper.dart';

class AuthRepositorySupabase implements AuthRepository {
  AuthRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      // trim: e-mail colado com espaço (comum em copiar/colar) nunca deve
      // virar "e-mail ou senha inválidos" por um detalhe de formatação.
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } catch (e) {
      throw AppException(mapAuthErrorMessage(e), cause: e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw AppException(mapAuthErrorMessage(e), cause: e);
    }
  }

  @override
  Future<AuthSignUpResult> signUp({
    required String nome,
    required String cpf,
    required String email,
    required String senha,
  }) async {
    try {
      // `data` só recebe nome/cpf — NUNCA perfil/ativo/access_status/
      // approved_by ou qualquer chave de privilégio (ver AuthRepository.
      // signUp e handle_new_user no banco, que ignora qualquer outra
      // chave mesmo que chegasse). A assinatura tipada desta função já
      // impede, por construção, que o caller injete algo além disso.
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: senha,
        data: {'nome': nome, 'cpf': cpf},
      );
      return AuthSignUpResult(sessaoCriada: response.session != null);
    } catch (e) {
      throw AppException(mapAuthErrorMessage(e), cause: e);
    }
  }

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<Profile?> fetchProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return row == null ? null : Profile.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException('Falha ao carregar perfil do usuário', cause: e);
    }
  }

  @override
  Stream<void> get authStateChanges =>
      _client.auth.onAuthStateChange.map((_) {});

  // Sinal puro (sem payload), mesmo padrão de
  // `AppNotificationRepositorySupabase.observarMudancas`: o consumidor
  // reage buscando o estado atual do servidor de novo, nunca tenta montar o
  // novo profile a partir do payload do evento.
  @override
  Stream<void> observeProfileChanges(String userId) {
    late final StreamController<void> controller;
    late final RealtimeChannel channel;

    controller = StreamController<void>.broadcast(
      onCancel: () => unawaited(_client.removeChannel(channel)),
    );

    channel = _client
        .channel('profiles:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) => controller.add(null),
        )
        .subscribe();

    return controller.stream;
  }

  // Ação self-service do próprio usuário REJECTED — ver doc de
  // AuthRepository.reenviarSolicitacao. Usa `traduzirErroSupabase` (não
  // `mapAuthErrorMessage`, que é específico de erros de GoTrue/login): o
  // erro aqui vem de uma RPC Postgrest, mesma família de erro das RPCs
  // administrativas já tratadas por essa função.
  @override
  Future<void> reenviarSolicitacao() async {
    try {
      await _client.rpc('reenviar_solicitacao_acesso');
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositorySupabase(Supabase.instance.client);
});
