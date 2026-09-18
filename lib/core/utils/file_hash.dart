import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 (hex, minúsculo) do conteúdo de um arquivo — usado hoje só pelo
/// leitor de documentos SEI (PROMPT 11.1, seção 27) para identificar o
/// documento sem persistir nada; nenhuma chamada de rede, nenhum serviço
/// externo.
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
