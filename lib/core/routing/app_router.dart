import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_status.dart';
import '../../features/auth/domain/profile.dart';
import '../../features/auth/presentation/acesso_bloqueado_page.dart';
import '../../features/auth/presentation/acesso_pendente_page.dart';
import '../../features/auth/presentation/acesso_rejeitado_page.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/cadastro_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/administracao/presentation/admin_usuario_detalhe_page.dart';
import '../../features/administracao/presentation/admin_usuarios_page.dart';
import '../../features/configuracoes/presentation/configuracoes_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/localizacoes/presentation/localizacoes_page.dart';
import '../../features/movimentacoes/presentation/movimentacoes_page.dart';
import '../../features/patrimonios/importacao/presentation/patrimonio_import_page.dart';
import '../../features/patrimonios/presentation/patrimonio_detail_page.dart';
import '../../features/patrimonios/presentation/patrimonio_form_page.dart';
import '../../features/patrimonios/presentation/patrimonios_page.dart';
import '../../features/setores/domain/setor.dart';
import '../../features/setores/presentation/setores_page.dart';
import '../shell/app_shell.dart';

const _rotaAdminUsuarios = '/administracao/usuarios';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authStatus = ref.read(authControllerProvider);
      final rota = state.matchedLocation;

      return authStatus.when(
        data: (status) => _redirectFor(status, rota),
        // enquanto resolve (checagem inicial de sessão, ou logo após o
        // login), não força navegação — evita flicker/loop de redirect
        loading: () => null,
        error: (_, _) =>
            (rota == '/login' || rota == '/cadastro') ? null : '/login',
      );
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/cadastro',
        name: 'cadastro',
        builder: (context, state) => const CadastroPage(),
      ),
      GoRoute(
        path: '/acesso/pendente',
        name: 'acesso-pendente',
        builder: (context, state) => const AcessoPendentePage(),
      ),
      GoRoute(
        path: '/acesso/rejeitado',
        name: 'acesso-rejeitado',
        builder: (context, state) => const AcessoRejeitadoPage(),
      ),
      GoRoute(
        path: '/acesso/bloqueado',
        name: 'acesso-bloqueado',
        builder: (context, state) => const AcessoBloqueadoPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(currentRoute: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/patrimonios',
            name: 'patrimonios',
            // `?busca=...` (Dashboard → busca rápida) inicializa o campo
            // de busca já existente de `PatrimoniosPage` — nunca uma
            // segunda busca paralela.
            builder: (context, state) => PatrimoniosPage(
              buscaInicial: state.uri.queryParameters['busca'],
            ),
            routes: [
              // Precisa vir antes de ':id' para que "novo" não seja
              // interpretado como um id.
              GoRoute(
                path: 'novo',
                name: 'patrimonio-novo',
                builder: (context, state) => const PatrimonioFormPage(),
              ),
              GoRoute(
                path: 'importar',
                name: 'patrimonio-importar',
                builder: (context, state) => const PatrimonioImportPage(),
              ),
              GoRoute(
                path: ':id',
                name: 'patrimonio-detalhe',
                builder: (context, state) =>
                    PatrimonioDetailPage(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/movimentacoes',
            name: 'movimentacoes',
            // `?acao=nova` (Dashboard → "Registrar movimentação") e
            // `?acao=importar-sei` (Dashboard → "Documento SEI") — a
            // MESMA `MovimentacoesPage` detecta a ação e abre o
            // diálogo/aba já existente, nenhuma rota nova por ação.
            builder: (context, state) =>
                MovimentacoesPage(acao: state.uri.queryParameters['acao']),
            routes: [
              // Deep-link para o detalhe de UMA movimentação (ex.: "Ver
              // movimentação completa" no Dashboard) — a MESMA
              // `MovimentacoesPage`, que busca por id e abre o diálogo de
              // detalhe já existente automaticamente (ver seção 11 do
              // pedido de refinamento: reutilizar, não duplicar).
              GoRoute(
                path: ':id',
                name: 'movimentacao-detalhe',
                builder: (context, state) => MovimentacoesPage(
                  movimentacaoId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/setores',
            name: 'setores',
            builder: (context, state) => const SetoresPage(),
            routes: [
              GoRoute(
                path: ':setorId/localizacoes',
                name: 'setor-localizacoes',
                builder: (context, state) {
                  final setor = state.extra as Setor?;
                  if (setor == null) {
                    // navegação direta por URL (sem passar pela lista de
                    // Setores) não é suportada — volta para a lista em vez
                    // de quebrar a tela.
                    return const SetoresPage();
                  }
                  return LocalizacoesPage(setor: setor);
                },
              ),
            ],
          ),
          GoRoute(
            path: _rotaAdminUsuarios,
            name: 'administracao-usuarios',
            builder: (context, state) => const AdminUsuariosPage(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'administracao-usuario-detalhe',
                builder: (context, state) =>
                    AdminUsuarioDetalhePage(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/configuracoes',
            name: 'configuracoes',
            builder: (context, state) => const ConfiguracoesPage(),
          ),
        ],
      ),
    ],
  );
});

/// Lógica de redirect centralizada (seção 6 do pedido) — nunca delegada só
/// à visibilidade da sidebar: `unauthenticated`/`pending`/`rejected`/
/// `blocked` cada um só pode ver a própria rota dedicada (e ações, não
/// rotas, como logout); `active` tem as rotas de negócio normais, mas
/// `/administracao/...` exige ADMIN mesmo estando ACTIVE.
String? _redirectFor(AuthStatus status, String rota) {
  switch (status.status) {
    case AuthAccountStatus.unauthenticated:
      return (rota == '/login' || rota == '/cadastro') ? null : '/login';
    case AuthAccountStatus.pending:
      return rota == '/acesso/pendente' ? null : '/acesso/pendente';
    case AuthAccountStatus.rejected:
      return rota == '/acesso/rejeitado' ? null : '/acesso/rejeitado';
    case AuthAccountStatus.blocked:
      return rota == '/acesso/bloqueado' ? null : '/acesso/bloqueado';
    case AuthAccountStatus.active:
      if (rota == '/login' || rota == '/cadastro') return '/dashboard';
      if (rota.startsWith(_rotaAdminUsuarios) && !_ehAdminAtivo(status)) {
        return '/dashboard';
      }
      return null;
  }
}

bool _ehAdminAtivo(AuthStatus status) =>
    status.profile?.perfil == ProfilePerfil.admin;

/// Faz o GoRouter reavaliar `redirect` sempre que [authControllerProvider]
/// muda (login, logout, sessão negada por profile inexistente, ou qualquer
/// transição de `access_status`).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscription = ref.listen<AsyncValue<AuthStatus>>(
      authControllerProvider,
      (previous, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<AuthStatus>> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
