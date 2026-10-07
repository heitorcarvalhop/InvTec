enum ProfilePerfil {
  admin('ADMIN'),
  gestor('GESTOR'),
  operador('OPERADOR'),
  consulta('CONSULTA');

  const ProfilePerfil(this.value);

  final String value;

  static ProfilePerfil fromValue(String value) {
    return ProfilePerfil.values.firstWhere(
      (perfil) => perfil.value == value,
      orElse: () => throw ArgumentError('Perfil de usuário inválido: $value'),
    );
  }
}

/// Rótulo em PT-BR exibido na interface — o enum técnico nunca aparece
/// diretamente para o usuário.
extension ProfilePerfilLabel on ProfilePerfil {
  String get label {
    switch (this) {
      case ProfilePerfil.admin:
        return 'Administrador';
      case ProfilePerfil.gestor:
        return 'Gestor';
      case ProfilePerfil.operador:
        return 'Operador';
      case ProfilePerfil.consulta:
        return 'Consulta';
    }
  }
}

/// Estado completo da conta — ver migration
/// `20261005120000_add_profile_access_control.sql`. `ativo` é mantido em
/// paralelo por compatibilidade com código já existente, mas o banco garante
/// (`profiles_ativo_access_status_coerente`) que os dois nunca divergem:
/// `ACTIVE` ↔ `ativo = true`; `PENDING`/`REJECTED`/`BLOCKED` ↔ `ativo = false`.
enum ProfileAccessStatus {
  pending('PENDING'),
  active('ACTIVE'),
  rejected('REJECTED'),
  blocked('BLOCKED');

  const ProfileAccessStatus(this.value);
  final String value;

  static ProfileAccessStatus fromValue(String value) {
    return ProfileAccessStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError('Status de acesso inválido: $value'),
    );
  }
}

class Profile {
  const Profile({
    required this.id,
    required this.nome,
    this.email,
    required this.perfil,
    required this.ativo,
    required this.criadoEm,
    required this.atualizadoEm,
    required this.accessStatus,
    required this.rejectionCount,
    this.cpf,
    this.approvedAt,
    this.approvedBy,
    this.rejectedReason,
    this.blockedReason,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      nome: json['nome'] as String,
      email: json['email'] as String?,
      perfil: ProfilePerfil.fromValue(json['perfil'] as String),
      ativo: json['ativo'] as bool,
      criadoEm: DateTime.parse(json['criado_em'] as String),
      atualizadoEm: DateTime.parse(json['atualizado_em'] as String),
      accessStatus: ProfileAccessStatus.fromValue(json['access_status'] as String),
      rejectionCount: json['rejection_count'] as int,
      cpf: json['cpf'] as String?,
      approvedAt: json['approved_at'] == null ? null : DateTime.parse(json['approved_at'] as String),
      approvedBy: json['approved_by'] as String?,
      rejectedReason: json['rejected_reason'] as String?,
      blockedReason: json['blocked_reason'] as String?,
    );
  }

  final String id;
  final String nome;
  final String? email;
  final ProfilePerfil perfil;
  final bool ativo;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  /// Somente dígitos (11), ou `null` para contas legadas que nunca
  /// forneceram CPF — ver `profiles.cpf` na migration
  /// `20261005120000_add_profile_access_control.sql`.
  final String? cpf;
  final ProfileAccessStatus accessStatus;

  /// Quantas vezes esta conta já foi rejeitada. 3 rejeições vira `BLOCKED`
  /// automaticamente (ver `rejeitar_usuario` no banco).
  final int rejectionCount;
  final DateTime? approvedAt;
  final String? approvedBy;
  final String? rejectedReason;
  final String? blockedReason;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'perfil': perfil.value,
      'ativo': ativo,
      'criado_em': criadoEm.toIso8601String(),
      'atualizado_em': atualizadoEm.toIso8601String(),
      'access_status': accessStatus.value,
      'rejection_count': rejectionCount,
      'cpf': cpf,
      'approved_at': approvedAt?.toIso8601String(),
      'approved_by': approvedBy,
      'rejected_reason': rejectedReason,
      'blocked_reason': blockedReason,
    };
  }
}
