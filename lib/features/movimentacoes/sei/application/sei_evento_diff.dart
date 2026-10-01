/// Interpretação pura (sem I/O) de `dados_antes`/`dados_depois` de um
/// [SeiEventoDocumento] do tipo EDICAO — a auditoria já grava o retrato
/// completo antes/depois (ver `editar_documento_sei_pendente` na migration:
/// `documento` com os 4 campos principais, `itens` com a linha inteira de
/// `documentos_sei_itens` — `to_jsonb(i.*)` — capturada antes e depois da
/// correção). Este arquivo só extrai quais campos realmente mudaram, nunca
/// reinterpreta nem recalcula nada que a migration já não tenha registrado.
///
/// Nunca confunde os três conceitos distintos de um item: "original
/// extraído do PDF" (`*_original`, nunca muda por edição — por isso nunca
/// aparece como um campo diffado por si só aqui), "valor antes da edição"
/// ([SeiCampoAlterado.antes]) e "valor depois da edição"
/// ([SeiCampoAlterado.depois]). Para os campos que têm par
/// original/corrigido, "antes"/"depois" usa o valor efetivo (corrigido ??
/// original) de cada lado — nunca a coluna `_corrigido` bruta sozinha: a
/// primeira correção de um item vai de `_corrigido = null` para
/// `_corrigido = 'X'`, mas o que o usuário realmente mudou foi do original
/// para X (ex.: "9999 → 9998", nunca "— → 9998" quando 9999 já era o valor
/// efetivo antes). Os campos resolvidos de destino (sem par original) usam
/// o valor bruto como está. Nunca inclui metadados internos de auditoria
/// (`corrigido_por`, `corrigido_em`, `motivo_correcao` — este último já é o
/// `descricao` do próprio evento, mostrado à parte) que mudam em toda
/// edição e não interessam ao usuário como "campo alterado".
library;

/// Uma alteração pontual: `rotulo` já pronto para exibição, `antes`/`depois`
/// ainda nos tipos brutos do jsonb (String/num/null) — a camada de UI é
/// quem decide como formatar cada `chave` (texto puro, enum, ou um id que
/// precisa ser resolvido para nome, ex.: `destino_setor_id`).
class SeiCampoAlterado {
  const SeiCampoAlterado({required this.chave, required this.rotulo, required this.antes, required this.depois});

  final String chave;
  final String rotulo;
  final Object? antes;
  final Object? depois;
}

/// Uma linha (item) cujo conteúdo mudou num evento EDICAO — [numeroPatrimonio]
/// é só para IDENTIFICAR a linha na apresentação (ex.: "Patrimônio
/// 900000001"), nunca usado para decisão; cai para "Linha N" quando nenhum
/// número (original ou corrigido) está disponível.
class SeiDiffItem {
  const SeiDiffItem({required this.itemId, required this.numeroPatrimonio, required this.linha, required this.campos});

  final String itemId;
  final String? numeroPatrimonio;
  final int? linha;
  final List<SeiCampoAlterado> campos;

  String get rotuloItem => numeroPatrimonio != null ? 'Patrimônio $numeroPatrimonio' : 'Linha ${linha ?? '?'}';
}

/// Campos principais do documento que uma edição pode alterar (chave jsonb
/// -> rótulo de exibição). Mesmo conjunto que `_dados_antes`/`_dados_depois`
/// da RPC gravam dentro de `documento`.
const camposDocumentoEditavel = {
  'numero_documento_sei': 'Número do documento SEI',
  'numero_processo': 'Processo',
  'numero_documento_formatado': 'Número formatado',
  'assunto': 'Assunto',
};

/// Campos de item que uma edição pode alterar: chave jsonb -> (rótulo,
/// chave do par "_original" — `null` para os cinco campos resolvidos, que
/// não têm um lado original). O valor efetivo de um campo com par original
/// é sempre `bruto[chave] ?? bruto[chaveOriginal]` — nunca a coluna
/// `_corrigido` sozinha (ver comentário do topo do arquivo).
///
/// Deliberadamente nunca inclui metadados internos de auditoria
/// (`corrigido_por`/`corrigido_em`/`motivo_correcao`/`atualizado_em`) que
/// mudam em toda edição sem interessar ao usuário como "campo alterado".
const camposItemEditavel = {
  'numero_patrimonio_corrigido': ('Número patrimonial', 'numero_patrimonio_original'),
  'destino_texto_corrigido': ('Destino (texto do documento)', 'destino_texto_original'),
  'numero_chamado_corrigido': ('Número do chamado', 'numero_chamado_original'),
  'equipamento_texto_corrigido': ('Equipamento', 'equipamento_texto_original'),
  'destino_setor_id': ('Setor de destino resolvido', null),
  'localizacao_destino_id': ('Localização de destino', null),
  'decisao_localizacao': ('Decisão de localização', null),
  'responsavel_destino': ('Responsável de destino', null),
  'decisao_responsavel': ('Decisão de responsável', null),
};

