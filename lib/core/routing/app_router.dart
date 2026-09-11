import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_status.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/configuracoes/presentation/configuracoes_page.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/movimentacoes/presentation/movimentacoes_page.dart';
import '../../features/patrimonios/importacao/presentation/patrimonio_import_page.dart';
import '../../features/patrimonios/presentation/patrimonio_detail_page.dart';
import '../../features/patrimonios/presentation/patrimonio_form_page.dart';
import '../../features/patrimonios/presentation/patrimonios_page.dart';
import '../../features/setores/presentation/setores_page.dart';
import '../shell/app_shell.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authStatus = ref.read(authControllerProvider);
      final isLoggingIn = state.matchedLocation == '/login';

      return authStatus.when(
        data: (status) {
          if (!status.isAuthenticated) {
            return isLoggingIn ? null : '/login';
          }
          return isLoggingIn ? '/dashboard' : null;
        },
        // enquanto resolve (checagem inicial de sessão, ou logo após o
        // login), não força navegação — evita flicker/loop de redirect
        loading: () => null,
        error: (_, _) => isLoggingIn ? null : '/login',
      );
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
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
            builder: (context, state) => const PatrimoniosPage(),
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
                builder: (context, state) => PatrimonioDetailPage(
                  id: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/movimentacoes',
            name: 'movimentacoes',
            builder: (context, state) => const MovimentacoesPage(),
          ),
          GoRoute(
            path: '/setores',
            name: 'setores',
            builder: (context, state) => const SetoresPage(),
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

/// Faz o GoRouter reavaliar `redirect` sempre que [authControllerProvider]
/// muda (login, logout, sessão negada por profile inexistente/inativo).
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
