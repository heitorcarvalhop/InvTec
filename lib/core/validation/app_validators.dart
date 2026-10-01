/// Validators de formulário reutilizados por mais de uma tela.
class AppValidators {
  const AppValidators._();

  /// Número patrimonial é opcional, mas quando preenchido deve conter só
  /// dígitos: a coluna é `text` (preserva zeros à esquerda), porém o campo
  /// é semanticamente numérico em todo o app (cadastro, edição e
  /// importação). Usado junto com `FilteringTextInputFormatter.digitsOnly`.
  static String? numeroPatrimonio(String? value) =>
      _somenteDigitos(value, campo: 'Número patrimonial');

  /// Campos de correção de dados SEI que são sempre dígitos puros (o
  /// "Processo" fica de fora: dados já existentes usam formato com ponto,
  /// ex. "2026.0001", então não é um campo numérico). Cobrem o caso do
  /// valor já chegar não-numérico por outro caminho que não a digitação
  /// (ex.: texto original extraído do PDF, nunca editado).
  static String? numeroDocumentoSei(String? value) =>
      _somenteDigitos(value, campo: 'Número do documento SEI');

  static String? numeroChamado(String? value) =>
      _somenteDigitos(value, campo: 'Número do chamado');

  static String? _somenteDigitos(String? value, {required String campo}) {
    final texto = value?.trim() ?? '';
    if (texto.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(texto)) {
      return '$campo deve conter apenas números.';
    }
    return null;
  }

  /// Validação leve de formato de e-mail (não é RFC completa) — só para dar
  /// feedback imediato antes do round-trip ao servidor de autenticação.
  static String? email(String? value) {
    final texto = value?.trim() ?? '';
    if (texto.isEmpty) return 'Informe o e-mail';
    final arroba = texto.indexOf('@');
    final dominio = arroba < 0 ? '' : texto.substring(arroba + 1);
    if (arroba <= 0 || !dominio.contains('.') || dominio.endsWith('.')) {
      return 'Informe um e-mail válido.';
    }
    return null;
  }
}
