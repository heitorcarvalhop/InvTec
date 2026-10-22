import 'patrimonio_detalhe.dart';

/// Uma página de resultados de [PatrimonioRepository.listar] — itens já
/// paginados no servidor + a contagem total (para calcular quantas páginas
/// existem), obtidos em uma única consulta.
///
/// [correspondenciasPorNumeroSerie] só é preenchido no caso específico do
/// modo [PatrimonioSearchField.tudo] com consulta só de
/// dígitos, quando NENHUM `numero_patrimonio` exato foi encontrado mas
/// existe ao menos um `numero_serie` exato — nunca misturado com [itens]
/// (que continua vazio nesse caso): a UI precisa deixar explícito que a
/// consulta não é o número de patrimônio, só coincide com um número de
/// série.
///
/// [correspondenciasPorTombamentoAnterior] é preenchido quando a pesquisa é
/// por tombamento (modo [PatrimonioSearchField.tudo] numérico ou
/// [PatrimonioSearchField.patrimonio]) e existe histórico validado — ver
/// [PatrimonioRepository.buscarPorTombamentoAnterior]. Sempre uma lista
/// SEPARADA de [itens] (nunca misturada, para nunca apresentar um
/// patrimônio encontrado pelo tombamento ANTERIOR como se tivesse sido pelo
/// ATUAL) e nunca com um patrimônio já presente em [itens] (sem repetição
/// quando um bem corresponde por critérios diferentes). Fica sempre vazia
/// enquanto a migration do histórico de tombamentos não estiver aplicada —
/// nunca lança erro por isso.
class PatrimoniosResultado {
  const PatrimoniosResultado({
    required this.itens,
    required this.total,
    this.correspondenciasPorNumeroSerie = const [],
    this.correspondenciasPorTombamentoAnterior = const [],
  });

  const PatrimoniosResultado.vazio()
    : itens = const [],
      total = 0,
      correspondenciasPorNumeroSerie = const [],
      correspondenciasPorTombamentoAnterior = const [];

  final List<PatrimonioDetalhe> itens;
  final int total;
  final List<PatrimonioDetalhe> correspondenciasPorNumeroSerie;
  final List<PatrimonioEncontradoPorAnterior> correspondenciasPorTombamentoAnterior;
}
