import 'localizacao.dart';

abstract class LocalizacaoRepository {
  /// Localizações de uma gerência (seção 39) — usado no seletor em cascata
  /// do formulário/importador e na tela de gestão. [somenteAtivas] é `true`
  /// para seletores de novo cadastro/movimentação (nunca oferecer uma
  /// localização inativa como destino); a tela de gestão usa `false` para
  /// mostrar o histórico completo.
  Future<List<Localizacao>> listarPorSetor(
    String setorId, {
    bool somenteAtivas = true,
  });

  /// Todas as localizações acessíveis ao usuário, de qualquer gerência —
  /// usado pelo filtro "Localização" da listagem de patrimônios (PROMPT
  /// 9.2) quando nenhum Setor específico está selecionado. A leitura já é
  /// filtrada pela RLS (mesmos quatro perfis que leem `setores`), então
  /// não há necessidade de restringir por usuário aqui.
  Future<List<Localizacao>> listarTodas({bool somenteAtivas = true});

  Future<Localizacao?> buscarPorId(String id);

  /// Cria uma localização nova. Nasce ativa (padrão do banco). Requer
  /// ADMIN/GESTOR — RLS decide, esta chamada só reflete o resultado.
  Future<Localizacao> criar({
    required String setorId,
    required String nome,
    String? sigla,
  });

  /// Atualiza nome/sigla de uma localização existente — nunca `setorId`
  /// (imutável depois de criada, ver seção 5 da especificação; o próprio
  /// banco rejeita a tentativa).
  Future<Localizacao> atualizar({
    required String id,
    required String nome,
    String? sigla,
  });

  /// Ativa ou desativa (nunca DELETE). O banco rejeita desativar uma
  /// localização com patrimônio não baixado vinculado.
  Future<Localizacao> alterarAtivo({required String id, required bool ativo});
}
