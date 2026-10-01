import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 (hex, minúsculo) do conteúdo de um arquivo — usado pelo leitor
/// de documentos SEI para identificar o documento sem persistir nada;
/// nenhuma chamada de rede, nenhum serviço externo.
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
