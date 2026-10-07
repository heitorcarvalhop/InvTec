import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error_messages.dart';
import '../../../core/errors/app_exception.dart';
import '../../auth/data/permissions_repository_supabase.dart';
import '../../auth/domain/permissao_efetiva.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/usuario_admin_repository_supabase.dart';

final adminUsuarioDetalheControllerProvider =
    AsyncNotifierProvider.family<AdminUsuarioDetalheController, AdminUsuarioDetalheState, String>(
      AdminUsuarioDetalheController.new,
    );

class AdminUsuarioDetalheState {
  const AdminUsuarioDetalheState({
    required this.usuario,
    required this.permissoes,
    required this.ehProprioUsuarioLogado,
    this.processando = false,
  });

  final Profile usuario;
  final List<PermissaoEfetiva> permissoes;

  /// Proteção de auto-gestão (seção 43): `true` quando o usuário exibido
  /// nesta tela é o MESMO admin logado (`auth.uid()`). O banco já recusa
  /// toda RPC de override de permissão sobre a própria conta do chamador
  /// (`definir_permissao_usuario`/`remover_override_permissao_usuario`/
  /// `resetar_permissoes_usuario` — ver
  /// `supabase/migrations/20261006110000_add_has_permission_and_override_rpcs.sql`),
  /// mas a UI não deve nem oferecer os controles que sempre falhariam —
  /// exposto aqui para quem desenhar a tela decidir (desabilitar botões,
  /// ocultar seção, etc.).
  final bool ehProprioUsuarioLogado;

  /// Alguma ação de escrita (aprovar/rejeitar/bloquear/.../permissões) está
  /// em andamento — usado pela UI para desabilitar botões e evitar duplo
  /// clique (seção 49). Reseta para `false` automaticamente quando
  /// [AdminUsuarioDetalheController] reconstrói o estado (sucesso) ou é
  /// restaurado manualmente em caso de falha — ver
  /// [AdminUsuarioDetalheController._executarAcao].
  final bool processando;

  AdminUsuarioDetalheState copyWith({bool? processando}) {
    return AdminUsuarioDetalheState(
      usuario: usuario,
      permissoes: permissoes,
      ehProprioUsuarioLogado: ehProprioUsuarioLogado,
      processando: processando ?? this.processando,
    );
  }
}

/// Estado de detalhe de UM usuário administrado — `family` por `userId`
/// (mesmo padrão de `LocalizacoesController`, família por `setorId`): cada
/// tela de detalhe tem seu próprio controller/estado, sem interferir com a
/// de outro usuário aberta em paralelo.
///
/// Carrega o [Profile] alvo (via [UsuarioAdminRepository]) e suas
/// permissões efetivas (via `PermissionsRepository.obterPermissoesUsuario`,
/// feature `auth` — reaproveitado aqui, sem um segundo cliente de RPC de
/// permissões duplicado) em paralelo.
///
/// Depende de `authControllerProvider` só para saber qual é o admin
/// logado (checagem de auto-gestão, [AdminUsuarioDetalheState.
/// ehProprioUsuarioLogado]) — usa `ref.read` + `ref.listen`, NUNCA
/// `ref.watch`, dentro de [build]: mesmo motivo documentado em
/// `NotificacoesController` (ver `lib/features/notificacoes/presentation/
/// notificacoes_controller.dart`) — `ref.watch` recriaria este `build()` a
/// cada transição assíncrona do provider de auth, não só quando o admin
/// logado de fato muda, e combinado com o carregamento duplo (perfil +
/// permissões) deste controller é terreno fértil para reentrância.
class AdminUsuarioDetalheController extends AsyncNotifier<AdminUsuarioDetalheState> {
  AdminUsuarioDetalheController(this.userId);

  final String userId;

  String? _adminLogadoIdConhecido;

