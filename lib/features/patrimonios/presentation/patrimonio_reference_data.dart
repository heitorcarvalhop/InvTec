import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../setores/data/setor_repository_supabase.dart';
import '../../setores/domain/setor.dart';
import '../data/tipo_patrimonio_repository_supabase.dart';
import '../domain/tipo_patrimonio.dart';

/// Tipos/setores ativos usados nos filtros e no formulário de cadastro —
/// nunca hardcoded, sempre lidos do banco.
final tiposAtivosProvider = FutureProvider<List<TipoPatrimonio>>((ref) {
  return ref.watch(tipoPatrimonioRepositoryProvider).listarAtivos();
});

final setoresAtivosParaPatrimonioProvider = FutureProvider<List<Setor>>((
  ref,
) {
  return ref.watch(setorRepositoryProvider).listarAtivos();
});
