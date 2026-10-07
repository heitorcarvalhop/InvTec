/// Mascara um CPF já normalizado (ou não) para exibição, nunca para edição:
/// só os 5 últimos dígitos ficam visíveis (ex. `***.***.123-45`). CPF legado
/// nulo (contas antigas que nunca informaram CPF) devolve "Não informado" em
/// vez de quebrar o parsing.
String maskCpfParaExibicao(String? cpf) {
  final digitos = (cpf ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length != 11) return 'Não informado';
  return '***.***.${digitos.substring(6, 9)}-${digitos.substring(9, 11)}';
}
