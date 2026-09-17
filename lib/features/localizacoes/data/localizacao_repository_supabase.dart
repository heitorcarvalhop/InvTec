import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/localizacao.dart';
import '../domain/localizacao_repository.dart';
import 'localizacao_error_mapper.dart';

class LocalizacaoRepositorySupabase implements LocalizacaoRepository {
  LocalizacaoRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Localizacao>> listarPorSetor(
    String setorId, {
    bool somenteAtivas = true,
  }) async {
    try {
      var query = _client.from('localizacoes').select().eq('setor_id', setorId);
      if (somenteAtivas) {
        query = query.eq('ativo', true);
      }
      final rows = await query.order('nome');
      return rows.map(Localizacao.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(mapLocalizacaoErrorMessage(e), cause: e);
    }
  }

  @override
  Future<List<Localizacao>> listarTodas({bool somenteAtivas = true}) async {
    try {
      var query = _client.from('localizacoes').select();
      if (somenteAtivas) {
        query = query.eq('ativo', true);
      }
      final rows = await query.order('nome');
      return rows.map(Localizacao.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException(mapLocalizacaoErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Localizacao?> buscarPorId(String id) async {
    try {
      final row = await _client.from('localizacoes').select().eq('id', id).maybeSingle();
      return row == null ? null : Localizacao.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapLocalizacaoErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Localizacao> criar({
    required String setorId,
    required String nome,
    String? sigla,
  }) async {
    try {
      final row = await _client
          .from('localizacoes')
          .insert({
            'setor_id': setorId,
            'nome': nome.trim(),
            'sigla': _semEspacosOuNulo(sigla),
          })
          .select()
          .single();
      return Localizacao.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapLocalizacaoErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Localizacao> atualizar({
    required String id,
    required String nome,
    String? sigla,
  }) async {
    try {
      final row = await _client
          .from('localizacoes')
          .update({'nome': nome.trim(), 'sigla': _semEspacosOuNulo(sigla)})
          .eq('id', id)
          .select()
          .single();
      return Localizacao.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapLocalizacaoErrorMessage(e), cause: e);
    }
  }

  @override
  Future<Localizacao> alterarAtivo({required String id, required bool ativo}) async {
    try {
      final row = await _client
          .from('localizacoes')
          .update({'ativo': ativo})
          .eq('id', id)
          .select()
          .single();
      return Localizacao.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException(mapLocalizacaoErrorMessage(e), cause: e);
    }
  }
}

String? _semEspacosOuNulo(String? valor) {
  final normalizado = valor?.trim();
  return (normalizado == null || normalizado.isEmpty) ? null : normalizado;
}

final localizacaoRepositoryProvider = Provider<LocalizacaoRepository>((ref) {
  return LocalizacaoRepositorySupabase(Supabase.instance.client);
});
