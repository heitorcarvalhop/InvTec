import 'sei_item_plano.dart';

/// Plano de execução em memória, somente leitura — NUNCA persistido, nunca
/// enviado a `registrarMovimentacao`. Existe só para dar ao usuário uma
/// prévia exata do que uma futura confirmação (que esta versão não
/// implementa) enviaria à RPC.
class SeiPlanoExecucao {
  const SeiPlanoExecucao({required this.itens});

  /// Cada item aqui é um item SELECIONADO e elegível — nunca inclui
  /// bloqueados, avisos de confiança média não confirmados ou linhas
  /// desatualizadas pela revalidação (ver `construirPlanoExecucao`). Uma
  /// lista vazia é um plano válido (nada selecionado ainda).
  final List<SeiItemPlano> itens;

  int get totalItens => itens.length;
}
