import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/profile.dart';
import '../data/usuario_admin_repository_supabase.dart';

final adminUsuariosControllerProvider =
    AsyncNotifierProvider<AdminUsuariosController, AdminUsuariosState>(
      AdminUsuariosController.new,
    );

class AdminUsuariosState {
  const AdminUsuariosState({
    required this.status,
    required this.usuarios,
    required this.pendentesCount,
    this.busca = '',
  });

  final ProfileAccessStatus status;
  final List<Profile> usuarios;
  final String busca;

  /// Total de solicitações PENDING — para o badge "Pendentes (N)" (seção
  /// 45), carregado sempre junto da lista principal, independente da aba
  /// selecionada. Ver [AdminUsuariosController.build].
  final int pendentesCount;
}

/// Lista de usuários da tela "Administração > Usuários": uma aba por
/// `access_status` (pending/active/rejected/blocked) + busca textual.
///
/// Mantém `_status`/`_busca` como campos mutáveis do notifier (mesmo padrão
/// de [PatrimoniosController]/`LocalizacoesController`): cada ação de
/// filtro atualiza o campo e chama `ref.invalidateSelf()`, deixando
/// [build] recalcular a partir do estado atual. Sem debounce na busca aqui
/// — diferente de `PatrimoniosController` (lista potencialmente grande), a
/// tabela `profiles` deste projeto tem poucos usuários por `access_status`,
/// então uma consulta por tecla não é um problema de performance real; se a
/// UI quiser poupar chamadas enquanto o usuário digita, pode fazer seu
/// próprio debounce antes de chamar [buscar] — mantém este controller mais
/// simples.
class AdminUsuariosController extends AsyncNotifier<AdminUsuariosState> {
  ProfileAccessStatus _status = ProfileAccessStatus.pending;
  String _busca = '';

  @override
  Future<AdminUsuariosState> build() async {
    final repository = ref.watch(usuarioAdminRepositoryProvider);
    final buscaOuNull = _busca.isEmpty ? null : _busca;

    final usuariosFuture = repository.listar(status: _status, busca: buscaOuNull);

    // Contador de pendentes (seção 45): reaproveita a MESMA consulta já em
    // voo quando a aba atual já é "Pendentes" sem filtro de texto (evita
    // duplicar a chamada); caso contrário, busca separadamente. Nunca abre
    // uma subscription Realtime só para o badge — um recarregamento comum
    // (troca de aba, busca, `recarregar()`) já é suficiente, como pedido.
    final pendentesFuture = (_status == ProfileAccessStatus.pending && buscaOuNull == null)
        ? usuariosFuture
        : repository.listar(status: ProfileAccessStatus.pending);

    final usuarios = await usuariosFuture;
    final pendentes = await pendentesFuture;

    return AdminUsuariosState(
      status: _status,
      usuarios: usuarios,
      busca: _busca,
      pendentesCount: pendentes.length,
    );
  }

  Future<void> trocarStatus(ProfileAccessStatus status) async {
    _status = status;
    ref.invalidateSelf();
    await future;
  }

  Future<void> buscar(String termo) async {
    _busca = termo.trim();
    ref.invalidateSelf();
    await future;
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }
}
