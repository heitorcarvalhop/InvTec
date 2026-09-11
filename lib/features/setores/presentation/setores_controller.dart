import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/setor_repository_supabase.dart';
import '../domain/setor.dart';
import '../domain/setor_repository.dart';

final setoresControllerProvider =
    AsyncNotifierProvider<SetoresController, List<Setor>>(
      SetoresController.new,
    );

/// Lista de setores da tela de gestão, com busca com debounce. Ativos
/// primeiro, depois por nome — ver [SetorRepository.listar]. Ações de
/// escrita (criar/atualizar/alterarAtivo) também vivem aqui para recarregar
/// a lista automaticamente após sucesso.
class SetoresController extends AsyncNotifier<List<Setor>> {
  Timer? _debounce;
  String _busca = '';

  @override
  Future<List<Setor>> build() async {
    ref.onDispose(() => _debounce?.cancel());
    final repository = ref.watch(setorRepositoryProvider);
    return repository.listar(busca: _busca);
  }

  /// Atualiza a busca após um pequeno atraso, para não disparar uma
  /// consulta a cada tecla digitada.
  void buscar(String texto) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _busca = texto.trim();
      ref.invalidateSelf();
    });
  }

  Future<void> recarregar() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> criar({
    required String nome,
    String? sigla,
    String? descricao,
  }) async {
    await ref
        .read(setorRepositoryProvider)
        .criar(nome: nome, sigla: sigla, descricao: descricao);
    ref.invalidateSelf();
  }

  Future<void> atualizar({
    required String id,
    required String nome,
    String? sigla,
    String? descricao,
  }) async {
    await ref
        .read(setorRepositoryProvider)
        .atualizar(id: id, nome: nome, sigla: sigla, descricao: descricao);
    ref.invalidateSelf();
  }

  Future<void> alterarAtivo({required String id, required bool ativo}) async {
    await ref.read(setorRepositoryProvider).alterarAtivo(id: id, ativo: ativo);
    ref.invalidateSelf();
  }
}
