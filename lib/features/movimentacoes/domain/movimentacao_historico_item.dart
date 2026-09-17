import 'movimentacao.dart';

/// Entrada do histórico (timeline) de UM patrimônio, com os nomes de
/// setor/localização de origem e destino já resolvidos (via embed do
/// Postgrest) para exibição — a mesma ideia de [MovimentacaoResumo], só que
/// com todos os campos que a tela de detalhe do patrimônio precisa exibir.
/// Assim como [Movimentacao], é imutável: o histórico nunca é editado
/// (ver docs/database.md, seção "Histórico imutável").
class MovimentacaoHistoricoItem {
  const MovimentacaoHistoricoItem({
    required this.id,
    required this.tipo,
    this.setorOrigemNome,
    this.setorDestinoNome,
    this.localizacaoOrigemNome,
    this.localizacaoDestinoNome,
    this.responsavelOrigem,
    this.responsavelDestino,
    this.motivo,
    this.observacao,
    required this.dataMovimentacao,
  });

  factory MovimentacaoHistoricoItem.fromJson(Map<String, dynamic> json) {
    final setorOrigem = json['setor_origem'] as Map<String, dynamic>?;
    final setorDestino = json['setor_destino'] as Map<String, dynamic>?;
    final localizacaoOrigem = json['localizacao_origem'] as Map<String, dynamic>?;
    final localizacaoDestino = json['localizacao_destino'] as Map<String, dynamic>?;

    return MovimentacaoHistoricoItem(
      id: json['id'] as String,
      tipo: MovimentacaoTipo.fromValue(json['tipo'] as String),
      setorOrigemNome: setorOrigem?['nome'] as String?,
      setorDestinoNome: setorDestino?['nome'] as String?,
      localizacaoOrigemNome: localizacaoOrigem?['nome'] as String?,
      localizacaoDestinoNome: localizacaoDestino?['nome'] as String?,
      responsavelOrigem: json['responsavel_origem'] as String?,
      responsavelDestino: json['responsavel_destino'] as String?,
      motivo: json['motivo'] as String?,
      observacao: json['observacao'] as String?,
      dataMovimentacao: DateTime.parse(json['data_movimentacao'] as String),
    );
  }

  final String id;
  final MovimentacaoTipo tipo;
  final String? setorOrigemNome;
  final String? setorDestinoNome;
  final String? localizacaoOrigemNome;
  final String? localizacaoDestinoNome;
  final String? responsavelOrigem;
  final String? responsavelDestino;
  final String? motivo;
  final String? observacao;
  final DateTime dataMovimentacao;
}
