import '../domain/patrimonio.dart';

/// Sentinela para distinguir "não mudar este filtro" de "limpar para null"
/// em [PatrimoniosFiltro.copyWith] — `??` sozinho não consegue expressar
/// isso para campos anuláveis.
const _unset = Object();

/// Estado combinado de busca + filtros + página atual da listagem de
/// patrimônios.
class PatrimoniosFiltro {
  const PatrimoniosFiltro({
    this.busca = '',
    this.tipoId,
    this.status,
    this.setorId,
    this.pagina = 0,
  });

  final String busca;
  final String? tipoId;
  final PatrimonioStatus? status;
  final String? setorId;

  /// 0-based.
  final int pagina;

  bool get temFiltroAtivo =>
      busca.isNotEmpty || tipoId != null || status != null || setorId != null;

  PatrimoniosFiltro copyWith({
    String? busca,
    Object? tipoId = _unset,
    Object? status = _unset,
    Object? setorId = _unset,
    int? pagina,
  }) {
    return PatrimoniosFiltro(
      busca: busca ?? this.busca,
      tipoId: identical(tipoId, _unset) ? this.tipoId : tipoId as String?,
      status: identical(status, _unset)
          ? this.status
          : status as PatrimonioStatus?,
      setorId: identical(setorId, _unset) ? this.setorId : setorId as String?,
      pagina: pagina ?? this.pagina,
    );
  }
}
