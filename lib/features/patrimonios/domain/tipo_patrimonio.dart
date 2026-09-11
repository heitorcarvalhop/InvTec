/// Categoria de equipamento (Notebook, Monitor, etc.).
///
/// Representada como tabela no banco (não enum), pois é um dado
/// administrativo que pode crescer com o tempo — ver docs/database.md.
class TipoPatrimonio {
  const TipoPatrimonio({
    required this.id,
    required this.nome,
    this.descricao,
    required this.ativo,
    required this.criadoEm,
  });

  factory TipoPatrimonio.fromJson(Map<String, dynamic> json) {
    return TipoPatrimonio(
      id: json['id'] as String,
      nome: json['nome'] as String,
      descricao: json['descricao'] as String?,
      ativo: json['ativo'] as bool,
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }

  final String id;
  final String nome;
  final String? descricao;
  final bool ativo;
  final DateTime criadoEm;
}
