import 'package:invtec/features/auth/domain/permissao_efetiva.dart';
import 'package:invtec/features/auth/domain/permissions_repository.dart';
import 'package:invtec/features/auth/domain/profile.dart';

/// Fake em memória de [PermissionsRepository] para testes de PÁGINA (não de
/// `CurrentPermissionsController` em si — isso é
/// `current_permissions_controller_test.dart`). [FakePermissionsRepository.
/// paraPerfil] reproduz EXATAMENTE o seed de `role_permissions` (migration
/// `20261006100000_add_permission_catalog.sql`) — usado por qualquer teste
/// de página que precise simular "este perfil vê o botão X" depois da
/// migração de `profile.perfil == ...` para `ref.hasPermission(...)`
/// (Etapa 5), sem duplicar a tabela de presets em cada arquivo de teste.
class FakePermissionsRepository implements PermissionsRepository {
  FakePermissionsRepository({this.chaves = const {}});

  static const _todasAsChaves = {
    'patrimonio.view',
    'patrimonio.create',
    'patrimonio.edit',
    'patrimonio.compare_update',
    // ADMIN-only, mesmo critério de patrimonio.compare_update — ver
    // migration 20261019120000 (ainda não aplicada em produção).
    'patrimonio.import_historico',
    'movimentacao.view',
    'movimentacao.create',
    'setor.view',
    'setor.manage',
    'localizacao.view',
    'localizacao.manage',
    'tipo_patrimonio.view',
    'tipo_patrimonio.manage',
    'sei.view',
    'sei.manage',
  };

  factory FakePermissionsRepository.paraPerfil(ProfilePerfil perfil) {
    switch (perfil) {
      case ProfilePerfil.admin:
        return FakePermissionsRepository(chaves: _todasAsChaves);
      case ProfilePerfil.gestor:
        // tudo, EXCETO patrimonio.compare_update e patrimonio.import_historico
        // (sempre foram ADMIN puro).
        return FakePermissionsRepository(
          chaves: _todasAsChaves.difference({
            'patrimonio.compare_update',
            'patrimonio.import_historico',
          }),
        );
      case ProfilePerfil.operador:
        return FakePermissionsRepository(
          chaves: {
            'patrimonio.view',
            'patrimonio.create',
            'patrimonio.edit',
            'movimentacao.view',
            'movimentacao.create',
            'setor.view',
            'localizacao.view',
            'tipo_patrimonio.view',
            'sei.view',
            'sei.manage',
          },
        );
      case ProfilePerfil.consulta:
        return FakePermissionsRepository(
          chaves: {
            'patrimonio.view',
            'movimentacao.view',
            'setor.view',
            'localizacao.view',
            'tipo_patrimonio.view',
            'sei.view',
          },
        );
    }
  }

  final Set<String> chaves;

  int minhasPermissoesCallCount = 0;

  @override
  Future<Set<String>> minhasPermissoes() async {
    minhasPermissoesCallCount++;
    return chaves;
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
