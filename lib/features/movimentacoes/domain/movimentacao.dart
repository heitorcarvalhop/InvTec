enum MovimentacaoTipo {
  entrada('ENTRADA'),
  saida('SAIDA'),
  transferencia('TRANSFERENCIA'),
  emprestimo('EMPRESTIMO'),
  devolucao('DEVOLUCAO'),
  manutencao('MANUTENCAO'),
  retornoManutencao('RETORNO_MANUTENCAO'),
  baixa('BAIXA'),
  ajusteInventario('AJUSTE_INVENTARIO'),
  // Não representa deslocamento físico: mesmo setor, novo responsável.
  alteracaoResponsavel('ALTERACAO_RESPONSAVEL');

  const MovimentacaoTipo(this.value);

  final String value;

  static MovimentacaoTipo fromValue(String value) {
    return MovimentacaoTipo.values.firstWhere(
      (tipo) => tipo.value == value,
      orElse: () =>
          throw ArgumentError('Tipo de movimentação inválido: $value'),
    );
  }
}

/// Rótulo em PT-BR exibido na interface — o enum técnico nunca aparece
/// diretamente para o usuário.
extension MovimentacaoTipoLabel on MovimentacaoTipo {
  String get label {
    switch (this) {
      case MovimentacaoTipo.entrada:
        return 'Entrada';
      case MovimentacaoTipo.saida:
        return 'Saída';
      case MovimentacaoTipo.transferencia:
        return 'Transferência';
      case MovimentacaoTipo.emprestimo:
        return 'Empréstimo';
      case MovimentacaoTipo.devolucao:
        return 'Devolução';
      case MovimentacaoTipo.manutencao:
        return 'Manutenção';
      case MovimentacaoTipo.retornoManutencao:
        return 'Retorno de manutenção';
      case MovimentacaoTipo.baixa:
        return 'Baixa';
      case MovimentacaoTipo.ajusteInventario:
        return 'Ajuste de inventário';
      case MovimentacaoTipo.alteracaoResponsavel:
        return 'Alteração de responsável';
    }
  }
}

/// Registro de histórico de um patrimônio. Imutável após criado — ver
/// docs/database.md (seção "Histórico imutável").
class Movimentacao {
  const Movimentacao({
    required this.id,
    required this.patrimonioId,
    required this.tipo,
    this.origemId,
    this.destinoId,
    this.localizacaoOrigemId,
    this.localizacaoDestinoId,
    this.responsavelOrigem,
    this.responsavelDestino,
    this.motivo,
    this.observacao,
    this.numeroDocumento,
    this.numeroChamado,
    this.realizadoPor,
    required this.dataMovimentacao,
    required this.criadoEm,
  });

  factory Movimentacao.fromJson(Map<String, dynamic> json) {
    return Movimentacao(
      id: json['id'] as String,
      patrimonioId: json['patrimonio_id'] as String,
      tipo: MovimentacaoTipo.fromValue(json['tipo'] as String),
      origemId: json['origem_id'] as String?,
      destinoId: json['destino_id'] as String?,
      localizacaoOrigemId: json['localizacao_origem_id'] as String?,
      localizacaoDestinoId: json['localizacao_destino_id'] as String?,
      responsavelOrigem: json['responsavel_origem'] as String?,
      responsavelDestino: json['responsavel_destino'] as String?,
      motivo: json['motivo'] as String?,
      observacao: json['observacao'] as String?,
      numeroDocumento: json['numero_documento'] as String?,
      numeroChamado: json['numero_chamado'] as String?,
      realizadoPor: json['realizado_por'] as String?,
      dataMovimentacao: DateTime.parse(json['data_movimentacao'] as String),
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }

  final String id;
  final String patrimonioId;
  final MovimentacaoTipo tipo;
  final String? origemId;
  final String? destinoId;
  final String? localizacaoOrigemId;
  final String? localizacaoDestinoId;
  final String? responsavelOrigem;
  final String? responsavelDestino;
  final String? motivo;
  final String? observacao;
  final String? numeroDocumento;
  final String? numeroChamado;
  final String? realizadoPor;
  final DateTime dataMovimentacao;
  final DateTime criadoEm;
}
