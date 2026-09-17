/// Localização física/organizacional dentro de uma gerência (`Setor`) —
/// ex.: "Home Office" e "Datacenter - Universitário" dentro de GETEC.
/// Sempre pertence a exatamente uma gerência (`setorId`) e é opcional para
/// um patrimônio (ver docs/database.md e a migration
/// `20260914140000_add_localizacoes.sql`).
class Localizacao {
  const Localizacao({
    required this.id,
    required this.setorId,
    required this.nome,
    this.sigla,
    required this.ativo,
    required this.criadoEm,
  });

  factory Localizacao.fromJson(Map<String, dynamic> json) {
    return Localizacao(
      id: json['id'] as String,
      setorId: json['setor_id'] as String,
      nome: json['nome'] as String,
      sigla: json['sigla'] as String?,
      ativo: json['ativo'] as bool,
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }

  final String id;
  final String setorId;
  final String nome;
  final String? sigla;
  final bool ativo;
  final DateTime criadoEm;
}
