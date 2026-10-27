import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `Platform.isAndroid` reflete o SO que executa o PROCESSO (no `flutter
/// test`, o host de desenvolvimento — nunca um dispositivo-alvo simulado),
/// então nenhuma UI que dependa dele é testável em widget test se ler
/// `Platform.isAndroid` direto. Este provider existe só para isso: testes
/// sobrescrevem com `isAndroidProvider.overrideWithValue(true/false)`, a UI
/// real nunca precisa (nem deve) fazer isso.
final isAndroidProvider = Provider<bool>((ref) => Platform.isAndroid);
