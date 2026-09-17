/// Campo em que a busca da tela de patrimônios é aplicada (PROMPT 9.1) —
/// nunca strings mágicas espalhadas pela UI/repository. [tudo] é o modo
/// padrão; os demais restringem a busca a um único critério, com
/// [patrimonio] sendo o único que exige correspondência EXATA (nunca
/// `ilike`/substring/similaridade — ver [PatrimonioRepository.listar]).
enum PatrimonioSearchField {
  tudo,
  patrimonio,
  numeroSerie,
  equipamentoDescricao,
  marcaModelo,
  responsavel,
  localizacao;

  /// Rótulo em PT-BR exibido no seletor — o enum técnico nunca aparece
  /// diretamente para o usuário.
  String get label {
    switch (this) {
      case PatrimonioSearchField.tudo:
        return 'Tudo';
      case PatrimonioSearchField.patrimonio:
        return 'Patrimônio';
      case PatrimonioSearchField.numeroSerie:
        return 'Número de série';
      case PatrimonioSearchField.equipamentoDescricao:
        return 'Equipamento / Descrição';
      case PatrimonioSearchField.marcaModelo:
        return 'Marca / Modelo';
      case PatrimonioSearchField.responsavel:
        return 'Responsável';
      case PatrimonioSearchField.localizacao:
        return 'Localização';
    }
  }

  /// Dica exibida no campo de texto — só para orientar o usuário sobre o
  /// que o modo selecionado pesquisa; não afeta a consulta em si.
  String get dica {
    switch (this) {
      case PatrimonioSearchField.tudo:
        return 'Buscar por número, série, marca, modelo, responsável...';
      case PatrimonioSearchField.patrimonio:
        return 'Número de patrimônio exato';
      case PatrimonioSearchField.numeroSerie:
        return 'Número de série';
      case PatrimonioSearchField.equipamentoDescricao:
        return 'Descrição do equipamento';
      case PatrimonioSearchField.marcaModelo:
        return 'Marca ou modelo';
      case PatrimonioSearchField.responsavel:
        return 'Nome do responsável';
      case PatrimonioSearchField.localizacao:
        return 'Nome da localização';
    }
  }
}
