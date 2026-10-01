import 'dart:math';

/// Gera um UUID v4 (aleatório) no formato padrão
/// `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` (RFC 4122), usando
/// `Random.secure()` (fonte criptograficamente segura do próprio Dart —
/// nenhum pacote novo precisou ser adicionado a `pubspec.yaml`).
///
/// PROMPT 11.5.6 — usado para gerar `lote_id` no CLIENTE, uma única vez por
/// decisão de conclusão em lote confirmada (`SeiConclusaoLoteController`):
/// `documentos_sei_lotes_conclusao.lote_id` é `primary key` e NUNCA gerado
/// pelo banco (`gen_random_uuid()` ali produziria uma chave nova a cada
/// chamada, o que destruiria a detecção de retry) — ver
/// `supabase/migrations/20260928100000_add_concluir_itens_documento_sei_lote.sql`.
String gerarUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // Bits de versão (4) e variante (RFC 4122) — sem isto o valor não é um
  // UUID v4 válido, mesmo sendo 16 bytes aleatórios.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int start, int end) => bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