/// Extrai só os campos PRINCIPAIS do documento que mudaram entre
/// `dados_antes['documento']` e `dados_depois['documento']` — nunca lista um
/// campo cujo valor é idêntico nos dois lados.
List<SeiCampoAlterado> diffDocumentoDoEvento(Map<String, Object?>? dadosAntes, Map<String, Object?>? dadosDepois) {
  final antesDoc = dadosAntes?['documento'] as Map<String, Object?>?;
  final depoisDoc = dadosDepois?['documento'] as Map<String, Object?>?;
  if (antesDoc == null && depoisDoc == null) return const [];

  final campos = <SeiCampoAlterado>[];
  for (final entrada in camposDocumentoEditavel.entries) {
    final valorAntes = antesDoc?[entrada.key];
    final valorDepois = depoisDoc?[entrada.key];
    if (valorAntes != valorDepois) {
      campos.add(SeiCampoAlterado(chave: entrada.key, rotulo: entrada.value, antes: valorAntes, depois: valorDepois));
    }
  }
  return campos;
}

/// Extrai, item a item (pareados por `id`, nunca por posição — as duas
/// consultas que produzem `itens_antes`/`itens_depois` na RPC não garantem a
/// mesma ordem), só os campos que realmente mudaram. Itens sem nenhum campo
/// alterado (ex.: um item listado em `p_itens_alterados` cuja correção
/// terminou vazia) não aparecem no resultado.
List<SeiDiffItem> diffItensDoEvento(Map<String, Object?>? dadosAntes, Map<String, Object?>? dadosDepois) {
  final itensAntes = _itensComo(dadosAntes);
  final itensDepois = _itensComo(dadosDepois);
  final antesPorId = {for (final item in itensAntes) item['id'] as String: item};
  final depoisPorId = {for (final item in itensDepois) item['id'] as String: item};
  final ids = {...antesPorId.keys, ...depoisPorId.keys};

  final resultado = <SeiDiffItem>[];
  for (final id in ids) {
    final antes = antesPorId[id];
    final depois = depoisPorId[id];

    final campos = <SeiCampoAlterado>[];
    for (final entrada in camposItemEditavel.entries) {
      final chave = entrada.key;
      final (rotulo, chaveOriginal) = entrada.value;
      final valorAntes = _valorEfetivo(antes, chave, chaveOriginal);
      final valorDepois = _valorEfetivo(depois, chave, chaveOriginal);
      if (valorAntes != valorDepois) {
        campos.add(SeiCampoAlterado(chave: chave, rotulo: rotulo, antes: valorAntes, depois: valorDepois));
      }
    }
    if (campos.isEmpty) continue;

    final numeroPatrimonio =
        _valorEfetivo(depois, 'numero_patrimonio_corrigido', 'numero_patrimonio_original') as String? ??
        _valorEfetivo(antes, 'numero_patrimonio_corrigido', 'numero_patrimonio_original') as String?;
    final linha = (depois?['linha'] as num?)?.toInt() ?? (antes?['linha'] as num?)?.toInt();

    resultado.add(SeiDiffItem(itemId: id, numeroPatrimonio: numeroPatrimonio, linha: linha, campos: campos));
  }

  resultado.sort((a, b) => (a.linha ?? 0).compareTo(b.linha ?? 0));
  return resultado;
}

/// Valor efetivo de um campo de item dentro de um retrato antes/depois:
/// `bruto[chave] ?? bruto[chaveOriginal]` quando há par original, senão só
/// `bruto[chave]`. `bruto == null` (item ausente daquele lado) dá `null`.
Object? _valorEfetivo(Map<String, Object?>? bruto, String chave, String? chaveOriginal) {
  if (bruto == null) return null;
  final valor = bruto[chave];
  if (chaveOriginal == null) return valor;
  return valor ?? bruto[chaveOriginal];
}

List<Map<String, Object?>> _itensComo(Map<String, Object?>? dados) {
  final lista = dados?['itens'] as List<dynamic>?;
  if (lista == null) return const [];
  return lista.cast<Map<String, Object?>>();
}

/// Rótulo de exibição de uma decisão (`decisao_localizacao`/
/// `decisao_responsavel`, valores brutos do enum `documento_sei_decisao_campo`
/// no jsonb) — mesmos três estados de [SeiDecisaoCampo], reproduzidos aqui em
/// texto puro porque o valor chega como `String` bruta do jsonb, não como o
/// enum já tipado.
String rotuloDecisaoBruta(Object? valor) {
  switch (valor) {
    case 'PENDENTE':
      return 'Pendente — decisão necessária';
    case 'DEFINIDO':
      return 'Definida';
    case 'CONFIRMADO_SEM_INFORMACAO':
      return 'Confirmado sem informação';
    case null:
      return '—';
    default:
      return valor.toString();
  }
}
