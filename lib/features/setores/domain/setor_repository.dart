import 'setor.dart';

abstract class SetorRepository {
  /// Setores ativos, usados em seletores/formulários de movimentação.
  Future<List<Setor>> listarAtivos();

  /// Lista para a tela de gestão de setores: ativos primeiro, depois por
  /// nome. Inclui inativos (histórico não é escondido). [busca] filtra por
  /// nome/sigla no servidor; nunca carrega a tabela inteira de uma vez.
  Future<List<Setor>> listar({String? busca, int limit = 50, int offset = 0});

  /// Cria um setor novo. Nasce ativo (padrão do banco). Requer
  /// ADMIN/GESTOR — RLS decide, esta chamada só reflete o resultado.
  Future<Setor> criar({required String nome, String? sigla, String? descricao});

  /// Atualiza nome/sigla/descrição de um setor existente. Nunca recria o
  /// registro (setores podem estar referenciados por movimentações
  /// históricas).
  Future<Setor> atualizar({
    required String id,
    required String nome,
    String? sigla,
    String? descricao,
  });

  /// Ativa ou desativa um setor (nunca DELETE). O banco rejeita desativar
  /// um setor com patrimônio não baixado vinculado.
  Future<Setor> alterarAtivo({required String id, required bool ativo});
}
