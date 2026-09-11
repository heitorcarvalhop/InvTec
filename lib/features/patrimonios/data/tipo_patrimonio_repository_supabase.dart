import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/tipo_patrimonio.dart';
import '../domain/tipo_patrimonio_repository.dart';

class TipoPatrimonioRepositorySupabase implements TipoPatrimonioRepository {
  TipoPatrimonioRepositorySupabase(this._client);

  final SupabaseClient _client;

  @override
  Future<List<TipoPatrimonio>> listarAtivos() async {
    try {
      final rows = await _client
          .from('tipos_patrimonio')
          .select()
          .eq('ativo', true)
          .order('nome');
      return rows.map(TipoPatrimonio.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException('Falha ao listar tipos de patrimônio', cause: e);
    }
  }
}

final tipoPatrimonioRepositoryProvider = Provider<TipoPatrimonioRepository>((
  ref,
) {
  return TipoPatrimonioRepositorySupabase(Supabase.instance.client);
});
