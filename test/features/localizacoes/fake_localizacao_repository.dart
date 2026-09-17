import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/localizacoes/domain/localizacao_repository.dart';

/// Fake em memória de [LocalizacaoRepository], sem nenhuma chamada de rede.
class FakeLocalizacaoRepository implements LocalizacaoRepository {
  FakeLocalizacaoRepository({List<Localizacao>? localizacoes}) : _localizacoes = [...?localizacoes];

  final List<Localizacao> _localizacoes;

  int criarCallCount = 0;
  int atualizarCallCount = 0;
  int alterarAtivoCallCount = 0;

  /// Quantas vezes `listarPorSetor` foi chamado — usado para provar que a
  /// resolução de localizações da importação GETEC carrega a lista em lote
  /// UMA vez (nunca por linha/patrimônio, ver PROMPT 8.9 "proibido N+1").
  int listarPorSetorCallCount = 0;

  @override
  Future<List<Localizacao>> listarPorSetor(String setorId, {bool somenteAtivas = true}) async {
    listarPorSetorCallCount++;
    return _localizacoes
        .where((l) => l.setorId == setorId && (!somenteAtivas || l.ativo))
        .toList();
  }

  @override
  Future<List<Localizacao>> listarTodas({bool somenteAtivas = true}) async {
    return _localizacoes.where((l) => !somenteAtivas || l.ativo).toList();
  }

  @override
  Future<Localizacao?> buscarPorId(String id) async {
    for (final l in _localizacoes) {
      if (l.id == id) return l;
    }
    return null;
  }

  @override
  Future<Localizacao> criar({required String setorId, required String nome, String? sigla}) async {
    criarCallCount++;
    final nova = Localizacao(
      id: 'nova-${_localizacoes.length + 1}',
      setorId: setorId,
      nome: nome.trim(),
      sigla: sigla,
      ativo: true,
      criadoEm: DateTime.now(),
    );
    _localizacoes.add(nova);
    return nova;
  }

  @override
  Future<Localizacao> atualizar({required String id, required String nome, String? sigla}) async {
    atualizarCallCount++;
    final index = _localizacoes.indexWhere((l) => l.id == id);
    final atual = _localizacoes[index];
    final atualizada = Localizacao(
      id: atual.id,
      setorId: atual.setorId,
      nome: nome.trim(),
      sigla: sigla,
      ativo: atual.ativo,
      criadoEm: atual.criadoEm,
    );
    _localizacoes[index] = atualizada;
    return atualizada;
  }

  @override
  Future<Localizacao> alterarAtivo({required String id, required bool ativo}) async {
    alterarAtivoCallCount++;
    final index = _localizacoes.indexWhere((l) => l.id == id);
    final atual = _localizacoes[index];
    final atualizada = Localizacao(
      id: atual.id,
      setorId: atual.setorId,
      nome: atual.nome,
      sigla: atual.sigla,
      ativo: ativo,
      criadoEm: atual.criadoEm,
    );
    _localizacoes[index] = atualizada;
    return atualizada;
  }
}
