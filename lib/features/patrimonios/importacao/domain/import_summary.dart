import 'import_row.dart';

/// Contagens por categoria (seção 21) — exibidas como cards/chips no passo
/// de resumo e usadas na confirmação final (seção 24).
class ImportSummary {
  const ImportSummary({
    required this.total,
    required this.prontos,
    required this.avisos,
    required this.erros,
    required this.duplicados,
    required this.existentes,
    required this.atualizar,
    required this.ignorados,
  });

  factory ImportSummary.fromRows(List<ImportRow> linhas) {
    var prontos = 0;
    var avisos = 0;
    var erros = 0;
    var duplicados = 0;
    var existentes = 0;
    var atualizar = 0;
    var ignorados = 0;

    for (final linha in linhas) {
      if (linha.duplicadoNoArquivo && linha.status == ImportRowStatus.erro) {
        duplicados++;
        continue;
      }
      switch (linha.status) {
        case ImportRowStatus.pronto:
          prontos++;
        case ImportRowStatus.aviso:
          avisos++;
        case ImportRowStatus.erro:
          erros++;
        case ImportRowStatus.ignorado:
          ignorados++;
        case ImportRowStatus.existente:
          existentes++;
        case ImportRowStatus.atualizar:
          atualizar++;
      }
    }

    return ImportSummary(
      total: linhas.length,
      prontos: prontos,
      avisos: avisos,
      erros: erros,
      duplicados: duplicados,
      existentes: existentes,
      atualizar: atualizar,
      ignorados: ignorados,
    );
  }

  final int total;
  final int prontos;
  final int avisos;
  final int erros;
  final int duplicados;
  final int existentes;
  final int atualizar;
  final int ignorados;

  /// Novos patrimônios que serão criados via `cadastrar_patrimonio`.
  int get novos => prontos + avisos;

  /// Total de linhas que serão efetivamente enviadas ao Supabase.
  int get totalParaEnviar => novos + atualizar;
}
