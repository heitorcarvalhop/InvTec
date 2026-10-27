import '../../../core/errors/app_exception.dart';
import 'patrimonio_detalhe.dart';
import 'patrimonio_repository.dart';
import 'tombamento_normalizacao.dart';

/// Como [resolverCodigoEscaneado] classificou um código lido pela câmera
/// (leitor de patrimônio Android). Seis categorias, deliberadamente
/// distintas e nunca combinadas (pedido de auditoria de confiabilidade):
/// encontrado/encontrado-por-anterior/ambíguo têm sua própria resposta;
/// "não encontrado" é SEMPRE o resultado de uma busca que TERMINOU sem
/// corresponder a nada (nunca de uma falha); falha de consulta e acesso
/// insuficiente nunca oferecem cadastro, porque nenhuma delas prova que o
/// patrimônio não existe.
enum ScannerResultadoTipo {
  /// Um único patrimônio encontrado pelo tombamento ATUAL.
  encontradoAtual,

  /// Um único patrimônio encontrado pelo tombamento ANTERIOR (ver
  /// [PatrimonioRepository.buscarPorTombamentoAnterior]).
  encontradoAnterior,

  /// Mais de um patrimônio corresponde EXATAMENTE ao código lido — anomalia
  /// de dados (o cadastro/importação não deveria permitir duplicidade),
  /// nunca escolhida automaticamente: quem chama decide como apresentar.
  ambiguo,

  /// A busca TERMINOU (atual e anterior) sem nenhuma correspondência,
  /// entre o que esta sessão consegue acessar — candidato a "Cadastrar
  /// patrimônio". Nunca prova que o patrimônio não existe de verdade (RLS
  /// pode estar ocultando um registro que outra sessão veria).
  naoEncontrado,

  /// [codigoLido] é vazio ou só zeros depois de normalizado — nunca gera
  /// consulta ao Supabase.
  codigoInvalido,

  /// A consulta foi RECUSADA por falta de permissão
  /// ([AcessoInsuficienteException]) — nunca se sabe se o patrimônio
  /// existe. Distinto de [naoEncontrado] (que é uma resposta completa, só
  /// sem correspondência) e de [falhaConsulta] (que pode ser só uma falha
  /// passageira de rede).
  acessoInsuficiente,

  /// A consulta falhou por outro motivo (rede, timeout, erro do servidor)
  /// — nunca se sabe se o patrimônio existe. "Tentar novamente" é a única
  /// ação sensata; nunca oferecer cadastro aqui.
  falhaConsulta,
}

/// Resultado de [resolverCodigoEscaneado] — [codigoLido] preserva o texto
/// BRUTO exatamente como veio da câmera/entrada manual (zeros à esquerda
/// intactos, nunca a chave normalizada), para exibição fiel e para
/// pré-preencher o formulário de cadastro quando [tipo] for
/// [ScannerResultadoTipo.naoEncontrado].
class ScannerResultado {
  const ScannerResultado._({
    required this.tipo,
    required this.codigoLido,
    this.encontrados = const [],
  });

  factory ScannerResultado.encontradoAtual(
    String codigoLido,
    PatrimonioDetalhe patrimonio,
  ) => ScannerResultado._(
    tipo: ScannerResultadoTipo.encontradoAtual,
    codigoLido: codigoLido,
    encontrados: [patrimonio],
  );

  factory ScannerResultado.encontradoAnterior(
    String codigoLido,
    PatrimonioDetalhe patrimonio,
  ) => ScannerResultado._(
    tipo: ScannerResultadoTipo.encontradoAnterior,
    codigoLido: codigoLido,
    encontrados: [patrimonio],
  );

  factory ScannerResultado.ambiguo(
    String codigoLido,
    List<PatrimonioDetalhe> encontrados,
  ) => ScannerResultado._(
    tipo: ScannerResultadoTipo.ambiguo,
    codigoLido: codigoLido,
    encontrados: encontrados,
  );

  factory ScannerResultado.naoEncontrado(String codigoLido) =>
      ScannerResultado._(
        tipo: ScannerResultadoTipo.naoEncontrado,
        codigoLido: codigoLido,
      );

  factory ScannerResultado.codigoInvalido(String codigoLido) =>
      ScannerResultado._(
        tipo: ScannerResultadoTipo.codigoInvalido,
        codigoLido: codigoLido,
      );

