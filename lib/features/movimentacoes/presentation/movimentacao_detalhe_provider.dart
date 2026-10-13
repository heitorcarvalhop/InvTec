import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/movimentacao_repository_supabase.dart';
import '../domain/movimentacao_listagem_item.dart';

/// Busca uma movimentação específica por id — usada só pelo deep-link
/// `/movimentacoes/:id` (ex.: "Ver movimentação completa" do Dashboard).
/// `autoDispose`/`family`: a consulta só dispara quando a rota com id é
/// efetivamente visitada, nunca no carregamento normal da listagem.
final movimentacaoPorIdProvider = FutureProvider.autoDispose
    .family<MovimentacaoListagemItem?, String>((ref, id) async {
      final repository = ref.watch(movimentacaoRepositoryProvider);
      return repository.buscarPorId(id);
    });
