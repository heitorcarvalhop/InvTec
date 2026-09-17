import 'patrimonio.dart';
import 'patrimonio_detalhe.dart';
import 'patrimonio_search_field.dart';
import 'patrimonios_resultado.dart';

abstract class PatrimonioRepository {
  Future<Patrimonio?> buscarPorId(String id);

  /// Detalhe com tipo/setor (e, quando a RLS permitir, quem cadastrou) já
  /// resolvidos — usado na tela de detalhe.
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id);

  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio);

  /// Página de patrimônios com tipo/setor já resolvidos (embed, sem N+1).
  /// [tipoId], [status], [setorId], [localizacaoId]/[semLocalizacao],
  /// [marca], [modelo], [responsavel] e os intervalos de data são filtros
  /// opcionais, todos combináveis entre si e com a busca por AND (PROMPT
  /// 9.2). Sempre resolvidos no servidor: nunca carrega a página inteira
  /// para filtrar/paginar em memória.
  ///
  /// [busca] é interpretado de acordo com [campoBusca] (PROMPT 9.1):
  /// - [PatrimonioSearchField.patrimonio]: correspondência EXATA contra
  ///   `numero_patrimonio` (nunca `ilike`/substring/similaridade — um
  ///   número de patrimônio incorreto não pode aparecer como se fosse o
  ///   patrimônio pesquisado).
  /// - [PatrimonioSearchField.numeroSerie]: busca textual controlada
  ///   (`ilike`) em `numero_serie`.
  /// - [PatrimonioSearchField.equipamentoDescricao]: `ilike` em `descricao`.
  /// - [PatrimonioSearchField.marcaModelo]: `ilike` em `marca` OU `modelo`.
  /// - [PatrimonioSearchField.responsavel]: `ilike` em `responsavel_atual`.
  /// - [PatrimonioSearchField.localizacao]: pelo nome da localização
  ///   relacionada (`localizacoes.nome`), nunca pelo setor/gerência.
  /// - [PatrimonioSearchField.tudo] (padrão): se [busca] contém só dígitos,
  ///   trata como identificador — `numero_patrimonio` OU `numero_serie`
  ///   EXATOS, nunca fuzzy/"número mais próximo"; se contém letras, busca
  ///   textual nos campos textuais (mantendo `numero_patrimonio` exato
  ///   quando aplicável).
  ///
  /// [localizacaoId] filtra por `localizacao_atual_id` exato (nunca texto).
  /// [semLocalizacao] filtra `localizacao_atual_id IS NULL` — mutuamente
  /// exclusivo com [localizacaoId] (a UI nunca envia os dois juntos).
  ///
  /// [marca], [modelo] e [responsavel] (PROMPT 9.2, seção 4) usam `ilike`
  /// case-insensitive, independentes do [campoBusca]/[busca] da busca
  /// principal — vazio (após trim) significa "filtro não aplicado".
  ///
  /// [dataCadastroDe]/[dataCadastroAte] filtram `data_cadastro`
  /// (timestamptz) por intervalo INCLUSIVO nos dois limites — a
  /// implementação decide como tratar início/fim do dia local do
  /// dispositivo (seção 5: preferir `>= início do dia` e `< início do dia
  /// seguinte`, nunca depender de `23:59:59.999`).
  /// [dataAquisicaoDe]/[dataAquisicaoAte] filtram `data_aquisicao` (date)
  /// também por intervalo inclusivo, sem ambiguidade de fuso (é só data).
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
  });

  /// Cadastra um patrimônio novo e sua movimentação inicial (ENTRADA) via
  /// a função `cadastrar_patrimonio` no Postgres, atomicamente. O
  /// responsável atual passa a ser [responsavelDestino].
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  });

  /// Atualiza somente metadados (nunca status/setor/responsável — esses só
  /// mudam por movimentação registrada, ver docs/database.md).
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  });

  /// Busca, em uma única consulta, os patrimônios cujo `numero_patrimonio`
  /// (já normalizado) esteja em [numeros] — usado pela importação de
  /// planilha para detectar existentes sem uma consulta por linha (nunca
  /// N+1, ver seção 15 da especificação de importação).
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(List<String> numeros);

  /// Entre [numerosSerie], devolve os que já pertencem a algum patrimônio
  /// cadastrado — usado para o aviso de possível duplicidade por número de
  /// série (não é `unique` no banco, então nunca bloqueia, só avisa).
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie);
}
