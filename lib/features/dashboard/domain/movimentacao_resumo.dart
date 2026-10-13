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
    this.origemSigla,
    this.destinoNome,
    this.destinoSigla,
    this.autorNome,
    required this.dataMovimentacao,
  });

  factory MovimentacaoResumo.fromJson(Map<String, dynamic> json) {
    final patrimonio = json['patrimonios'] as Map<String, dynamic>?;
    final origem = json['origem'] as Map<String, dynamic>?;
    final destino = json['destino'] as Map<String, dynamic>?;
    final autor = json['autor'] as Map<String, dynamic>?;

    return MovimentacaoResumo(
      id: json['id'] as String,
      tipo: MovimentacaoTipo.fromValue(json['tipo'] as String),
      patrimonioLabel:
          (patrimonio?['numero_patrimonio'] as String?) ??
          (patrimonio?['descricao'] as String?) ??
          'Patrimônio sem identificação',
      origemNome: origem?['nome'] as String?,
      origemSigla: origem?['sigla'] as String?,
      destinoNome: destino?['nome'] as String?,
      destinoSigla: destino?['sigla'] as String?,
      autorNome: autor?['nome'] as String?,
      dataMovimentacao: DateTime.parse(json['data_movimentacao'] as String),
    );
  }

  final String id;
  final MovimentacaoTipo tipo;
  final String patrimonioLabel;
  final String? origemNome;

  /// `setores.sigla` do setor de origem — igual ao campo já usado pela tela
  /// completa de Movimentações (`MovimentacaoListagemItem.setorOrigemSigla`
  /// via `siglaOuNomeSetor`). `null` quando o setor não tem sigla
  /// cadastrada; a UI cai para [origemNome].
  final String? origemSigla;
  final String? destinoNome;

  /// `setores.sigla` do setor de destino — ver [origemSigla].
  final String? destinoSigla;

  /// Quem registrou a movimentação (`profiles.nome` via
  /// `realizado_por`) — `null` quando a RLS de `profiles` não resolve o
  /// autor para o perfil atual (mesma situação de
  /// `PatrimonioDetalhe.criadoPorProfile`), nunca um erro.
  final String? autorNome;
  final DateTime dataMovimentacao;
}
