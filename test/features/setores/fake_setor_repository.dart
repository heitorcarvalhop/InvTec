import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/setores/domain/setor.dart';
import 'package:invtec/features/setores/domain/setor_repository.dart';

/// Fake em memória de [SetorRepository], sem nenhuma chamada de rede —
/// usado para testar a página de Setores isolada do Supabase real. Imita
/// as mesmas mensagens amigáveis que `mapSetorErrorMessage` produziria a
/// partir dos erros reais do banco (nome duplicado, setor em uso).
class FakeSetorRepository implements SetorRepository {
  FakeSetorRepository({List<Setor>? setores, Set<String>? idsEmUso})
    : _setores = [...?setores],
      _idsEmUso = idsEmUso ?? const {};

  final List<Setor> _setores;
  final Set<String> _idsEmUso;

  int criarCallCount = 0;
  int atualizarCallCount = 0;
  int alterarAtivoCallCount = 0;

  @override
  Future<List<Setor>> listarAtivos() async {
    return _setores.where((s) => s.ativo).toList();
  }

  @override
  Future<List<Setor>> listar({
    String? busca,
    int limit = 50,
    int offset = 0,
  }) async {
    Iterable<Setor> resultado = _setores;

    final termo = busca?.trim().toLowerCase();
    if (termo != null && termo.isNotEmpty) {
      resultado = resultado.where(
        (s) =>
            s.nome.toLowerCase().contains(termo) ||
            (s.sigla?.toLowerCase().contains(termo) ?? false),
      );
    }

    final lista = resultado.toList()
      ..sort((a, b) {
        if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

    return lista.skip(offset).take(limit).toList();
  }

  @override
  Future<Setor> criar({
    required String nome,
    String? sigla,
    String? descricao,
  }) async {
    criarCallCount++;
    final nomeNormalizado = nome.trim();

    if (_setores.any(
      (s) => s.nome.toLowerCase() == nomeNormalizado.toLowerCase(),
    )) {
      throw const AppException('Já existe um setor com este nome.');
    }

    final novo = Setor(
      id: 'novo-${_setores.length + 1}',
      nome: nomeNormalizado,
      sigla: _semEspacosOuNulo(sigla),
      descricao: _semEspacosOuNulo(descricao),
      ativo: true,
      criadoEm: DateTime.now(),
    );
    _setores.add(novo);
    return novo;
  }

  @override
  Future<Setor> atualizar({
    required String id,
    required String nome,
    String? sigla,
    String? descricao,
  }) async {
    atualizarCallCount++;
    final index = _setores.indexWhere((s) => s.id == id);
    final atualizado = Setor(
      id: id,
      nome: nome.trim(),
      sigla: _semEspacosOuNulo(sigla),
      descricao: _semEspacosOuNulo(descricao),
      ativo: _setores[index].ativo,
      criadoEm: _setores[index].criadoEm,
    );
    _setores[index] = atualizado;
    return atualizado;
  }

  @override
  Future<Setor> alterarAtivo({required String id, required bool ativo}) async {
    alterarAtivoCallCount++;
    if (!ativo && _idsEmUso.contains(id)) {
      throw const AppException(
        'Este setor possui patrimônios vinculados e não pode ser desativado.',
      );
    }

    final index = _setores.indexWhere((s) => s.id == id);
    final atualizado = _setores[index].copyWith(ativo: ativo);
    _setores[index] = atualizado;
    return atualizado;
  }
}

String? _semEspacosOuNulo(String? valor) {
  final normalizado = valor?.trim();
  return (normalizado == null || normalizado.isEmpty) ? null : normalizado;
}
