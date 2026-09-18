import '../domain/movimentacao.dart';

/// Sentinela para distinguir "não mudar este filtro" de "limpar para null"
/// em [MovimentacoesFiltro.copyWith] — mesmo padrão de `PatrimoniosFiltro`
/// (PROMPT 9.2).
const _unset = Object();

/// Tamanhos de página permitidos pela listagem (PROMPT 10.1, seção
/// "Paginação") — mesmos valores de Patrimônios.
const movimentacoesTamanhosPaginaPermitidos = [25, 50, 100];

const movimentacoesTamanhoPaginaPadrao = 25;

/// Mesma regra de `intervaloDeDataValido` de Patrimônios: `null` em
/// qualquer lado (intervalo aberto) é sempre válido.
bool intervaloPeriodoValido(DateTime? de, DateTime? ate) {
  if (de == null || ate == null) return true;
  return !de.isAfter(ate);
}

/// Estado combinado de busca + filtros + página atual da listagem geral de
/// movimentações (PROMPT 10.1).
class MovimentacoesFiltro {
  const MovimentacoesFiltro({
    this.busca = '',
    this.tipo,
    this.setorId,
    this.periodoDe,
    this.periodoAte,
    this.pagina = 0,
    this.tamanhoPagina = movimentacoesTamanhoPaginaPadrao,
  });

  /// Busca livre: patrimônio (número), responsável (origem OU destino),
  /// número de documento, número de chamado — combinados por OR.
  final String busca;

  final MovimentacaoTipo? tipo;

  /// Setor de origem OU destino (PROMPT 10.1: "setor" sozinho, sem
  /// distinguir lado — uma movimentação "envolve" um setor dos dois jeitos).
  final String? setorId;

  /// Intervalo de `data_movimentacao`, inclusivo nos dois limites.
  final DateTime? periodoDe;
  final DateTime? periodoAte;

  /// 0-based.
  final int pagina;

  final int tamanhoPagina;

  bool get temFiltroAtivo =>
      busca.isNotEmpty || tipo != null || setorId != null || periodoDe != null || periodoAte != null;

  MovimentacoesFiltro copyWith({
    String? busca,
    Object? tipo = _unset,
    Object? setorId = _unset,
    Object? periodoDe = _unset,
    Object? periodoAte = _unset,
    int? pagina,
    int? tamanhoPagina,
  }) {
    return MovimentacoesFiltro(
      busca: busca ?? this.busca,
      tipo: identical(tipo, _unset) ? this.tipo : tipo as MovimentacaoTipo?,
      setorId: identical(setorId, _unset) ? this.setorId : setorId as String?,
      periodoDe: identical(periodoDe, _unset) ? this.periodoDe : periodoDe as DateTime?,
      periodoAte: identical(periodoAte, _unset) ? this.periodoAte : periodoAte as DateTime?,
      pagina: pagina ?? this.pagina,
      tamanhoPagina: tamanhoPagina ?? this.tamanhoPagina,
    );
  }
}
