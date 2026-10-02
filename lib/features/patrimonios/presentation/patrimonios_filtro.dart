import '../../../core/domain/ordenacao_direcao.dart';
import '../domain/patrimonio.dart';
import '../domain/patrimonio_ordenacao.dart';
import '../domain/patrimonio_search_field.dart';

/// Sentinela para distinguir "não mudar este filtro" de "limpar para null"
/// em [PatrimoniosFiltro.copyWith] — `??` sozinho não consegue expressar
/// isso para campos anuláveis.
const _unset = Object();

/// Tamanhos de página permitidos pela listagem.
const patrimoniosTamanhosPaginaPermitidos = [25, 50, 100];

const patrimoniosTamanhoPaginaPadrao = 25;

/// Um intervalo De/Até só é válido quando a data inicial não é posterior à
/// final — `null` em qualquer um dos lados (intervalo aberto) é sempre
/// válido. Função pura para ser testável sem precisar simular a interação
/// com o seletor de data.
bool intervaloDeDataValido(DateTime? de, DateTime? ate) {
  if (de == null || ate == null) return true;
  return !de.isAfter(ate);
}

/// Estado combinado de busca + filtros (principais e avançados) + página
/// atual da listagem de patrimônios.
class PatrimoniosFiltro {
  const PatrimoniosFiltro({
    this.busca = '',
    this.campoBusca = PatrimonioSearchField.tudo,
    this.tipoId,
    this.status,
    this.setorId,
    this.localizacaoId,
    this.semLocalizacao = false,
    this.marca = '',
    this.modelo = '',
    this.responsavel = '',
    this.dataCadastroDe,
    this.dataCadastroAte,
    this.dataAquisicaoDe,
    this.dataAquisicaoAte,
    this.ordenarPor,
    this.ordenacaoDirecao = OrdenacaoDirecao.asc,
    this.pagina = 0,
    this.tamanhoPagina = patrimoniosTamanhoPaginaPadrao,
  });

  final String busca;
  final PatrimonioSearchField campoBusca;
  final String? tipoId;
  final PatrimonioStatus? status;
  final String? setorId;

  /// `localizacao_atual_id` exato — nunca comparação textual. `null` +
  /// [semLocalizacao] `false` significa "todas as localizações".
  final String? localizacaoId;

  /// Filtro explícito "Sem localização" (`localizacao_atual_id IS NULL`) —
  /// mutuamente exclusivo com [localizacaoId] (a UI garante isso: ao marcar
  /// um, o outro é limpo).
  final bool semLocalizacao;

  /// Filtros avançados textuais — independentes do campo/termo da busca
  /// principal, combinados por AND. Vazio = filtro não aplicado.
  final String marca;
  final String modelo;
  final String responsavel;

  /// Intervalo de `data_cadastro` (timestamptz) — ambos os limites são
  /// inclusivos para o usuário.
  final DateTime? dataCadastroDe;
  final DateTime? dataCadastroAte;

  /// Intervalo de `data_aquisicao` (date) — também inclusivo nos dois
  /// limites.
  final DateTime? dataAquisicaoDe;
  final DateTime? dataAquisicaoAte;

  /// `null` = ordenação padrão (cadastro mais recente primeiro). Qualquer
  /// outro valor substitui totalmente essa ordenação, sempre resolvida no
  /// servidor — ver [PatrimonioRepository.listar].
  final PatrimonioOrdenacaoCampo? ordenarPor;

  /// Só importa quando [ordenarPor] não é `null`.
  final OrdenacaoDirecao ordenacaoDirecao;

  /// 0-based.
  final int pagina;

  final int tamanhoPagina;

  bool get temFiltroAtivo =>
      busca.isNotEmpty ||
      campoBusca != PatrimonioSearchField.tudo ||
      tipoId != null ||
      status != null ||
      setorId != null ||
      localizacaoId != null ||
      semLocalizacao ||
      temFiltroAvancadoAtivo;

  bool get temFiltroAvancadoAtivo =>
      marca.isNotEmpty ||
      modelo.isNotEmpty ||
      responsavel.isNotEmpty ||
      dataCadastroDe != null ||
      dataCadastroAte != null ||
      dataAquisicaoDe != null ||
      dataAquisicaoAte != null;

  /// Quantos filtros avançados estão ativos — usado no rótulo "Filtros
  /// avançados (N)". Cada intervalo de data conta como UM filtro (De/Até
  /// formam um único critério), nunca dois.
  int get quantidadeFiltrosAvancados {
    var quantidade = 0;
    if (marca.isNotEmpty) quantidade++;
    if (modelo.isNotEmpty) quantidade++;
    if (responsavel.isNotEmpty) quantidade++;
    if (dataCadastroDe != null || dataCadastroAte != null) quantidade++;
    if (dataAquisicaoDe != null || dataAquisicaoAte != null) quantidade++;
    return quantidade;
  }

  PatrimoniosFiltro copyWith({
    String? busca,
    PatrimonioSearchField? campoBusca,
    Object? tipoId = _unset,
    Object? status = _unset,
    Object? setorId = _unset,
    Object? localizacaoId = _unset,
    bool? semLocalizacao,
    String? marca,
    String? modelo,
    String? responsavel,
    Object? dataCadastroDe = _unset,
    Object? dataCadastroAte = _unset,
    Object? dataAquisicaoDe = _unset,
    Object? dataAquisicaoAte = _unset,
    Object? ordenarPor = _unset,
    OrdenacaoDirecao? ordenacaoDirecao,
    int? pagina,
    int? tamanhoPagina,
  }) {
    return PatrimoniosFiltro(
      busca: busca ?? this.busca,
      campoBusca: campoBusca ?? this.campoBusca,
      tipoId: identical(tipoId, _unset) ? this.tipoId : tipoId as String?,
      status: identical(status, _unset)
          ? this.status
          : status as PatrimonioStatus?,
      setorId: identical(setorId, _unset) ? this.setorId : setorId as String?,
      localizacaoId: identical(localizacaoId, _unset)
          ? this.localizacaoId
          : localizacaoId as String?,
      semLocalizacao: semLocalizacao ?? this.semLocalizacao,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      responsavel: responsavel ?? this.responsavel,
      dataCadastroDe: identical(dataCadastroDe, _unset)
          ? this.dataCadastroDe
          : dataCadastroDe as DateTime?,
      dataCadastroAte: identical(dataCadastroAte, _unset)
          ? this.dataCadastroAte
          : dataCadastroAte as DateTime?,
      dataAquisicaoDe: identical(dataAquisicaoDe, _unset)
          ? this.dataAquisicaoDe
          : dataAquisicaoDe as DateTime?,
      dataAquisicaoAte: identical(dataAquisicaoAte, _unset)
          ? this.dataAquisicaoAte
          : dataAquisicaoAte as DateTime?,
      ordenarPor: identical(ordenarPor, _unset) ? this.ordenarPor : ordenarPor as PatrimonioOrdenacaoCampo?,
      ordenacaoDirecao: ordenacaoDirecao ?? this.ordenacaoDirecao,
      pagina: pagina ?? this.pagina,
      tamanhoPagina: tamanhoPagina ?? this.tamanhoPagina,
    );
  }
}
