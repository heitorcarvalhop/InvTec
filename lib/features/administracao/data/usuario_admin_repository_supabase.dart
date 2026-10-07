import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error_messages.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/domain/profile.dart';
import '../domain/usuario_admin_repository.dart';

class UsuarioAdminRepositorySupabase implements UsuarioAdminRepository {
  UsuarioAdminRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Profile>> listar({
    required ProfileAccessStatus status,
    String? busca,
  }) async {
    try {
      // Sem RPC de listagem (não existe uma — ver comentário em
      // UsuarioAdminRepository): filtro no servidor via SELECT comum, que a
      // policy `profiles_select` já libera para ADMIN ACTIVE ler qualquer
      // linha. Sem paginação explícita: a tabela `profiles` deste projeto
      // tem poucos usuários (nunca um por patrimônio/movimentação) — um
      // único filtro por `access_status` já reduz o resultado o bastante
      // para não justificar `.range(...)` nesta etapa.
      var query = _client.from('profiles').select().eq('access_status', status.value);

      final termo = busca?.trim();
      if (termo != null && termo.isNotEmpty) {
        // `.or(...)` do Postgrest usa vírgula como separador de condições —
        // removida do termo para nunca quebrar o parsing em dois filtros
        // acidentais. Dígitos extraídos à parte para também casar CPF
        // (armazenado só com dígitos — ver trigger normalize_profile_cpf),
        // mesmo que o usuário digite com pontuação.
        final termoSemVirgula = termo.replaceAll(',', '');
        final apenasDigitos = termo.replaceAll(RegExp(r'[^0-9]'), '');
        final condicoes = <String>[
          'nome.ilike.%$termoSemVirgula%',
          'email.ilike.%$termoSemVirgula%',
          if (apenasDigitos.isNotEmpty) 'cpf.ilike.%$apenasDigitos%',
        ];
        query = query.or(condicoes.join(','));
      }

      final rows = await query.order('criado_em', ascending: false);
      return rows.map(Profile.fromJson).toList();
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> buscarPorId(String userId) async {
    try {
      final row = await _client.from('profiles').select().eq('id', userId).single();
      return Profile.fromJson(row);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> aprovar({required String userId, required ProfilePerfil perfil}) async {
    try {
      final row = await _client.rpc(
        'aprovar_usuario',
        params: {'p_user_id': userId, 'p_perfil': perfil.value},
      );
      return Profile.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> rejeitar({required String userId, required String motivo}) async {
    try {
      final row = await _client.rpc(
        'rejeitar_usuario',
        params: {'p_user_id': userId, 'p_motivo': motivo},
      );
      return Profile.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> bloquear({required String userId, required String motivo}) async {
    try {
      final row = await _client.rpc(
        'bloquear_usuario',
        params: {'p_user_id': userId, 'p_motivo': motivo},
      );
      return Profile.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> desbloquear(String userId) async {
    try {
      final row = await _client.rpc('desbloquear_usuario', params: {'p_user_id': userId});
      return Profile.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> alterarIdentidade({
    required String userId,
    required String nome,
    required String cpf,
    required String motivo,
  }) async {
    try {
      final row = await _client.rpc(
        'alterar_identidade_usuario',
        params: {
          'p_user_id': userId,
          'p_novo_nome': nome,
          'p_novo_cpf': cpf,
          'p_motivo': motivo,
        },
      );
      return Profile.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }

  @override
  Future<Profile> alterarPerfil({required String userId, required ProfilePerfil perfil}) async {
    try {
      final row = await _client.rpc(
        'alterar_perfil_usuario',
        params: {'p_user_id': userId, 'p_novo_perfil': perfil.value},
      );
      return Profile.fromJson(row as Map<String, dynamic>);
    } catch (e) {
      throw AppException(traduzirErroSupabase(e), cause: e);
    }
  }
}

final usuarioAdminRepositoryProvider = Provider<UsuarioAdminRepository>((ref) {
  return UsuarioAdminRepositorySupabase(Supabase.instance.client);
});
