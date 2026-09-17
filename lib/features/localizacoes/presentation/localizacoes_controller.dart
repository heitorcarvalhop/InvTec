import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/localizacao_repository_supabase.dart';
import '../domain/localizacao.dart';

/// Lista de localizações de UMA gerência (tela de gestão) — ativas e
/// inativas, igual à filosofia de `SetoresController`. `family` por
/// `setorId`: cada gerência tem seu próprio controller/estado.
final localizacoesControllerProvider =
    AsyncNotifierProvider.family<LocalizacoesController, List<Localizacao>, String>(
      LocalizacoesController.new,
    );

class LocalizacoesController extends AsyncNotifier<List<Localizacao>> {
  LocalizacoesController(this.setorId);

  final String setorId;

  @override
  Future<List<Localizacao>> build() async {
    final repository = ref.watch(localizacaoRepositoryProvider);
    final lista = await repository.listarPorSetor(setorId, somenteAtivas: false);
    return [...lista]..sort((a, b) {
      if (a.ativo != b.ativo) return a.ativo ? -1 : 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> criar({required String nome, String? sigla}) async {
    await ref.read(localizacaoRepositoryProvider).criar(setorId: setorId, nome: nome, sigla: sigla);
    ref.invalidateSelf();
  }

  Future<void> atualizar({required String id, required String nome, String? sigla}) async {
    await ref.read(localizacaoRepositoryProvider).atualizar(id: id, nome: nome, sigla: sigla);
    ref.invalidateSelf();
  }

  Future<void> alterarAtivo({required String id, required bool ativo}) async {
    await ref.read(localizacaoRepositoryProvider).alterarAtivo(id: id, ativo: ativo);
    ref.invalidateSelf();
  }
}
