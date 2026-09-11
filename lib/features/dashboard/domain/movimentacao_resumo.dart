import '../../movimentacoes/domain/movimentacao.dart';

/// Versão resumida/denormalizada de uma movimentação para a lista
/// "Movimentações recentes" do dashboard — já traz o rótulo do patrimônio e
/// os nomes de setor de origem/destino (via embed do Postgrest), evitando
/// consultas extras por linha.
class MovimentacaoResumo {
  const MovimentacaoResumo({
    required this.id,
    required this.tipo,
    required this.patrimonioLabel,
    this.origemNome,
    this.destinoNome,
    required this.dataMovimentacao,
  });

  factory MovimentacaoResumo.fromJson(Map<String, dynamic> json) {
    final patrimonio = json['patrimonios'] as Map<String, dynamic>?;
    final origem = json['origem'] as Map<String, dynamic>?;
    final destino = json['destino'] as Map<String, dynamic>?;

    return MovimentacaoResumo(
      id: json['id'] as String,
      tipo: MovimentacaoTipo.fromValue(json['tipo'] as String),
      patrimonioLabel:
          (patrimonio?['numero_patrimonio'] as String?) ??
          (patrimonio?['descricao'] as String?) ??
          'Patrimônio sem identificação',
      origemNome: origem?['nome'] as String?,
      destinoNome: destino?['nome'] as String?,
      dataMovimentacao: DateTime.parse(json['data_movimentacao'] as String),
    );
  }

  final String id;
  final MovimentacaoTipo tipo;
  final String patrimonioLabel;
  final String? origemNome;
  final String? destinoNome;
  final DateTime dataMovimentacao;
}
