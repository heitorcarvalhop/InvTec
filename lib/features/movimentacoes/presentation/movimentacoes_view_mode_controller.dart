import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/widgets/list_view_mode.dart';

/// Chave usada no armazenamento local do dispositivo (nunca no Supabase).
const _movimentacoesViewModeKey = 'invtec.movimentacoes_view_mode';

/// Preferência de modo de visualização (Lista/Cards) da listagem de
/// Movimentações, persistida localmente via `SharedPreferences` — mesmo
/// padrão de `SidebarController`, mas sem o caso "sem preferência": aqui o
/// padrão é sempre [ListViewMode.list] (nunca `null`), já que a tela
/// precisa de um modo para renderizar mesmo antes de qualquer escolha do
/// usuário.
class MovimentacoesViewModeController extends AsyncNotifier<ListViewMode> {
  @override
  Future<ListViewMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getString(_movimentacoesViewModeKey);
    return ListViewMode.values.firstWhere((modo) => modo.name == salvo, orElse: () => ListViewMode.list);
  }

  Future<void> definir(ListViewMode modo) async {
    state = AsyncData(modo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_movimentacoesViewModeKey, modo.name);
  }
}

final movimentacoesViewModeControllerProvider =
    AsyncNotifierProvider<MovimentacoesViewModeController, ListViewMode>(MovimentacoesViewModeController.new);
