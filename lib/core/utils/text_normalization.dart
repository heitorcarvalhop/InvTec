/// `null`/vazio/só espaços → `null`; qualquer outro texto → aparado
/// (`trim`). Usado antes de enviar campos textuais OPCIONAIS a uma RPC —
/// nunca para campos onde string vazia tem significado próprio (nenhum
/// campo do domínio hoje tem esse caso; auditar antes de reusar em um novo
/// lugar).
///
/// PROMPT 10.2.3: sem isso, um campo deixado em branco na UI (que um
/// `TextEditingController` sempre representa como `""`, nunca `null`) era
/// enviado literalmente como string vazia para a RPC, em vez de `null`.
String? nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
