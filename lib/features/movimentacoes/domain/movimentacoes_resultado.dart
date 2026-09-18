import 'movimentacao_listagem_item.dart';

/// Uma página de resultados de [MovimentacaoRepository.listar] — itens já
/// paginados no servidor + a contagem total do conjunto filtrado (mesmo
/// padrão de `PatrimoniosResultado`, PROMPT 9.2).
class MovimentacoesResultado {
  const MovimentacoesResultado({required this.itens, required this.total});

  const MovimentacoesResultado.vazio() : itens = const [], total = 0;

  final List<MovimentacaoListagemItem> itens;
  final int total;
}
