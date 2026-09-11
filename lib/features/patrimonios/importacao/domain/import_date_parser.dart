/// Interpreta uma data de planilha textual — só os formatos comuns em
/// planilhas brasileiras. Retorna `null` (nunca lança) quando o texto é
/// ambíguo ou desconhecido: a linha chamadora decide marcar para revisão
/// em vez de adivinhar (seção 38: "não converter silenciosamente um valor
/// ambíguo").
DateTime? interpretarDataTexto(String texto) {
  final valor = texto.trim();
  if (valor.isEmpty) return null;

  // dd/mm/yyyy ou dd-mm-yyyy (com ano de 2 ou 4 dígitos)
  final comBarraOuTraco = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2}|\d{4})$');
  final matchBarra = comBarraOuTraco.firstMatch(valor);
  if (matchBarra != null) {
    final dia = int.parse(matchBarra.group(1)!);
    final mes = int.parse(matchBarra.group(2)!);
    var ano = int.parse(matchBarra.group(3)!);
    if (ano < 100) ano += 2000;
    return _dataValida(ano, mes, dia);
  }

  // yyyy-mm-dd (ISO)
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
  final matchIso = iso.firstMatch(valor);
  if (matchIso != null) {
    final ano = int.parse(matchIso.group(1)!);
    final mes = int.parse(matchIso.group(2)!);
    final dia = int.parse(matchIso.group(3)!);
    return _dataValida(ano, mes, dia);
  }

  return null;
}

DateTime? _dataValida(int ano, int mes, int dia) {
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  final data = DateTime(ano, mes, dia);
  // DateTime "normaliza" datas inválidas (ex.: 31/02) rolando para o mês
  // seguinte — se isso aconteceu, o valor original não era uma data real.
  if (data.year != ano || data.month != mes || data.day != dia) return null;
  return data;
}
