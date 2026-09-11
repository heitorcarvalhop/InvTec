import 'patrimonio_detalhe.dart';

/// Uma página de resultados de [PatrimonioRepository.listar] — itens já
/// paginados no servidor + a contagem total (para calcular quantas páginas
/// existem), obtidos em uma única consulta.
class PatrimoniosResultado {
  const PatrimoniosResultado({required this.itens, required this.total});

  const PatrimoniosResultado.vazio() : itens = const [], total = 0;

  final List<PatrimonioDetalhe> itens;
  final int total;
}
