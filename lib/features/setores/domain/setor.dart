class Setor {
  const Setor({
    required this.id,
    required this.nome,
    this.sigla,
    this.descricao,
    required this.ativo,
    required this.criadoEm,
  });

  factory Setor.fromJson(Map<String, dynamic> json) {
    return Setor(
      id: json['id'] as String,
      nome: json['nome'] as String,
      sigla: json['sigla'] as String?,
      descricao: json['descricao'] as String?,
      ativo: json['ativo'] as bool,
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }

  final String id;
  final String nome;
  final String? sigla;
  final String? descricao;
  final bool ativo;
  final DateTime criadoEm;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'sigla': sigla,
      'descricao': descricao,
      'ativo': ativo,
      'criado_em': criadoEm.toIso8601String(),
    };
  }

  Setor copyWith({
    String? nome,
    String? sigla,
    String? descricao,
    bool? ativo,
  }) {
    return Setor(
      id: id,
      nome: nome ?? this.nome,
      sigla: sigla ?? this.sigla,
      descricao: descricao ?? this.descricao,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm,
    );
  }
}