  @override
  Future<AdminUsuarioDetalheState> build() async {
    final adminLogadoId = ref.read(authControllerProvider).value?.profile?.id;
    _adminLogadoIdConhecido = adminLogadoId;

    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return; // carregando/erro sem valor — nada a comparar ainda
      final novoId = next.value?.profile?.id;
      if (novoId == _adminLogadoIdConhecido) return;
      _adminLogadoIdConhecido = novoId;
      ref.invalidateSelf();
    });

    final usuarioAdminRepository = ref.watch(usuarioAdminRepositoryProvider);
    final permissionsRepository = ref.watch(permissionsRepositoryProvider);

    final usuarioFuture = usuarioAdminRepository.buscarPorId(userId);
    final permissoesFuture = permissionsRepository.obterPermissoesUsuario(userId);
    final usuario = await usuarioFuture;
    final permissoes = await permissoesFuture;

    return AdminUsuarioDetalheState(
      usuario: usuario,
      permissoes: permissoes,
      ehProprioUsuarioLogado: adminLogadoId != null && adminLogadoId == userId,
    );
  }

  Future<void> aprovar(ProfilePerfil perfil) {
    return _executarAcao(
      () => ref.read(usuarioAdminRepositoryProvider).aprovar(userId: userId, perfil: perfil),
    );
  }

  Future<void> rejeitar(String motivo) {
    return _executarAcao(
      () => ref.read(usuarioAdminRepositoryProvider).rejeitar(userId: userId, motivo: motivo),
    );
  }

  Future<void> bloquear(String motivo) {
    return _executarAcao(
      () => ref.read(usuarioAdminRepositoryProvider).bloquear(userId: userId, motivo: motivo),
    );
  }

  Future<void> desbloquear() {
    return _executarAcao(() => ref.read(usuarioAdminRepositoryProvider).desbloquear(userId));
  }

  Future<void> alterarIdentidade({
    required String nome,
    required String cpf,
    required String motivo,
  }) {
    return _executarAcao(
      () => ref
          .read(usuarioAdminRepositoryProvider)
          .alterarIdentidade(userId: userId, nome: nome, cpf: cpf, motivo: motivo),
    );
  }

  Future<void> alterarPerfil(ProfilePerfil perfil) {
    return _executarAcao(
      () => ref.read(usuarioAdminRepositoryProvider).alterarPerfil(userId: userId, perfil: perfil),
    );
  }

  // As três ações abaixo são `async` de propósito (nunca só `{ return
  // _executarAcao(...); }`): `_recusarSeProprioUsuario()` lança de forma
  // SÍNCRONA, e uma função `async` captura qualquer exceção do próprio
  // corpo — mesmo antes do primeiro `await` — dentro do `Future` que
  // devolve, em vez de lançá-la na hora em que o método é chamado. Sem
  // `async` aqui, `controller.definirPermissao(...)` lançaria ANTES de
  // devolver um `Future`, e um chamador que faça
  // `await controller.definirPermissao(...)` (ou `expectLater(..., throwsA(...))`,
  // como nos testes) nunca teria a chance de tratar o erro como rejeição do
  // `Future` — ele escaparia como uma exceção síncrona comum.
  Future<void> definirPermissao(String permissionKey, bool granted) async {
    _recusarSeProprioUsuario();
    return _executarAcao(
      () => ref
          .read(permissionsRepositoryProvider)
          .definirPermissaoUsuario(userId: userId, permissionKey: permissionKey, granted: granted),
    );
  }

  Future<void> removerOverridePermissao(String permissionKey) async {
    _recusarSeProprioUsuario();
    return _executarAcao(
      () => ref
          .read(permissionsRepositoryProvider)
          .removerOverridePermissaoUsuario(userId: userId, permissionKey: permissionKey),
    );
  }

  Future<void> resetarPermissoes() async {
    _recusarSeProprioUsuario();
    return _executarAcao(
      () => ref.read(permissionsRepositoryProvider).resetarPermissoesUsuario(userId),
    );
  }

  /// Proteção de auto-gestão (seção 43), lado cliente: recusa ANTES de
  /// chamar o repositório — o banco também recusaria (as 3 RPCs de override
  /// já bloqueiam `p_user_id = auth.uid()`), mas a UI não deve depender só
  /// disso. Lança a mesma `AppException` que uma falha de servidor
  /// lançaria, para o chamador tratar de um jeito só (`on AppException
  /// catch (e) { ... e.message ... }`, mesmo padrão já usado em todo o
  /// projeto — ver `LocalizacoesPage`/`localizacao_form_dialog.dart`).
  void _recusarSeProprioUsuario() {
    if (_adminLogadoIdConhecido != null && _adminLogadoIdConhecido == userId) {
      throw const AppException('Suas próprias permissões não podem ser alteradas nesta tela.');
    }
  }

  /// Executa uma ação de escrita marcando [AdminUsuarioDetalheState.
  /// processando] durante a chamada (proteção contra duplo clique — seção
  /// 49). Em caso de sucesso, `ref.invalidateSelf()` reconstrói o estado do
  /// zero a partir do servidor (processando volta a `false` naturalmente,
  /// como parte do novo estado). Em caso de falha, `processando` é
  /// restaurado manualmente para `false` (o resto do estado não muda — a
  /// ação não teve efeito) e a exceção é relançada já traduzida: se já é
  /// `AppException` (como as lançadas por `UsuarioAdminRepositorySupabase`,
  /// que já aplica `traduzirErroSupabase`), a mensagem amigável é
  /// preservada tal qual; qualquer outro erro passa por
  /// `traduzirErroSupabase` aqui — rede de segurança para o caso de
  /// `PermissionsRepository` (feature `auth`, fora do nosso escopo) lançar
  /// algo que não tenha passado por tradução.
  Future<void> _executarAcao(Future<void> Function() acao) async {
    final estadoAtual = state.value;
    if (estadoAtual != null) {
      state = AsyncData(estadoAtual.copyWith(processando: true));
    }

    try {
      await acao();
    } catch (e) {
      final base = state.value ?? estadoAtual;
      if (base != null) {
        state = AsyncData(base.copyWith(processando: false));
      }
      if (e is AppException) rethrow;
      throw AppException(traduzirErroSupabase(e), cause: e);
    }

    ref.invalidateSelf();
    await future;
  }
}
