import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/permissions_repository_supabase.dart';
import '../domain/auth_status.dart';
import '../domain/current_permissions.dart';
import 'auth_controller.dart';

final currentPermissionsControllerProvider =
    AsyncNotifierProvider<CurrentPermissionsController, CurrentPermissions>(
      CurrentPermissionsController.new,
      // Riverpod 3 tenta de novo automaticamente por padrão (10 tentativas,
      // até ~38s de backoff) antes de assentar em AsyncError — isso
      // esconderia o fail-closed por até ~38s (o provider fica "retrying",
      // não um AsyncError estável) em vez de deixar o widget decidir
      // imediatamente se mostra "tentar de novo" (seção 22 do pedido).
      // `retry: (_, __) => null` desativa o retry automático: a primeira
      // falha já assenta em AsyncError.
      retry: (retryCount, error) => null,
    );

/// Permissões granulares EFETIVAS do usuário atual. Segue o MESMO padrão
/// `ref.read` + `ref.listen` de `NotificacoesController` — NUNCA
/// `ref.watch(authControllerProvider)` dentro deste `build()` assíncrono
/// (mesmo motivo documentado lá: ReplaySubject do gotrue + reentrância de
/// AsyncNotifier). Só invalida quando a identidade do usuário resolvido
/// realmente muda (login/logout/troca de usuário) — não a cada recomputo
/// trivial do mesmo usuário.
///
/// Só carrega `minhasPermissoes()` quando `AuthStatus.status == active`;
/// para qualquer outro estado (unauthenticated/pending/rejected/blocked)
/// resolve direto para [CurrentPermissions.vazio] SEM chamar o repositório
/// — nenhum desses estados pode operar o sistema de negócio, então não há
/// permissão de negócio a consultar.
///
/// FAIL CLOSED deliberado (seção 22 do pedido): se `minhasPermissoes()`
/// lançar, este AsyncNotifier fica em `AsyncError` — NUNCA capturamos o
/// erro para virar `CurrentPermissions.vazio()` silenciosamente. Embora o
/// efeito prático de um erro escondido fosse "sem permissões" (que por
/// acidente já é fail-closed), preferimos deixar o erro visível: cada
/// widget consumidor decide se mostra "tentar de novo" ou outro tratamento
/// — não é decisão deste controller. `HasPermissionX.hasPermission` abaixo
/// já trata `AsyncError`/`AsyncLoading` como `false` (fail closed
/// automático), então nenhum widget que só verifica uma permissão precisa
/// lidar com o erro explicitamente.
class CurrentPermissionsController extends AsyncNotifier<CurrentPermissions> {
  String? _userIdConhecido;
  AuthAccountStatus? _statusConhecido;

  @override
  Future<CurrentPermissions> build() async {
    final authStatus = ref.read(authControllerProvider).value;
    _userIdConhecido = authStatus?.profile?.id;
    _statusConhecido = authStatus?.status;

    ref.listen(authControllerProvider, (previous, next) {
      if (!next.hasValue) return; // carregando/erro sem valor — nada a comparar ainda
      final novoStatus = next.value;
      final novoUserId = novoStatus?.profile?.id;
      final novoStatusEnum = novoStatus?.status;
      if (novoUserId == _userIdConhecido && novoStatusEnum == _statusConhecido) return;
      _userIdConhecido = novoUserId;
      _statusConhecido = novoStatusEnum;
      ref.invalidateSelf();
    });

    if (authStatus?.status != AuthAccountStatus.active) {
      return const CurrentPermissions.vazio();
    }

    final repository = ref.watch(permissionsRepositoryProvider);
    final chaves = await repository.minhasPermissoes();
    return CurrentPermissions(chaves);
  }
}

/// Conveniência para widgets: `ref.hasPermission('patrimonio.create')` em
/// vez de `ref.watch(currentPermissionsControllerProvider).value?.
/// hasPermission(...) ?? false`. Fail closed automático — enquanto carrega
/// ou em erro, `.value` é `null`, então devolve `false`.
extension HasPermissionX on WidgetRef {
  bool hasPermission(String key) =>
      watch(currentPermissionsControllerProvider).value?.hasPermission(key) ?? false;
}
