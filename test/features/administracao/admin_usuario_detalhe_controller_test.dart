import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/administracao/data/usuario_admin_repository_supabase.dart';
import 'package:invtec/features/administracao/presentation/admin_usuario_detalhe_controller.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_permissions_repository.dart';
import 'fake_usuario_admin_repository.dart';

Profile _usuario({
  required String id,
  String nome = 'Fulano de Tal',
  String? email = 'fulano@invtec.com',
  String? cpf,
  ProfilePerfil perfil = ProfilePerfil.consulta,
  required ProfileAccessStatus accessStatus,
  int rejectionCount = 0,
  DateTime? approvedAt,
  String? approvedBy,
  String? rejectedReason,
  String? blockedReason,
}) {
  return Profile(
    id: id,
    nome: nome,
    email: email,
    cpf: cpf,
    perfil: perfil,
    ativo: accessStatus == ProfileAccessStatus.active,
    accessStatus: accessStatus,
    rejectionCount: rejectionCount,
    approvedAt: approvedAt,
    approvedBy: approvedBy,
    rejectedReason: rejectedReason,
    blockedReason: blockedReason,
    criadoEm: DateTime(2026, 1, 1),
    atualizadoEm: DateTime(2026, 1, 1),
  );
}

/// Monta o container com o admin logado (`fake-admin-id`, ACTIVE) já
/// resolvido em `authControllerProvider` — mesmo padrão documentado em
/// `notificacoes_controller_test.dart`: resolve `authControllerProvider`
/// ANTES de ler qualquer provider desta feature, para nunca correr contra o
/// `build()` do auth ainda em loading.
Future<ProviderContainer> _containerComAdminLogado({
  required FakeUsuarioAdminRepository fakeUsuarios,
  required FakePermissionsRepository fakePermissoes,
  String adminId = 'fake-admin-id',
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: adminId,
    profileResolver: (_) => _usuario(
      id: adminId,
      nome: 'Admin Logado',
      perfil: ProfilePerfil.admin,
      accessStatus: ProfileAccessStatus.active,
      approvedAt: DateTime(2026, 1, 1),
    ),
  );
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      usuarioAdminRepositoryProvider.overrideWithValue(fakeUsuarios),
      permissionsRepositoryProvider.overrideWithValue(fakePermissoes),
    ],
  );
  await container.read(authControllerProvider.future);
  return container;
}

