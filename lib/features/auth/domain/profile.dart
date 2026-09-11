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

class Profile {
  const Profile({
    required this.id,
    required this.nome,
    this.email,
    required this.perfil,
    required this.ativo,
    required this.criadoEm,
    required this.atualizadoEm,
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
    );
  }

  final String id;
  final String nome;
  final String? email;
  final ProfilePerfil perfil;
  final bool ativo;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'email': email,
      'perfil': perfil.value,
      'ativo': ativo,
      'criado_em': criadoEm.toIso8601String(),
      'atualizado_em': atualizadoEm.toIso8601String(),
    };
  }
}
