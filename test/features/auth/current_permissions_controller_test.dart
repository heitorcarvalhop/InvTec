import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/permissao_efetiva.dart';
import 'package:invtec/features/auth/domain/permissions_repository.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/auth/presentation/current_permissions_controller.dart';

import 'fake_auth_repository.dart';

Profile _profile({
  required ProfilePerfil perfil,
  ProfileAccessStatus accessStatus = ProfileAccessStatus.active,
}) {
  return Profile(
    id: 'fake-user-id',
    nome: 'Usuária de Teste',
    email: 'teste@invtec.com',
    perfil: perfil,
    ativo: accessStatus == ProfileAccessStatus.active,
    criadoEm: DateTime.utc(2026, 1, 1),
    atualizadoEm: DateTime.utc(2026, 1, 1),
    accessStatus: accessStatus,
    rejectionCount: 0,
  );
}

/// Fake mínimo de `PermissionsRepository` só para este arquivo — só
/// `minhasPermissoes` importa para `CurrentPermissionsController`; os
/// demais métodos nunca são chamados por ele.
class _FakePermissionsRepository implements PermissionsRepository {
  _FakePermissionsRepository({this.chaves, this.erro});

  final Set<String>? chaves;
  final Object? erro;
  int chamadas = 0;

  @override
  Future<Set<String>> minhasPermissoes() async {
    chamadas++;
    final erroConfigurado = erro;
    if (erroConfigurado != null) throw erroConfigurado;
    return chaves ?? const {};
  }

  @override
  Future<List<PermissaoEfetiva>> obterPermissoesUsuario(String userId) => throw UnimplementedError();

  @override
  Future<void> definirPermissaoUsuario({
    required String userId,
    required String permissionKey,
    required bool granted,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removerOverridePermissaoUsuario({
    required String userId,
    required String permissionKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> resetarPermissoesUsuario(String userId) => throw UnimplementedError();
}

void main() {
  group('CurrentPermissionsController', () {
    test('OPERADOR com patrimonio.create: hasPermission true', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.operador),
      );
      final fakePerms = _FakePermissionsRepository(chaves: {'patrimonio.create', 'patrimonio.view'});
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          permissionsRepositoryProvider.overrideWithValue(fakePerms),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);

      await container.read(authControllerProvider.future);
      final permissoes = await container.read(currentPermissionsControllerProvider.future);

      expect(permissoes.hasPermission('patrimonio.create'), isTrue);
    });

    test('CONSULTA sem patrimonio.create: hasPermission false', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.consulta),
      );
      final fakePerms = _FakePermissionsRepository(chaves: {'patrimonio.view'});
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          permissionsRepositoryProvider.overrideWithValue(fakePerms),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);

      await container.read(authControllerProvider.future);
      final permissoes = await container.read(currentPermissionsControllerProvider.future);

      expect(permissoes.hasPermission('patrimonio.create'), isFalse);
    });

    test('CONSULTA com override granted=true (ex.: patrimonio.create liberado individualmente)', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.consulta),
      );
      // minhas_permissoes() já devolve o conjunto EFETIVO (perfil + override
      // resolvidos pelo servidor) — simulamos o override já aplicado.
      final fakePerms = _FakePermissionsRepository(chaves: {'patrimonio.view', 'patrimonio.create'});
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          permissionsRepositoryProvider.overrideWithValue(fakePerms),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);

      await container.read(authControllerProvider.future);
      final permissoes = await container.read(currentPermissionsControllerProvider.future);

      expect(permissoes.hasPermission('patrimonio.create'), isTrue);
    });

    test(
      'estado não-ACTIVE (pending/rejected/blocked/unauthenticated) resolve vazio sem chamar o repositório',
      () async {
        final fakeAuth = FakeAuthRepository(
          initialUserId: 'fake-user-id',
          profileResolver: (_) => _profile(perfil: ProfilePerfil.admin, accessStatus: ProfileAccessStatus.pending),
        );
        final fakePerms = _FakePermissionsRepository(chaves: {'patrimonio.create'});
        final container = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            permissionsRepositoryProvider.overrideWithValue(fakePerms),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(fakeAuth.dispose);

        await container.read(authControllerProvider.future);
        final permissoes = await container.read(currentPermissionsControllerProvider.future);

        expect(permissoes.hasPermission('patrimonio.create'), isFalse);
        expect(fakePerms.chamadas, 0);
      },
    );

    test('falha ao carregar: AsyncError, fail closed (hasPermission nunca true)', () async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(perfil: ProfilePerfil.admin),
      );
      final fakePerms = _FakePermissionsRepository(erro: Exception('falha de rede'));
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          permissionsRepositoryProvider.overrideWithValue(fakePerms),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(fakeAuth.dispose);

      await container.read(authControllerProvider.future);

      // Nunca captura o erro para virar CurrentPermissions.vazio() — fica
      // em AsyncError de verdade (seção 22: fail closed, mas sem esconder o
      // erro do widget consumidor).
      await expectLater(
        container.read(currentPermissionsControllerProvider.future),
        throwsException,
      );
      expect(container.read(currentPermissionsControllerProvider).hasError, isTrue);
    });
  });
}