void main() {
  group('AdminUsuarioDetalheController', () {
    test('carrega usuário + permissões efetivas, sem ser o próprio admin', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.active)],
      );
      final fakePermissoes = FakePermissionsRepository(
        defaults: {'patrimonio.view': true, 'patrimonio.edit': false},
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: fakePermissoes,
      );
      addTearDown(container.dispose);

      final estado = await container.read(adminUsuarioDetalheControllerProvider('u1').future);

      expect(estado.usuario.id, 'u1');
      expect(estado.permissoes, hasLength(2));
      expect(estado.ehProprioUsuarioLogado, isFalse);
      expect(estado.processando, isFalse);
      expect(fakePermissoes.ultimoUserIdConsultado, 'u1');
    });

    test('ehProprioUsuarioLogado é true ao abrir o detalhe do próprio admin', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(
            id: 'fake-admin-id',
            perfil: ProfilePerfil.admin,
            accessStatus: ProfileAccessStatus.active,
            approvedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final fakePermissoes = FakePermissionsRepository();
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: fakePermissoes,
      );
      addTearDown(container.dispose);

      final estado = await container.read(adminUsuarioDetalheControllerProvider('fake-admin-id').future);

      expect(estado.ehProprioUsuarioLogado, isTrue);
    });

    test('aprovar muda access_status para active', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.pending)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container
          .read(adminUsuarioDetalheControllerProvider('u1').notifier)
          .aprovar(ProfilePerfil.operador);

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.accessStatus, ProfileAccessStatus.active);
      expect(estado.usuario.perfil, ProfilePerfil.operador);
      expect(fakeUsuarios.aprovarCallCount, 1);
    });

    test('rejeitar incrementa rejection_count e mantém REJECTED antes da 3ª vez', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.pending, rejectionCount: 1)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container.read(adminUsuarioDetalheControllerProvider('u1').notifier).rejeitar('Documento ilegível');

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.accessStatus, ProfileAccessStatus.rejected);
      expect(estado.usuario.rejectionCount, 2);
    });

    test('3ª rejeição bloqueia a conta automaticamente', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.pending, rejectionCount: 2)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container.read(adminUsuarioDetalheControllerProvider('u1').notifier).rejeitar('Documento inválido');

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.accessStatus, ProfileAccessStatus.blocked);
      expect(estado.usuario.rejectionCount, 3);
      expect(estado.usuario.blockedReason, 'Documento inválido');
    });

    test('desbloquear com approved_at preenchido volta para ACTIVE', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(
            id: 'u1',
            accessStatus: ProfileAccessStatus.blocked,
            approvedAt: DateTime(2025, 6, 1),
            rejectionCount: 1,
          ),
        ],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container.read(adminUsuarioDetalheControllerProvider('u1').notifier).desbloquear();

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.accessStatus, ProfileAccessStatus.active);
    });

    test('desbloquear sem approved_at volta para PENDING com contador zerado', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'u1', accessStatus: ProfileAccessStatus.blocked, rejectionCount: 3, approvedAt: null),
        ],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container.read(adminUsuarioDetalheControllerProvider('u1').notifier).desbloquear();

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.accessStatus, ProfileAccessStatus.pending);
      expect(estado.usuario.rejectionCount, 0);
    });

    test('alterarPerfil troca o perfil do usuário', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', perfil: ProfilePerfil.consulta, accessStatus: ProfileAccessStatus.active)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container
          .read(adminUsuarioDetalheControllerProvider('u1').notifier)
          .alterarPerfil(ProfilePerfil.gestor);

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.perfil, ProfilePerfil.gestor);
    });

    test('erro de "último admin" é mapeado para mensagem amigável', () async {
      // u1 é o ÚNICO ADMIN ACTIVE do cenário (o admin logado é outro id) —
      // tirar o papel de ADMIN dele deve ser recusado com a mesma mensagem
      // amigável que o Postgres produziria (ver
      // trg_profiles_prevent_remove_last_active_admin).
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', perfil: ProfilePerfil.admin, accessStatus: ProfileAccessStatus.active)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);

      await expectLater(
        container.read(adminUsuarioDetalheControllerProvider('u1').notifier).alterarPerfil(ProfilePerfil.operador),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Não é possível remover o último administrador ativo do sistema.',
          ),
        ),
      );

      // Estado não deve ter mudado (a ação falhou) e processando deve ter
      // voltado a false.
      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.perfil, ProfilePerfil.admin);
      expect(estado.processando, isFalse);
    });

    test('alterarIdentidade edita nome e CPF', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', nome: 'Nome Antigo', accessStatus: ProfileAccessStatus.active)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container
          .read(adminUsuarioDetalheControllerProvider('u1').notifier)
          .alterarIdentidade(nome: 'Nome Corrigido', cpf: '98765432100', motivo: 'Erro de digitação no cadastro');

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.usuario.nome, 'Nome Corrigido');
      expect(estado.usuario.cpf, '98765432100');
    });

    test('CPF legado NULL não quebra o carregamento do detalhe', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', cpf: null, accessStatus: ProfileAccessStatus.active)],
      );
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: FakePermissionsRepository(),
      );
      addTearDown(container.dispose);

      final estado = await container.read(adminUsuarioDetalheControllerProvider('u1').future);

      expect(estado.usuario.cpf, isNull);
    });

    test('definirPermissao reflete o override no estado', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.active)],
      );
      final fakePermissoes = FakePermissionsRepository(defaults: {'setor.manage': false});
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: fakePermissoes,
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container
          .read(adminUsuarioDetalheControllerProvider('u1').notifier)
          .definirPermissao('setor.manage', true);

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      final permissao = estado.permissoes.single;
      expect(permissao.override, isTrue);
      expect(permissao.efetiva, isTrue);
      expect(fakePermissoes.definirPermissaoCallCount, 1);
    });

    test('removerOverridePermissao volta a herdar o padrão do perfil', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.active)],
      );
      final fakePermissoes = FakePermissionsRepository(defaults: {'setor.manage': false})
        ..definirOverrideParaTeste('u1', 'setor.manage', true);
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: fakePermissoes,
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container
          .read(adminUsuarioDetalheControllerProvider('u1').notifier)
          .removerOverridePermissao('setor.manage');

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      final permissao = estado.permissoes.single;
      expect(permissao.override, isNull);
      expect(permissao.efetiva, isFalse);
      expect(fakePermissoes.removerOverrideCallCount, 1);
    });

    test('resetarPermissoes remove todos os overrides do usuário', () async {
      final fakeUsuarios = FakeUsuarioAdminRepository(
        usuarios: [_usuario(id: 'u1', accessStatus: ProfileAccessStatus.active)],
      );
      final fakePermissoes = FakePermissionsRepository(defaults: {'setor.manage': false, 'patrimonio.view': true})
        ..definirOverrideParaTeste('u1', 'setor.manage', true)
        ..definirOverrideParaTeste('u1', 'patrimonio.view', false);
      final container = await _containerComAdminLogado(
        fakeUsuarios: fakeUsuarios,
        fakePermissoes: fakePermissoes,
      );
      addTearDown(container.dispose);

      await container.read(adminUsuarioDetalheControllerProvider('u1').future);
      await container.read(adminUsuarioDetalheControllerProvider('u1').notifier).resetarPermissoes();

      final estado = container.read(adminUsuarioDetalheControllerProvider('u1')).value!;
      expect(estado.permissoes.every((p) => p.override == null), isTrue);
      expect(fakePermissoes.resetarCallCount, 1);
    });

    test(
      'admin tentando alterar as PRÓPRIAS permissões é bloqueado client-side, sem chamar o repositório',
      () async {
        const adminId = 'fake-admin-id';
        final fakeUsuarios = FakeUsuarioAdminRepository(
          usuarios: [
            _usuario(
              id: adminId,
              perfil: ProfilePerfil.admin,
              accessStatus: ProfileAccessStatus.active,
              approvedAt: DateTime(2026, 1, 1),
            ),
          ],
        );
        final fakePermissoes = FakePermissionsRepository(defaults: {'setor.manage': false});
        final container = await _containerComAdminLogado(
          fakeUsuarios: fakeUsuarios,
          fakePermissoes: fakePermissoes,
          adminId: adminId,
        );
        addTearDown(container.dispose);

        await container.read(adminUsuarioDetalheControllerProvider(adminId).future);

        await expectLater(
          container
              .read(adminUsuarioDetalheControllerProvider(adminId).notifier)
              .definirPermissao('setor.manage', true),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              'Suas próprias permissões não podem ser alteradas nesta tela.',
            ),
          ),
        );

        expect(fakePermissoes.definirPermissaoCallCount, 0);

        await expectLater(
          container.read(adminUsuarioDetalheControllerProvider(adminId).notifier).removerOverridePermissao('setor.manage'),
          throwsA(isA<AppException>()),
        );
        expect(fakePermissoes.removerOverrideCallCount, 0);

        await expectLater(
          container.read(adminUsuarioDetalheControllerProvider(adminId).notifier).resetarPermissoes(),
          throwsA(isA<AppException>()),
        );
        expect(fakePermissoes.resetarCallCount, 0);
      },
    );
  });
}
