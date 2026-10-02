import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/widgets/list_view_mode.dart';

/// Chave usada no armazenamento local do dispositivo (nunca no Supabase).
const _patrimoniosViewModeKey = 'invtec.patrimonios_view_mode';

/// Preferência de visualização (Lista/Cards) da listagem de Patrimônios,
/// persistida localmente via `SharedPreferences` — mesmo padrão de
/// [SidebarController], mas mais simples: aqui não existe o conceito de
/// "nenhuma escolha ainda", o padrão é sempre [ListViewMode.list] quando
/// nada foi salvo.
class PatrimoniosViewModeController extends AsyncNotifier<ListViewMode> {
  @override
  Future<ListViewMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getString(_patrimoniosViewModeKey);
    return ListViewMode.values.firstWhere(
      (modo) => modo.name == salvo,
      orElse: () => ListViewMode.list,
    );
  }

  Future<void> definir(ListViewMode modo) async {
    state = AsyncData(modo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_patrimoniosViewModeKey, modo.name);
  }
}

final patrimoniosViewModeControllerProvider =
    AsyncNotifierProvider<PatrimoniosViewModeController, ListViewMode>(
      PatrimoniosViewModeController.new,
    );
