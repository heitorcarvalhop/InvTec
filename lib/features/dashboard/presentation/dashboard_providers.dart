import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracao/data/usuario_admin_repository_supabase.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/current_permissions_controller.dart';
import '../../notificacoes/data/app_notification_repository_supabase.dart';
import '../data/dashboard_repository_supabase.dart';
import '../domain/dashboard_distribuicoes.dart';
import '../domain/dashboard_kpis.dart';
import '../domain/movimentacao_resumo.dart';

/// Carrega só as contagens cuja permissão o usuário atual tem — nunca
/// dispara a consulta de uma contagem que ele não pode ver (seção 19 do
/// pedido: "não carregar... não apenas esconder depois de consultar").
/// `autoDispose` para não manter números obsoletos em memória ao sair do
/// Dashboard.
final dashboardKpisProvider = FutureProvider.autoDispose<DashboardKpis>((ref) async {
  final permissoes = ref.watch(currentPermissionsControllerProvider).value;
  bool pode(String chave) => permissoes?.hasPermission(chave) ?? false;

  final repository = ref.watch(dashboardRepositoryProvider);
  final trintaDiasAtras = DateTime.now().subtract(const Duration(days: 30));

  final futures = <String, Future<int>>{};
  if (pode('patrimonio.view')) futures['patrimonios'] = repository.contarPatrimonios();
  if (pode('setor.view')) futures['setores'] = repository.contarSetoresAtivos();
  if (pode('localizacao.view')) futures['localizacoes'] = repository.contarLocalizacoesAtivas();
  if (pode('tipo_patrimonio.view')) futures['tipos'] = repository.contarTiposAtivos();
  if (pode('movimentacao.view')) {
    futures['movimentacoes30d'] = repository.contarMovimentacoesDesde(trintaDiasAtras);
  }

  final chaves = futures.keys.toList();
  final valores = await Future.wait(futures.values);
  final porChave = Map<String, int>.fromIterables(chaves, valores);

  return DashboardKpis(
    totalPatrimonios: porChave['patrimonios'],
    totalSetores: porChave['setores'],
    totalLocalizacoes: porChave['localizacoes'],
    totalTipos: porChave['tipos'],
    movimentacoesUltimos30Dias: porChave['movimentacoes30d'],
  );
});

/// `null` quando o usuário não tem `patrimonio.view` — a seção inteira
/// (setor/tipo/localização) fica oculta, nunca consultada.
final dashboardDistribuicoesProvider = FutureProvider.autoDispose<DashboardDistribuicoes?>((ref) async {
  final pode = ref.watch(currentPermissionsControllerProvider).value?.hasPermission('patrimonio.view') ?? false;
  if (!pode) return null;

  final repository = ref.watch(dashboardRepositoryProvider);
  return repository.carregarDistribuicoes();
});

/// `null` quando o usuário não tem `movimentacao.view` — o painel
/// "Movimentações recentes" fica oculto, nunca consultado.
final dashboardMovimentacoesRecentesProvider = FutureProvider.autoDispose<List<MovimentacaoResumo>?>((ref) async {
  final pode = ref.watch(currentPermissionsControllerProvider).value?.hasPermission('movimentacao.view') ?? false;
  if (!pode) return null;

  final repository = ref.watch(dashboardRepositoryProvider);
  return repository.listarMovimentacoesRecentes();
});

/// Pendências administrativas resumidas (seção "Atenção"). Mesmo critério
/// já usado para o sino de notificações no shell (`profile.perfil ==
/// ProfilePerfil.admin`, nunca uma permissão granular — notificações
/// administrativas ainda não se estendem a outros perfis): `null` para
/// qualquer perfil que não seja ADMIN, e a seção fica oculta.
class DashboardAtencaoAdmin {
  const DashboardAtencaoAdmin({
    required this.solicitacoesPendentes,
    required this.notificacoesNaoLidas,
  });

  final int solicitacoesPendentes;
  final int notificacoesNaoLidas;

  bool get temAlgo => solicitacoesPendentes > 0 || notificacoesNaoLidas > 0;
}

final dashboardAtencaoAdminProvider = FutureProvider.autoDispose<DashboardAtencaoAdmin?>((ref) async {
  final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
  if (perfil != ProfilePerfil.admin) return null;

  final usuarioAdminRepository = ref.watch(usuarioAdminRepositoryProvider);
  final notificationRepository = ref.watch(appNotificationRepositoryProvider);

  // Disparadas juntas (sem `await` entre as duas chamadas) para rodar em
  // paralelo — nunca uma consulta esperando a outra terminar.
  final pendentesFuture = usuarioAdminRepository.listar(status: ProfileAccessStatus.pending);
  final naoLidasFuture = notificationRepository.contarNaoLidas();

  final pendentes = await pendentesFuture;
  final naoLidas = await naoLidasFuture;

  return DashboardAtencaoAdmin(
    solicitacoesPendentes: pendentes.length,
    notificacoesNaoLidas: naoLidas,
  );
});
