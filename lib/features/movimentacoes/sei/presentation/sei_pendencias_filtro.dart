import '../../domain/movimentacao.dart';
import '../domain/sei_item_pendencia_status.dart';

/// Filtros da lista de Documentos SEI pendentes (PROMPT 11.3, seção 4) —
/// mesmo padrão de `MovimentacoesFiltro`: objeto imutável, só usado pela
/// camada de apresentação (o repositório recebe parâmetros nomeados, não
/// este objeto).
class SeiPendenciasFiltro {
  const SeiPendenciasFiltro({
    this.tipo,
    this.situacaoContemStatus,
    this.numeroDocumentoSei,
    this.numeroProcesso,
    this.numeroPatrimonio,
    this.pagina = 0,
    this.tamanhoPagina = 25,
  });

  final MovimentacaoTipo? tipo;
  final SeiItemPendenciaStatus? situacaoContemStatus;
  final String? numeroDocumentoSei;
  final String? numeroProcesso;
  final String? numeroPatrimonio;
  final int pagina;
  final int tamanhoPagina;

  bool get temFiltroAtivo =>
      tipo != null ||
      situacaoContemStatus != null ||
      (numeroDocumentoSei != null && numeroDocumentoSei!.isNotEmpty) ||
      (numeroProcesso != null && numeroProcesso!.isNotEmpty) ||
      (numeroPatrimonio != null && numeroPatrimonio!.isNotEmpty);

  SeiPendenciasFiltro copyWith({
    MovimentacaoTipo? Function()? tipo,
    SeiItemPendenciaStatus? Function()? situacaoContemStatus,
    String? Function()? numeroDocumentoSei,
    String? Function()? numeroProcesso,
    String? Function()? numeroPatrimonio,
    int? pagina,
    int? tamanhoPagina,
  }) {
    return SeiPendenciasFiltro(
      tipo: tipo != null ? tipo() : this.tipo,
      situacaoContemStatus: situacaoContemStatus != null ? situacaoContemStatus() : this.situacaoContemStatus,
      numeroDocumentoSei: numeroDocumentoSei != null ? numeroDocumentoSei() : this.numeroDocumentoSei,
      numeroProcesso: numeroProcesso != null ? numeroProcesso() : this.numeroProcesso,
      numeroPatrimonio: numeroPatrimonio != null ? numeroPatrimonio() : this.numeroPatrimonio,
      pagina: pagina ?? this.pagina,
      tamanhoPagina: tamanhoPagina ?? this.tamanhoPagina,
    );
  }
}

const seiPendenciasTamanhosPaginaPermitidos = [10, 25, 50];
