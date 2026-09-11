import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/patrimonio_repository_supabase.dart';
import '../domain/patrimonio_detalhe.dart';

/// Detalhe de um patrimônio por id, com tipo/setor/criador já resolvidos.
/// `family` + `autoDispose`: cada tela de detalhe busca só o seu id, e o
/// cache é descartado ao sair da tela. Invalidar esta entrada específica
/// (`ref.invalidate(patrimonioDetalheProvider(id))`) após uma edição bem
/// sucedida atualiza a tela sem precisar recarregar o app.
final patrimonioDetalheProvider = FutureProvider.autoDispose
    .family<PatrimonioDetalhe?, String>((ref, id) async {
      final repository = ref.watch(patrimonioRepositoryProvider);
      return repository.buscarDetalhePorId(id);
    });
