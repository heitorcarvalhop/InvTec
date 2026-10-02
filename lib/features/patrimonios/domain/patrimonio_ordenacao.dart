/// Campos pelos quais a listagem de patrimônios pode ser ordenada no
/// servidor — ver [PatrimonioRepository.listar]. Nunca passar um nome de
/// coluna vindo direto da UI para a consulta: este enum é o único
/// vocabulário permitido, mapeado para coluna/relacionamento real dentro do
/// repositório (nunca o contrário).
enum PatrimonioOrdenacaoCampo {
  numeroPatrimonio,
  equipamento,
  marca,
  setor,
  localizacao,
  status,
  criadoEm;

  /// Rótulo em PT-BR exibido no cabeçalho ordenável/seletor "Ordenar por" —
  /// o enum técnico nunca aparece diretamente para o usuário.
  String get label {
    switch (this) {
      case PatrimonioOrdenacaoCampo.numeroPatrimonio:
        return 'Patrimônio';
      case PatrimonioOrdenacaoCampo.equipamento:
        return 'Equipamento';
      case PatrimonioOrdenacaoCampo.marca:
        return 'Marca';
      case PatrimonioOrdenacaoCampo.setor:
        return 'Setor';
      case PatrimonioOrdenacaoCampo.localizacao:
        return 'Localização';
      case PatrimonioOrdenacaoCampo.status:
        return 'Status';
      case PatrimonioOrdenacaoCampo.criadoEm:
        return 'Data de cadastro';
    }
  }
}
