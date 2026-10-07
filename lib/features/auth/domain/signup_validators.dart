/// Validators PUROS (sem widget, sem BuildContext) do formulário de
/// cadastro — usados tanto pelos `FormField.validator` da futura
/// `CadastroPage` (design-ui) quanto por [SignUpController] antes de
/// chamar o repositório. Mantidos fora de qualquer widget para serem
/// testáveis diretamente.
///
/// Divisão de responsabilidade (documentada aqui porque a UI que ainda vai
/// ser escrita precisa saber o que já está pronto): estas funções cobrem
/// TODA validação PURA/testável sem widget — formato de nome/CPF/e-mail,
/// força de senha, confirmação de senha. A UI só precisa plugar cada
/// função num `TextFormField.validator` correspondente; não deve duplicar
/// nenhuma regex. [SignUpController.signUp] roda estas mesmas funções de
/// novo antes de chamar o repositório (defesa em profundidade — nunca
/// confia que a UI sempre validou) e trata separadamente os erros que só o
/// SERVIDOR pode detectar (CPF/e-mail já em uso, falha de rede, erro
/// genérico do GoTrue) — ver `lib/core/errors/app_error_messages.dart`.
library;

/// Um dos 5 requisitos de senha avaliados por [avaliarRequisitosSenha],
/// para a UI desenhar o checklist visual (✓/○) sem duplicar a lógica.
enum RequisitoSenha {
  comprimentoMinimo('Mínimo de 12 caracteres'),
  letraMaiuscula('Uma letra maiúscula'),
  letraMinuscula('Uma letra minúscula'),
  numero('Um número'),
  caractereEspecial('Um caractere especial');

  const RequisitoSenha(this.descricao);
  final String descricao;
}

/// `nome` obrigatório, sem espaços nas pontas, não vazio.
String? validarNome(String? nome) {
  final texto = nome?.trim() ?? '';
  if (texto.isEmpty) return 'Informe o nome completo.';
  return null;
}

/// Validação leve de formato de e-mail — mesma regra de
/// `AppValidators.email` (não é RFC completa, só feedback imediato antes do
/// round-trip ao servidor).
String? validarEmail(String? email) {
  final texto = email?.trim() ?? '';
  if (texto.isEmpty) return 'Informe o e-mail.';
  final arroba = texto.indexOf('@');
  final dominio = arroba < 0 ? '' : texto.substring(arroba + 1);
  if (arroba <= 0 || !dominio.contains('.') || dominio.endsWith('.')) {
    return 'Informe um e-mail válido.';
  }
  return null;
}

/// Mesmo algoritmo de `private.is_valid_cpf` (migration
/// `20261005120000_add_profile_access_control.sql`): 11 dígitos, rejeita as
/// 10 sequências de dígito repetido, confere os dois dígitos verificadores.
/// Client-side é só UX — nunca é a autoridade; o banco revalida tudo de
/// novo nas RPCs administrativas (ver `aprovar_usuario`).
String? validarCpf(String? cpf) {
  final digitos = (cpf ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return 'Informe o CPF.';
  if (!_isValidCpf(digitos)) return 'Informe um CPF válido.';
  return null;
}

bool _isValidCpf(String cpf) {
  if (cpf.length != 11 || !RegExp(r'^[0-9]{11}$').hasMatch(cpf)) return false;

  // sequências repetidas (00000000000, 11111111111, ..., 99999999999)
  if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

  final digitos = cpf.split('').map(int.parse).toList();

  var soma = 0;
  for (var i = 0; i < 9; i++) {
    soma += digitos[i] * (10 - i);
  }
  var digito1 = 11 - (soma % 11);
  if (digito1 >= 10) digito1 = 0;
  if (digito1 != digitos[9]) return false;

  soma = 0;
  for (var i = 0; i < 10; i++) {
    soma += digitos[i] * (11 - i);
  }
  var digito2 = 11 - (soma % 11);
  if (digito2 >= 10) digito2 = 0;
  if (digito2 != digitos[10]) return false;

  return true;
}

/// Os 5 requisitos avaliados independentemente (nunca "tudo ou nada") para
/// o checklist visual ✓ que a UI desenha enquanto o usuário digita.
List<RequisitoSenha> avaliarRequisitosSenha(String senha) {
  final satisfeitos = <RequisitoSenha>[];
  if (senha.length >= 12) satisfeitos.add(RequisitoSenha.comprimentoMinimo);
  if (RegExp(r'[A-Z]').hasMatch(senha)) satisfeitos.add(RequisitoSenha.letraMaiuscula);
  if (RegExp(r'[a-z]').hasMatch(senha)) satisfeitos.add(RequisitoSenha.letraMinuscula);
  if (RegExp(r'[0-9]').hasMatch(senha)) satisfeitos.add(RequisitoSenha.numero);
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(senha)) satisfeitos.add(RequisitoSenha.caractereEspecial);
  return satisfeitos;
}

/// `senha` só é válida quando satisfaz os 5 requisitos de
/// [avaliarRequisitosSenha] — 12+ caracteres, maiúscula, minúscula, número,
/// caractere especial.
String? validarSenha(String? senha) {
  final texto = senha ?? '';
  if (texto.isEmpty) return 'Informe a senha.';
  final satisfeitos = avaliarRequisitosSenha(texto).toSet();
  if (satisfeitos.length < RequisitoSenha.values.length) {
    return 'A senha não atende a todos os requisitos.';
  }
  return null;
}

/// `confirmacao` precisa ser idêntica a `senha`.
String? validarConfirmacaoSenha(String? senha, String? confirmacao) {
  if ((confirmacao ?? '').isEmpty) return 'Confirme a senha.';
  if (senha != confirmacao) return 'As senhas não coincidem.';
  return null;
}
