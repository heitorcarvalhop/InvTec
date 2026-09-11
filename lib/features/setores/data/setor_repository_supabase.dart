import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/postgrest_filter.dart';
import '../domain/setor.dart';
import '../domain/setor_repository.dart';
import 'setor_error_mapper.dart';

class SetorRepositorySupabase implements SetorRepository {
  SetorRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Setor>> listarAtivos() async {
    try {
      final rows = await _client
          .from('setores')
          .select()
          .eq('ativo', true)
          .order('nome');
      return rows.map(Setor.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(mapSetorErrorMessage(e), cause: e);
    }
  }

  @override
  Future<List<Setor>> listar({
    String? busca,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _client.from('setores').select();

      final termo = busca?.trim();
      if (termo != null && termo.isNotEmpty) {
        final valor = postgrestFilterValue('%$termo%');
        query = query.or('nome.ilike.$valor,sigla.ilike.$valor');
      }

      final rows = await query
          .order('ativo', ascending: false)
          .order('nome', ascending: true)
          .range(offset, offset + limit - 1);

      return rows.map(Setor.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(mapSetorErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Setor> criar({
    required String nome,
    String? sigla,
    String? descricao,
  }) async {
    try {
      final row = await _client
          .from('setores')
          .insert({
            'nome': nome.trim(),
            'sigla': _semEspacosOuNulo(sigla),
            'descricao': _semEspacosOuNulo(descricao),
          })
          .select()
          .single();
      return Setor.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapSetorErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Setor> atualizar({
    required String id,
    required String nome,
    String? sigla,
    String? descricao,
  }) async {
    try {
      final row = await _client
          .from('setores')
          .update({
            'nome': nome.trim(),
            'sigla': _semEspacosOuNulo(sigla),
            'descricao': _semEspacosOuNulo(descricao),
          })
          .eq('id', id)
          .select()
          .single();
      return Setor.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapSetorErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Setor> alterarAtivo({required String id, required bool ativo}) async {
    try {
      final row = await _client
          .from('setores')
          .update({'ativo': ativo})
          .eq('id', id)
          .select()
          .single();
      return Setor.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapSetorErrorMessage(e), cause: e);
    }
  }
}

String? _semEspacosOuNulo(String? valor) {
  final normalizado = valor?.trim();
  return (normalizado == null || normalizado.isEmpty) ? null : normalizado;
}

final setorRepositoryProvider = Provider<SetorRepository>((ref) {
  return SetorRepositorySupabase(Supabase.instance.client);
});