  factory ScannerResultado.acessoInsuficiente(String codigoLido) =>
      ScannerResultado._(
        tipo: ScannerResultadoTipo.acessoInsuficiente,
        codigoLido: codigoLido,
      );

  factory ScannerResultado.falhaConsulta(String codigoLido) =>
      ScannerResultado._(
        tipo: ScannerResultadoTipo.falhaConsulta,
        codigoLido: codigoLido,
      );

  final ScannerResultadoTipo tipo;
  final String codigoLido;

  /// Vazia exceto em [ScannerResultadoTipo.encontradoAtual] (1 item),
  /// [ScannerResultadoTipo.encontradoAnterior] (1 item) e
  /// [ScannerResultadoTipo.ambiguo] (2+ itens).
  final List<PatrimonioDetalhe> encontrados;
}

/// Resolve um código lido pelo scanner de câmera (ou digitado manualmente
/// como alternativa) para um patrimônio existente — pesquisa primeiro pelo
/// tombamento ATUAL ([PatrimonioRepository.buscarPorTombamentoAtualExato]),
/// depois pelo ANTERIOR ([PatrimonioRepository.buscarPorTombamentoAnterior]),
/// exatamente como pedido.
///
/// IMPORTANTE (auditoria de confiabilidade): os dois métodos usados aqui
/// são buscas EXATAS, nunca por substring, e nenhum dos dois é paginado —
/// ao contrário de [PatrimonioRepository.listar] (ILIKE `%...%`, pensado
/// para o humano revisar uma LISTA de candidatos, com paginação), que foi
/// usado aqui numa versão anterior e podia produzir um falso "não
/// encontrado" quando a correspondência verdadeira existia mas caía fora
/// da página de candidatos retornada. Nenhum dos dois métodos atuais tem
/// esse risco: cada um devolve TODAS as linhas que realmente batem com a
/// chave normalizada.
///
/// Nunca lança: qualquer falha nas duas consultas é CLASSIFICADA (nunca
/// propagada) como [ScannerResultadoTipo.acessoInsuficiente] ou
/// [ScannerResultadoTipo.falhaConsulta] — nenhuma das duas é tratada como
/// [ScannerResultadoTipo.naoEncontrado]: quem chama NUNCA pode oferecer
/// "Cadastrar patrimônio" como consequência de uma falha (regra do
/// pedido), e isso só é garantido estruturalmente porque essas duas saídas
/// são distintas de [ScannerResultadoTipo.naoEncontrado] no mesmo enum.
///
/// Nunca cadastra, atualiza nem decide nada por conta própria — só
/// classifica. Quem chama decide a navegação/UI para cada
/// [ScannerResultadoTipo].
Future<ScannerResultado> resolverCodigoEscaneado(
  PatrimonioRepository repositorio,
  String codigoLido,
) async {
  final normalizado = normalizarTombamentoParaComparacao(codigoLido);
  if (normalizado.chaveComparacao == null) {
    return ScannerResultado.codigoInvalido(codigoLido);
  }

  final List<PatrimonioDetalhe> encontradosAtual;
  try {
    encontradosAtual = await repositorio.buscarPorTombamentoAtualExato(
      codigoLido,
    );
  } on AcessoInsuficienteException {
    return ScannerResultado.acessoInsuficiente(codigoLido);
  } catch (_) {
    return ScannerResultado.falhaConsulta(codigoLido);
  }

  if (encontradosAtual.length == 1) {
    return ScannerResultado.encontradoAtual(codigoLido, encontradosAtual.single);
  }
  if (encontradosAtual.length > 1) {
    return ScannerResultado.ambiguo(codigoLido, encontradosAtual);
  }

  final List<PatrimonioEncontradoPorAnterior> anteriores;
  try {
    anteriores = await repositorio.buscarPorTombamentoAnterior(codigoLido);
  } on AcessoInsuficienteException {
    return ScannerResultado.acessoInsuficiente(codigoLido);
  } catch (_) {
    return ScannerResultado.falhaConsulta(codigoLido);
  }

  if (anteriores.length == 1) {
    return ScannerResultado.encontradoAnterior(
      codigoLido,
      anteriores.single.patrimonio,
    );
  }
  if (anteriores.length > 1) {
    return ScannerResultado.ambiguo(
      codigoLido,
      anteriores.map((e) => e.patrimonio).toList(),
    );
  }

  return ScannerResultado.naoEncontrado(codigoLido);
}
