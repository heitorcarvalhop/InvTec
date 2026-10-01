/// Um valor extraído do PDF que a GETEC pode corrigir manualmente antes da
/// primeira conclusão (PROMPT 11.3, seção 13) — guarda os dois lados
/// SEMPRE: nunca sobrescreve [original] com [corrigido] para "fazer parecer
/// que o parser acertou de primeira". [valorEfetivo] é o que a UI/plano
/// deve usar; [original] fica preservado só para auditoria/consulta.
class SeiValorCorrigivel<T> {
  const SeiValorCorrigivel({
    required this.original,
    this.corrigido,
    this.corrigidoPorId,
    this.corrigidoPorNome,
    this.corrigidoEm,
    this.motivoCorrecao,
  });

  final T? original;
  final T? corrigido;
  final String? corrigidoPorId;
  final String? corrigidoPorNome;
  final DateTime? corrigidoEm;
  final String? motivoCorrecao;

  bool get foiCorrigido => corrigido != null;

  /// Valor que qualquer tela ou cálculo posterior deve usar — a correção
  /// humana sempre prevalece sobre o que o parser leu, mas nunca apaga o
  /// [original].
  T? get valorEfetivo => corrigido ?? original;

  SeiValorCorrigivel<T> corrigir({
    required T novoValor,
    required String corrigidoPorId,
    required String corrigidoPorNome,
    required DateTime corrigidoEm,
    required String motivo,
  }) {
    return SeiValorCorrigivel<T>(
      original: original,
      corrigido: novoValor,
      corrigidoPorId: corrigidoPorId,
      corrigidoPorNome: corrigidoPorNome,
      corrigidoEm: corrigidoEm,
      motivoCorrecao: motivo,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeiValorCorrigivel<T> &&
      other.original == original &&
      other.corrigido == corrigido &&
      other.corrigidoPorId == corrigidoPorId &&
      other.corrigidoEm == corrigidoEm &&
      other.motivoCorrecao == motivoCorrecao;

  @override
  int get hashCode => Object.hash(original, corrigido, corrigidoPorId, corrigidoEm, motivoCorrecao);
}
