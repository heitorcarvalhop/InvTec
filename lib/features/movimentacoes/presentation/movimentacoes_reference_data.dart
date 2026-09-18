import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../setores/data/setor_repository_supabase.dart';
import '../../setores/domain/setor.dart';

/// Setores para o filtro da listagem HISTÓRICA de movimentações (PROMPT
/// 10.1.1). Diferente do cadastro de patrimônio — que só pode apontar para
/// setores ativos e por isso usa `setoresAtivosParaPatrimonioProvider` — o
/// histórico pode conter movimentações de/para um setor já desativado, e
/// esse registro continua válido. Filtrar só por `listarAtivos()` esconderia
/// essas movimentações do filtro sem nenhum jeito de encontrá-las de volta.
///
/// Reaproveita `setorRepositoryProvider` e `SetorRepository.listar()` —
/// mesma consulta já usada pela tela de gestão de Setores (ativos primeiro,
/// depois inativos, por nome). Nenhum provider/consulta/regra de Setores é
/// criado ou alterado aqui.
final setoresParaFiltroMovimentacoesProvider = FutureProvider<List<Setor>>((ref) {
  // Setores são uma tabela de referência (dezenas, não milhares) — um limite
  // alto aqui é só uma salvaguarda, não um carregamento pesado.
  return ref.watch(setorRepositoryProvider).listar(limit: 500);
});
