import 'movimentacao.dart';

/// Uma linha da listagem geral de movimentações (PROMPT 10.1) — já traz
/// tudo que a tabela/detalhe precisam exibir (patrimônio, setores,
/// localizações e autor) resolvido via embed do Postgrest numa única
/// consulta, nunca uma por linha.
class MovimentacaoListagemItem {
  const MovimentacaoListagemItem({
    required this.id,
    required this.tipo,
    required this.patrimonioId,
    this.patrimonioNumero,
    this.patrimonioTipoNome,
    this.setorOrigemId,
    this.setorDestinoId,
    this.setorOrigemNome,
    this.setorDestinoNome,
    this.localizacaoOrigemNome,
    this.localizacaoDestinoNome,
    this.responsavelOrigem,
    this.responsavelDestino,
    this.motivo,
    this.observacao,
    this.numeroDocumento,
    this.numeroChamado,
    this.autorNome,
    required this.dataMovimentacao,
  });

  factory MovimentacaoListagemItem.fromJson(Map<String, dynamic> json) {
    final patrimonio = json['patrimonios'] as Map<String, dynamic>?;
    final tipoPatrimonio = patrimonio?['tipos_patrimonio'] as Map<String, dynamic>?;
    final setorOrigem = json['setor_origem'] as Map<String, dynamic>?;
    final setorDestino = json['setor_destino'] as Map<String, dynamic>?;
    final localizacaoOrigem = json['localizacao_origem'] as Map<String, dynamic>?;
    final localizacaoDestino = json['localizacao_destino'] as Map<String, dynamic>?;
    // profiles_select só deixa ADMIN/GESTOR verem o nome de outro usuário
    // (ver policy em supabase/migrations) — para OPERADOR/CONSULTA, o embed
    // de um autor que não é o próprio usuário volta null e a UI mostra "—",
    // nunca um erro.
    final autor = json['autor'] as Map<String, dynamic>?;

    return MovimentacaoListagemItem(
      id: json['id'] as String,
      tipo: MovimentacaoTipo.fromValue(json['tipo'] as String),
      patrimonioId: json['patrimonio_id'] as String,
      patrimonioNumero: patrimonio?['numero_patrimonio'] as String?,
      patrimonioTipoNome: tipoPatrimonio?['nome'] as String?,
      setorOrigemId: json['origem_id'] as String?,
      setorDestinoId: json['destino_id'] as String?,
      setorOrigemNome: setorOrigem?['nome'] as String?,
      setorDestinoNome: setorDestino?['nome'] as String?,
      localizacaoOrigemNome: localizacaoOrigem?['nome'] as String?,
      localizacaoDestinoNome: localizacaoDestino?['nome'] as String?,
      responsavelOrigem: json['responsavel_origem'] as String?,
      responsavelDestino: json['responsavel_destino'] as String?,
      motivo: json['motivo'] as String?,
      observacao: json['observacao'] as String?,
      numeroDocumento: json['numero_documento'] as String?,
      numeroChamado: json['numero_chamado'] as String?,
      autorNome: autor?['nome'] as String?,
      dataMovimentacao: DateTime.parse(json['data_movimentacao'] as String),
    );
  }

  final String id;
  final MovimentacaoTipo tipo;
  final String patrimonioId;
  final String? patrimonioNumero;
  final String? patrimonioTipoNome;

  /// Ids brutos de setor (origem/destino) — só para permitir o filtro
  /// "Setor" (PROMPT 10.1); a UI usa sempre os nomes resolvidos abaixo.
  final String? setorOrigemId;
  final String? setorDestinoId;
  final String? setorOrigemNome;
  final String? setorDestinoNome;
  final String? localizacaoOrigemNome;
  final String? localizacaoDestinoNome;
  final String? responsavelOrigem;
  final String? responsavelDestino;
  final String? motivo;
  final String? observacao;
  final String? numeroDocumento;
  final String? numeroChamado;
  final String? autorNome;
  final DateTime dataMovimentacao;

  /// Responsável exibido na coluna/detalhe: o de destino (quem fica com o
  /// patrimônio depois da movimentação) é mais relevante que o de origem;
  /// cai para o de origem só quando não há destino (ex.: BAIXA).
  String? get responsavelExibido => responsavelDestino ?? responsavelOrigem;

  /// Texto exibido para o autor (PROMPT 10.1.1) — nunca "—". `realizado_por`
  /// é `not null` no banco (ver migration), então um `autorNome` ausente
  /// aqui é sempre a RLS ocultando o nome de outro usuário (policy
  /// `profiles_select`: só ADMIN/GESTOR ou o próprio autor enxergam o
  /// nome), nunca falta de dado. Um texto diferente de "—" evita que o
  /// usuário leia isso como "autor não registrado".
  String get autorExibido => autorNome ?? 'Não disponível';
}
