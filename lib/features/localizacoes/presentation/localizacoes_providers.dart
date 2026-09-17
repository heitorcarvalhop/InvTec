import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/localizacao_repository_supabase.dart';
import '../domain/localizacao.dart';

/// Localizações ATIVAS de uma gerência — usado nos seletores em cascata do
/// formulário de patrimônio e do importador (nunca oferece localização de
/// outra gerência nem inativa). `family` por `setorId`: trocar de gerência
/// troca de provider, então o seletor nunca mistura dados da gerência
/// anterior enquanto a nova carrega.
final localizacoesAtivasPorSetorProvider = FutureProvider.family<List<Localizacao>, String>((
  ref,
  setorId,
) {
  return ref.watch(localizacaoRepositoryProvider).listarPorSetor(setorId);
});

/// Todas as localizações de uma gerência (ativas e inativas) — usado na
/// tela de gestão de localizações, que precisa mostrar o histórico.
final localizacoesPorSetorProvider = FutureProvider.family<List<Localizacao>, String>((
  ref,
  setorId,
) {
  return ref.watch(localizacaoRepositoryProvider).listarPorSetor(setorId, somenteAtivas: false);
});

/// Localizações ATIVAS para o filtro "Localização" da listagem de
/// patrimônios (PROMPT 9.2, seção 2) — `family` por Setor opcional: sem
/// Setor selecionado (`null`), lista todas as localizações acessíveis; com
/// um Setor selecionado, restringe às localizações daquela gerência (nunca
/// mistura localização de outra).
final localizacoesParaFiltroProvider = FutureProvider.family<List<Localizacao>, String?>((
  ref,
  setorId,
) {
  final repository = ref.watch(localizacaoRepositoryProvider);
  return setorId == null ? repository.listarTodas() : repository.listarPorSetor(setorId);
});
