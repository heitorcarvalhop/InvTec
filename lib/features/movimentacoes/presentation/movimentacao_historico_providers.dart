import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/movimentacao_repository_supabase.dart';
import '../domain/movimentacao_historico_item.dart';

/// Histórico (timeline) de um patrimônio por id. `family` + `autoDispose`:
/// cada tela de detalhe busca só o seu id, e o cache é descartado ao sair
/// da tela — mesmo padrão de [patrimonioDetalheProvider].
final patrimonioHistoricoProvider = FutureProvider.autoDispose
    .family<List<MovimentacaoHistoricoItem>, String>((ref, patrimonioId) async {
      final repository = ref.watch(movimentacaoRepositoryProvider);
      return repository.listarHistoricoPorPatrimonio(patrimonioId);
    });
