import 'text_similarity.dart';

/// Campos do InvTec que uma coluna da planilha pode ser mapeada para —
/// deliberadamente sem "status"/"setor atual"/"responsável atual" como
/// destino de UPDATE direto: esses só existem aqui como fonte para o
/// cadastro (via `cadastrar_patrimonio`) de patrimônios NOVOS.
enum ImportColumnField {
  numeroPatrimonio,
  tipo,
  marca,
  modelo,
  numeroSerie,
  descricao,
  observacao,
  setor,
  responsavel,
  origem,
  motivo,
  dataAquisicao,
  dataEntrada,

  /// Tombamento/patrimônio anterior de outra numeração — o banco não tem
  /// coluna própria para isso (seção 5 do perfil GETEC); quando mapeado, o
  /// valor é preservado em `observacao` em vez de descartado.
  tombamentoAnterior,
}

extension ImportColumnFieldLabel on ImportColumnField {
  String get label {
    switch (this) {
      case ImportColumnField.numeroPatrimonio:
        return 'Número patrimonial';
      case ImportColumnField.tipo:
        return 'Tipo';
      case ImportColumnField.marca:
        return 'Marca';
      case ImportColumnField.modelo:
        return 'Modelo';
      case ImportColumnField.numeroSerie:
        return 'Número de série';
      case ImportColumnField.descricao:
        return 'Descrição';
      case ImportColumnField.observacao:
        return 'Observação';
      case ImportColumnField.setor:
        return 'Setor / Localização';
      case ImportColumnField.responsavel:
        return 'Responsável';
      case ImportColumnField.origem:
        return 'Origem';
      case ImportColumnField.motivo:
        return 'Motivo';
      case ImportColumnField.dataAquisicao:
        return 'Data de aquisição';
      case ImportColumnField.dataEntrada:
        return 'Data da entrada';
      case ImportColumnField.tombamentoAnterior:
        return 'Tombamento anterior';
    }
  }
}

/// Heurísticas de reconhecimento automático (seção 9 da especificação):
/// só geram uma SUGESTÃO inicial de mapeamento, sempre visível e editável
/// pelo usuário antes da análise. Nenhuma IA externa é usada.
const _aliasesPorCampo = <ImportColumnField, List<String>>{
  ImportColumnField.numeroPatrimonio: [
    'patrimonio',
    'n patrimonio',
    'no patrimonio',
    'numero patrimonio',
    'numero patrimonial',
    'numero do patrimonio',
    'n patr',
    'no patr',
    'patr',
    'tombamento',
    'numero de tombamento',
    'plaqueta',
    'numero da plaqueta',
    'codigo patrimonial',
  ],
  ImportColumnField.numeroSerie: [
    'serial',
    'n serie',
    'numero de serie',
    'numero serie',
    'serial number',
    'ns',
    'n/s',
  ],
  ImportColumnField.tipo: ['tipo', 'equipamento', 'categoria', 'tipo de equipamento', 'classe'],
  ImportColumnField.marca: ['marca', 'fabricante'],
  ImportColumnField.modelo: ['modelo'],
  ImportColumnField.descricao: ['descricao', 'especificacao', 'especificacoes'],
  ImportColumnField.observacao: ['observacao', 'obs', 'nota', 'notas'],
  ImportColumnField.setor: [
    'setor',
    'local',
    'localizacao',
    'unidade',
    'departamento',
    'lotacao',
  ],
  ImportColumnField.responsavel: ['responsavel', 'usuario', 'colaborador'],
  ImportColumnField.origem: ['origem', 'setor de origem', 'procedencia'],
  ImportColumnField.motivo: ['motivo', 'justificativa'],
  ImportColumnField.dataAquisicao: [
    'data de aquisicao',
    'data aquisicao',
    'aquisicao',
    'data da compra',
    'data compra',
  ],
  ImportColumnField.dataEntrada: [
    'data de entrada',
    'data entrada',
    'data do cadastro',
    'data cadastro',
  ],
  ImportColumnField.tombamentoAnterior: [
    'tomb anterior',
    'tombamento anterior',
    'patrimonio anterior',
    'tombo anterior',
    'plaqueta anterior',
  ],
};

/// Sugere o campo do InvTec mais provável para o texto de cabeçalho
/// [cabecalho], ou `null` se nada bater — usado só como ponto de partida no
/// passo de mapeamento de colunas.
ImportColumnField? sugerirCampoPorCabecalho(String cabecalho) {
  final normalizado = normalizarTextoComparacao(cabecalho);
  if (normalizado.isEmpty) return null;

  for (final entry in _aliasesPorCampo.entries) {
    if (entry.value.contains(normalizado)) return entry.key;
  }
  for (final entry in _aliasesPorCampo.entries) {
    for (final alias in entry.value) {
      if (normalizado.contains(alias)) return entry.key;
    }
  }
  return null;
}
