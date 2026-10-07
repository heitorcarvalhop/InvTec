import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error_messages.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/permissao_efetiva.dart';
import '../domain/permissions_repository.dart';

class PermissionsRepositorySupabase implements PermissionsRepository {
  PermissionsRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> minhasPermissoes() async {
    try {
      final rows = await _client.rpc('minhas_permissoes') as List<dynamic>;
      return rows.map((row) => row['permission_key'] as String).toSet();
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<List<PermissaoEfetiva>> obterPermissoesUsuario(String userId) async {
    try {
      final rows = await _client.rpc(
        'obter_permissoes_usuario',
        params: {'p_user_id': userId},
      ) as List<dynamic>;
      return rows
          .map((row) => PermissaoEfetiva.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<void> definirPermissaoUsuario({
    required String userId,
    required String permissionKey,
    required bool granted,
  }) async {
    try {
      await _client.rpc(
        'definir_permissao_usuario',
        params: {
          'p_user_id': userId,
          'p_permission_key': permissionKey,
          'p_granted': granted,
        },
      );
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<void> removerOverridePermissaoUsuario({
    required String userId,
    required String permissionKey,
  }) async {
    try {
      await _client.rpc(
        'remover_override_permissao_usuario',
        params: {'p_user_id': userId, 'p_permission_key': permissionKey},
      );
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<int> resetarPermissoesUsuario(String userId) async {
    try {
      final resultado = await _client.rpc(
        'resetar_permissoes_usuario',
        params: {'p_user_id': userId},
      );
      return resultado as int;
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }
}

final permissionsRepositoryProvider = Provider<PermissionsRepository>((ref) {
  return PermissionsRepositorySupabase(Supabase.instance.client);
});
