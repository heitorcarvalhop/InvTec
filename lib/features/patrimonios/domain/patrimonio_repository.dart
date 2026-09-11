import 'patrimonio.dart';
import 'patrimonio_detalhe.dart';
import 'patrimonios_resultado.dart';

abstract class PatrimonioRepository {
  Future<Patrimonio?> buscarPorId(String id);

  /// Detalhe com tipo/setor (e, quando a RLS permitir, quem cadastrou) já
  /// resolvidos — usado na tela de detalhe.
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id);

  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio);

  /// Página de patrimônios com tipo/setor já resolvidos (embed, sem N+1).
  /// [busca] filtra por número de patrimônio/série/marca/modelo (server-side,
  /// nunca carrega a tabela inteira); [tipoId], [status] e [setorId] são
  /// filtros opcionais combináveis com a busca.
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
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
