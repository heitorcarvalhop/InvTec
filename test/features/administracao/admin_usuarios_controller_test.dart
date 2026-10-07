import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/administracao/data/usuario_admin_repository_supabase.dart';
import 'package:invtec/features/administracao/presentation/admin_usuarios_controller.dart';
import 'package:invtec/features/auth/domain/profile.dart';

import 'fake_usuario_admin_repository.dart';

Profile _usuario({
  required String id,
  String nome = 'Fulano de Tal',
  String? email = 'fulano@invtec.com',
  String? cpf,
  ProfilePerfil perfil = ProfilePerfil.consulta,
  required ProfileAccessStatus accessStatus,
  int rejectionCount = 0,
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
    approvedAt: null,
    approvedBy: null,
    rejectedReason: null,
    blockedReason: null,
    criadoEm: DateTime(2026, 1, 1),
    atualizadoEm: DateTime(2026, 1, 1),
  );
}

void main() {
  group('AdminUsuariosController', () {
    late FakeUsuarioAdminRepository fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'p1', nome: 'João Pendente', accessStatus: ProfileAccessStatus.pending),
          _usuario(id: 'p2', nome: 'Maria Pendente', accessStatus: ProfileAccessStatus.pending),
          _usuario(
            id: 'a1',
            nome: 'Carlos Ativo',
            email: 'carlos@invtec.com',
            cpf: '12345678900',
            accessStatus: ProfileAccessStatus.active,
          ),
          _usuario(id: 'r1', nome: 'Rejeitado', accessStatus: ProfileAccessStatus.rejected),
          _usuario(id: 'b1', nome: 'Bloqueado', accessStatus: ProfileAccessStatus.blocked),
        ],
      );
      container = ProviderContainer(
        overrides: [usuarioAdminRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      addTearDown(container.dispose);
    });

    test('build() carrega PENDING por padrão', () async {
      final estado = await container.read(adminUsuariosControllerProvider.future);

      expect(estado.status, ProfileAccessStatus.pending);
      expect(estado.usuarios.map((u) => u.id), containsAll(['p1', 'p2']));
      expect(estado.pendentesCount, 2);
    });

    test('trocarStatus(active) lista só usuários ativos', () async {
      await container.read(adminUsuariosControllerProvider.future);

      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.active);

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.status, ProfileAccessStatus.active);
      expect(estado.usuarios.map((u) => u.id), ['a1']);
      // Pendentes continua refletido mesmo fora da aba "Pendentes" — seção 45.
      expect(estado.pendentesCount, 2);
    });

    test('trocarStatus(rejected) lista só usuários rejeitados', () async {
      await container.read(adminUsuariosControllerProvider.future);

      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.rejected);

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios.map((u) => u.id), ['r1']);
    });

    test('trocarStatus(blocked) lista só usuários bloqueados', () async {
      await container.read(adminUsuariosControllerProvider.future);

      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.blocked);

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios.map((u) => u.id), ['b1']);
    });

    test('buscar filtra por nome', () async {
      await container.read(adminUsuariosControllerProvider.future);
      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.active);

      await container.read(adminUsuariosControllerProvider.notifier).buscar('Carlos');

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios.map((u) => u.id), ['a1']);
    });

    test('buscar filtra por e-mail', () async {
      await container.read(adminUsuariosControllerProvider.future);
      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.active);

      await container.read(adminUsuariosControllerProvider.notifier).buscar('carlos@invtec.com');

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios.map((u) => u.id), ['a1']);
    });

    test('buscar filtra por CPF (ignorando pontuação digitada)', () async {
      await container.read(adminUsuariosControllerProvider.future);
      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.active);

      await container.read(adminUsuariosControllerProvider.notifier).buscar('123.456.789-00');

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios.map((u) => u.id), ['a1']);
    });

    test('buscar sem resultados devolve lista vazia, sem erro', () async {
      await container.read(adminUsuariosControllerProvider.future);
      await container.read(adminUsuariosControllerProvider.notifier).trocarStatus(ProfileAccessStatus.active);

      await container.read(adminUsuariosControllerProvider.notifier).buscar('ninguém com esse nome');

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios, isEmpty);
    });

    test('recarregar busca o estado atual de novo no repositório', () async {
      await container.read(adminUsuariosControllerProvider.future);

      await container.read(adminUsuariosControllerProvider.notifier).recarregar();

      final estado = container.read(adminUsuariosControllerProvider).value!;
      expect(estado.usuarios.map((u) => u.id), containsAll(['p1', 'p2']));
    });
  });
}
