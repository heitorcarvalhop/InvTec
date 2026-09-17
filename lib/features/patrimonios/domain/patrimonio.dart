/// Status atual do patrimônio, distinto da movimentação que o originou.
///
/// TRANSFERIDO e INATIVO foram deliberadamente deixados de fora: uma
/// transferência apenas altera o setor atual (não é um estado persistente,
/// e sim consequência de uma movimentação já registrada), e INATIVO seria
/// redundante com BAIXADO — ver docs/database.md.
enum PatrimonioStatus {
  disponivel('DISPONIVEL'),
  emUso('EM_USO'),
  emprestado('EMPRESTADO'),
  emManutencao('EM_MANUTENCAO'),
  baixado('BAIXADO');

  const PatrimonioStatus(this.value);

  final String value;

  static PatrimonioStatus fromValue(String value) {
    return PatrimonioStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () =>
          throw ArgumentError('Status de patrimônio inválido: $value'),
    );
  }
}

/// Rótulo em PT-BR exibido na interface — o enum técnico nunca aparece
/// diretamente para o usuário.
extension PatrimonioStatusLabel on PatrimonioStatus {
  String get label {
    switch (this) {
      case PatrimonioStatus.disponivel:
        return 'Disponível';
      case PatrimonioStatus.emUso:
        return 'Em uso';
      case PatrimonioStatus.emprestado:
        return 'Emprestado';
      case PatrimonioStatus.emManutencao:
        return 'Em manutenção';
      case PatrimonioStatus.baixado:
        return 'Baixado';
    }
  }
}

class Patrimonio {
  const Patrimonio({
    required this.id,
    this.numeroPatrimonio,
    this.numeroSerie,
    required this.tipoId,
    this.marca,
    this.modelo,
    this.descricao,
    this.observacao,
    required this.status,
    required this.setorAtualId,
    this.localizacaoAtualId,
    this.responsavelAtual,
    this.dataAquisicao,
    required this.dataCadastro,
    this.criadoPor,
    required this.atualizadoEm,
  });

  factory Patrimonio.fromJson(Map<String, dynamic> json) {
    return Patrimonio(
      id: json['id'] as String,
      numeroPatrimonio: json['numero_patrimonio'] as String?,
      numeroSerie: json['numero_serie'] as String?,
      tipoId: json['tipo_id'] as String,
      marca: json['marca'] as String?,
      modelo: json['modelo'] as String?,
      descricao: json['descricao'] as String?,
      observacao: json['observacao'] as String?,
      status: PatrimonioStatus.fromValue(json['status'] as String),
      setorAtualId: json['setor_atual_id'] as String,
      localizacaoAtualId: json['localizacao_atual_id'] as String?,
      responsavelAtual: json['responsavel_atual'] as String?,
      dataAquisicao: json['data_aquisicao'] == null
          ? null
          : DateTime.parse(json['data_aquisicao'] as String),
      dataCadastro: DateTime.parse(json['data_cadastro'] as String),
      criadoPor: json['criado_por'] as String?,
      atualizadoEm: DateTime.parse(json['atualizado_em'] as String),
    );
  }

  final String id;
  final String? numeroPatrimonio;
  final String? numeroSerie;
  final String tipoId;
  final String? marca;
  final String? modelo;
  final String? descricao;
  final String? observacao;
  final PatrimonioStatus status;
  final String setorAtualId;
  final String? localizacaoAtualId;
  final String? responsavelAtual;
  final DateTime? dataAquisicao;
  final DateTime dataCadastro;
  final String? criadoPor;
  final DateTime atualizadoEm;

  /// Só expõe os metadados editáveis diretamente; status, setor atual e
  /// responsável atual mudam apenas por movimentação.
  Patrimonio copyWith({
    String? numeroPatrimonio,
    String? numeroSerie,
    String? tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) {
    return Patrimonio(
      id: id,
      numeroPatrimonio: numeroPatrimonio ?? this.numeroPatrimonio,
      numeroSerie: numeroSerie ?? this.numeroSerie,
      tipoId: tipoId ?? this.tipoId,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      descricao: descricao ?? this.descricao,
      observacao: observacao ?? this.observacao,
      status: status,
      setorAtualId: setorAtualId,
      localizacaoAtualId: localizacaoAtualId,
      responsavelAtual: responsavelAtual,
      dataAquisicao: dataAquisicao ?? this.dataAquisicao,
      dataCadastro: dataCadastro,
      criadoPor: criadoPor,
      atualizadoEm: atualizadoEm,
    );
  }
}

/// Mesma normalização aplicada pelo banco em `numero_patrimonio` (trim +
/// maiúsculas, vazio vira nulo), para que buscas exatas encontrem o valor
/// armazenado. Zeros à esquerda são preservados.
String? normalizarNumeroPatrimonio(String? valor) {
  final normalizado = valor?.trim().toUpperCase();
  return (normalizado == null || normalizado.isEmpty) ? null : normalizado;
}
