import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      await _client.auth.signInWithPassword(email: email, password: password);
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
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositorySupabase(Supabase.instance.client);
});
