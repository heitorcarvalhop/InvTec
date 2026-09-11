/// Valores padrão da importação (seção 10): usados quando a coluna
/// correspondente não existe na planilha ou a célula está vazia na linha —
/// o valor da linha, quando presente, sempre tem prioridade (seção 11).
/// Nunca hardcoded: [origemPadraoId]/[destinoPadraoId] só podem apontar
/// para setores realmente cadastrados (ver ImportDefaultsStep).
///
/// [dataPadrao] é deliberadamente nulo até o usuário configurar um valor —
/// se uma linha tiver data de entrada não reconhecida e não houver
/// [dataPadrao], a linha é classificada como ERRO em vez de usar `now()`
/// silenciosamente (ver ImportAnalyzer.classificar).
class ImportDefaults {
  const ImportDefaults({
    this.origemPadraoId,
    this.destinoPadraoId,
    this.responsavelDestinoPadrao,
    this.motivoPadrao,
    this.dataPadrao,
  });

  final String? origemPadraoId;
  final String? destinoPadraoId;
  final String? responsavelDestinoPadrao;
  final String? motivoPadrao;
  final DateTime? dataPadrao;

  ImportDefaults copyWith({
    String? Function()? origemPadraoId,
    String? Function()? destinoPadraoId,
    String? Function()? responsavelDestinoPadrao,
    String? Function()? motivoPadrao,
    DateTime? Function()? dataPadrao,
  }) {
    return ImportDefaults(
      origemPadraoId: origemPadraoId != null ? origemPadraoId() : this.origemPadraoId,
      destinoPadraoId: destinoPadraoId != null ? destinoPadraoId() : this.destinoPadraoId,
      responsavelDestinoPadrao: responsavelDestinoPadrao != null
          ? responsavelDestinoPadrao()
          : this.responsavelDestinoPadrao,
      motivoPadrao: motivoPadrao != null ? motivoPadrao() : this.motivoPadrao,
      dataPadrao: dataPadrao != null ? dataPadrao() : this.dataPadrao,
    );
  }
}
