import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chave usada no armazenamento local do dispositivo (nunca no Supabase —
/// PROMPT 9.3, "não salvar preferência de tema no Supabase nesta etapa").
const _themeModeKey = 'invtec.theme_mode';

/// Preferência de tema (claro/escuro) do usuário — persistida localmente
/// via `SharedPreferences`, nunca exige rede para ser restaurada. O InvTec
/// só oferece as duas opções explícitas ao usuário (nunca "seguir o
/// sistema"): sem preferência salva, o padrão é o tema claro.
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey) == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> alternar() async {
    final atual = state.value ?? ThemeMode.light;
    await definir(atual == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Aplica [modo] imediatamente (antes mesmo de terminar de persistir) —
  /// seção "TEMA CLARO E ESCURO" do PROMPT 9.3: a troca precisa ser
  /// instantânea, a escrita local em disco acontece em segundo plano.
  Future<void> definir(ThemeMode modo) async {
    state = AsyncData(modo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, modo == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeModeControllerProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
