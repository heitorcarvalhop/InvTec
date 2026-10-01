import '../../../core/utils/setor_display.dart';

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

/// Exibição compacta de um [Setor] — usada em todo dropdown/lista que
/// ofereça um [Setor] inteiro (diferente das telas que só têm nome/sigla
/// resolvidos via embed, que usam [siglaOuNomeSetor]/`SetorCompactText`
/// diretamente).
extension SetorExibicaoCompacta on Setor {
  /// Sigla cadastrada, ou o nome completo quando não há sigla — nunca uma
  /// abreviação inventada. Ver [siglaOuNomeSetor].
  String get rotuloCompacto => siglaOuNomeSetor(sigla: sigla, nome: nome) ?? nome;

  /// [rotuloCompacto] com o sufixo " (inativo)" quando aplicável — para
  /// dropdowns que precisam distinguir setores desativados (ex.: filtro de
  /// Movimentações, que pode referenciar um setor já desativado).
  String get rotuloCompactoComStatus => ativo ? rotuloCompacto : '$rotuloCompacto (inativo)';

  /// Nome completo + o mesmo sufixo de status — texto do `Tooltip` quando
  /// [rotuloCompactoComStatus] mostra a sigla.
  String get nomeComStatus => ativo ? nome : '$nome (inativo)';
}
