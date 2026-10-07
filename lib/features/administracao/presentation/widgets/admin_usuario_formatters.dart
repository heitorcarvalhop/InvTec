/// Formatação de CPF/data compartilhada pelas telas de Administração >
/// Usuários — sem `intl` (não é dependência do projeto): formatação manual
/// simples, suficiente para `dd/MM/yyyy` e a máscara de CPF.
library;

/// CPF mascarado para a LISTAGEM (visão de várias linhas, seção 26):
/// mostra só os 5 últimos dígitos — `***.***.123-45`. `null`/CPF ausente
/// (conta legada que nunca informou CPF) devolve `null` para o chamador
/// decidir o texto ("Não informado").
String? formatarCpfMascarado(String? cpf) {
  if (cpf == null || cpf.isEmpty) return null;
  final digitos = cpf.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length != 11) return cpf; // defensivo — nunca deveria ocorrer
  return '***.***.${digitos.substring(6, 9)}-${digitos.substring(9, 11)}';
}

/// CPF completo (com pontuação), usado só na tela de DETALHE — visão ADMIN,
/// nunca mascarado ali (seção 28).
String formatarCpfCompleto(String cpf) {
  final digitos = cpf.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.length != 11) return cpf;
  return '${digitos.substring(0, 3)}.${digitos.substring(3, 6)}.${digitos.substring(6, 9)}-${digitos.substring(9, 11)}';
}

/// `dd/MM/yyyy` em horário local — suficiente para "Data do cadastro"/
/// "Aprovado em" (nenhuma das duas precisa do horário, seção 26/28).
String formatarDataCurta(DateTime data) {
  final local = data.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(local.day)}/${dois(local.month)}/${local.year}';
}
