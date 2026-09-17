import 'patrimonio_detalhe.dart';

/// Uma página de resultados de [PatrimonioRepository.listar] — itens já
/// paginados no servidor + a contagem total (para calcular quantas páginas
/// existem), obtidos em uma única consulta.
///
/// [correspondenciasPorNumeroSerie] (PROMPT 9.1.1) só é preenchido no caso
/// específico do modo [PatrimonioSearchField.tudo] com consulta só de
/// dígitos, quando NENHUM `numero_patrimonio` exato foi encontrado mas
/// existe ao menos um `numero_serie` exato — nunca misturado com [itens]
/// (que continua vazio nesse caso): a UI precisa deixar explícito que a
/// consulta não é o número de patrimônio, só coincide com um número de
/// série.
class PatrimoniosResultado {
  const PatrimoniosResultado({
    required this.itens,
    required this.total,
    this.correspondenciasPorNumeroSerie = const [],
  });

  const PatrimoniosResultado.vazio()
    : itens = const [],
      total = 0,
      correspondenciasPorNumeroSerie = const [];

  final List<PatrimonioDetalhe> itens;
  final int total;
  final List<PatrimonioDetalhe> correspondenciasPorNumeroSerie;
}
