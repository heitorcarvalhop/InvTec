import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chave usada no armazenamento local do dispositivo (nunca no Supabase).
const _sidebarCollapsedKey = 'invtec.sidebar_collapsed';

/// Preferência explícita do usuário para a sidebar fixa (recolhida ou
/// expandida), persistida localmente via `SharedPreferences`.
///
/// `null` significa "nenhuma escolha explícita ainda": nesse caso é o
/// layout (ver `AppShell`) quem decide um padrão por largura de janela, sem
/// nunca gravar nada aqui — assim um padrão automático nunca sobrescreve
/// (nem é confundido com) uma preferência que o usuário de fato escolheu.
class SidebarController extends AsyncNotifier<bool?> {
  @override
  Future<bool?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_sidebarCollapsedKey) ? prefs.getBool(_sidebarCollapsedKey) : null;
  }

  Future<void> definir(bool collapsed) async {
    state = AsyncData(collapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidebarCollapsedKey, collapsed);
  }
}

final sidebarControllerProvider = AsyncNotifierProvider<SidebarController, bool?>(
  SidebarController.new,
);
