import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/domain/profile.dart';

void main() {
  final json = {
    'id': 'a1b2c3d4-0000-0000-0000-000000000002',
    'nome': 'Heitor Pereira',
    'email': 'heitor@example.com',
    'perfil': 'ADMIN',
    'ativo': true,
    'criado_em': '2026-01-10T12:00:00.000Z',
    'atualizado_em': '2026-01-11T12:00:00.000Z',
  };

  test('Profile.fromJson converte o perfil para o enum correto', () {
    final profile = Profile.fromJson(json);

    expect(profile.perfil, ProfilePerfil.admin);
    expect(profile.nome, 'Heitor Pereira');
  });

  test('ProfilePerfil.fromValue lança erro para valor desconhecido', () {
    expect(() => ProfilePerfil.fromValue('SUPER_ADMIN'), throwsArgumentError);
  });

  test('toJson serializa o enum de volta para o valor do banco', () {
    final profile = Profile.fromJson(json);
    expect(profile.toJson()['perfil'], 'ADMIN');
  });

  test('email institucional é opcional', () {
    final profile = Profile.fromJson({...json, 'email': null});
    expect(profile.email, isNull);
  });

  test('ProfilePerfilLabel traduz todos os perfis para PT-BR', () {
    expect(ProfilePerfil.admin.label, 'Administrador');
    expect(ProfilePerfil.gestor.label, 'Gestor');
    expect(ProfilePerfil.operador.label, 'Operador');
    expect(ProfilePerfil.consulta.label, 'Consulta');
  });
}
