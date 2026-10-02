/// Campos pelos quais a listagem geral de movimentações pode ser ordenada
/// no servidor — ver [MovimentacaoRepository.listar]. Vocabulário fechado,
/// nunca um nome de coluna vindo direto da UI.
///
/// "Equipamento" (tipo do patrimônio) foi deliberadamente deixado de fora:
/// exigiria ordenar pelo relacionamento `patrimonios.tipos_patrimonio`, dois
/// níveis de embed do Postgrest — um recurso sem suporte documentado com
/// certeza (ao contrário de um nível, usado por [patrimonio]/[origem]/
/// [destino] abaixo), e esta tarefa não acessa o Supabase real para
/// verificar o comportamento. Ver relatório.
enum MovimentacaoOrdenacaoCampo {
  data,
  patrimonio,
  tipo,
  origem,
  destino;

  /// Rótulo em PT-BR exibido no cabeçalho ordenável/seletor "Ordenar por".
  String get label {
    switch (this) {
      case MovimentacaoOrdenacaoCampo.data:
        return 'Data';
      case MovimentacaoOrdenacaoCampo.patrimonio:
        return 'Patrimônio';
      case MovimentacaoOrdenacaoCampo.tipo:
        return 'Tipo';
      case MovimentacaoOrdenacaoCampo.origem:
        return 'Origem';
      case MovimentacaoOrdenacaoCampo.destino:
        return 'Destino';
    }
  }
}
