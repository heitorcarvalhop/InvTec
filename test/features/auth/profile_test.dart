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
    'access_status': 'ACTIVE',
    'rejection_count': 0,
    'cpf': '52998224725',
    'approved_at': '2026-01-10T12:00:00.000Z',
    'approved_by': 'a1b2c3d4-0000-0000-0000-000000000099',
    'rejected_reason': null,
    'blocked_reason': null,
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

  group('ProfileAccessStatus (Etapa 5)', () {
    test('Profile.fromJson converte access_status/rejection_count/cpf/approved_*', () {
      final profile = Profile.fromJson(json);

      expect(profile.accessStatus, ProfileAccessStatus.active);
      expect(profile.rejectionCount, 0);
      expect(profile.cpf, '52998224725');
      expect(profile.approvedAt, DateTime.parse('2026-01-10T12:00:00.000Z'));
      expect(profile.approvedBy, 'a1b2c3d4-0000-0000-0000-000000000099');
      expect(profile.rejectedReason, isNull);
      expect(profile.blockedReason, isNull);
    });

    test('cpf/approved_at/approved_by nulos (conta legada/nunca aprovada) são aceitos', () {
      final profile = Profile.fromJson({
        ...json,
        'cpf': null,
        'approved_at': null,
        'approved_by': null,
        'access_status': 'PENDING',
      });

      expect(profile.cpf, isNull);
      expect(profile.approvedAt, isNull);
      expect(profile.approvedBy, isNull);
      expect(profile.accessStatus, ProfileAccessStatus.pending);
    });

    test('ProfileAccessStatus.fromValue cobre os 4 estados', () {
      expect(ProfileAccessStatus.fromValue('PENDING'), ProfileAccessStatus.pending);
      expect(ProfileAccessStatus.fromValue('ACTIVE'), ProfileAccessStatus.active);
      expect(ProfileAccessStatus.fromValue('REJECTED'), ProfileAccessStatus.rejected);
      expect(ProfileAccessStatus.fromValue('BLOCKED'), ProfileAccessStatus.blocked);
    });

    test('ProfileAccessStatus.fromValue lança erro para valor desconhecido', () {
      expect(() => ProfileAccessStatus.fromValue('ALGO_INVALIDO'), throwsArgumentError);
    });

    test('toJson serializa access_status/rejection_count/cpf/approved_* de volta', () {
      final profile = Profile.fromJson(json);
      final serializado = profile.toJson();

      expect(serializado['access_status'], 'ACTIVE');
      expect(serializado['rejection_count'], 0);
      expect(serializado['cpf'], '52998224725');
      expect(serializado['approved_by'], 'a1b2c3d4-0000-0000-0000-000000000099');
    });
  });
}
