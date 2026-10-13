import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Versão exibida em Configurações > Sobre. Lê direto do pacote instalado
/// (CFBundleShortVersionString/FileVersion conforme a plataforma), nunca
/// hardcoded — a única fonte de verdade é `version:` em pubspec.yaml.
final appInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});
