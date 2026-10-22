/// Normalização de TOMBAMENTO para fins de COMPARAÇÃO/conciliação — nunca
/// para exibição, nunca para regravar o valor armazenado. Ver
/// [normalizarNumeroPatrimonio] em `patrimonio.dart` para a normalização de
/// IDENTIDADE usada pelo banco (trim + maiúsculas, preserva zeros à
/// esquerda) — as duas funções coexistem de propósito: esta aqui decide
/// "são o mesmo número patrimonial?", aquela decide "qual o valor a
/// gravar?". Nenhuma das duas jamais reescreve um tombamento já existente.
///
/// Regra de negócio confirmada pelo responsável pelo sistema: zeros à
/// ESQUERDA de um tombamento exclusivamente numérico não fazem parte da
/// identificação efetiva do bem — `"000123456"`, `"00123456"` e `"123456"`
/// são o MESMO número patrimonial. Zeros internos e finais são
/// preservados (`"1200"` segue `"1200"`, nunca `"12"`).
///
/// Usada por: conciliação patrimonial, busca (Fase 4), validação de novos
/// tombamentos e de duplicidade (Fase 5), histórico de tombamentos
/// (Fase 3), importação futura (Parte D). Nunca aplicada a `numero_serie`
/// (que pode conter letras/hífens e nunca perde zeros).
library;

/// Classificação de um tombamento após a tentativa de normalização —
/// existe para que vazio/só-zeros/não-numérico sejam tratados
/// EXPLICITAMENTE por quem compara (regra 9 do pedido), em vez de vazarem
/// como um valor de comparação qualquer.
enum TombamentoTipo {
  /// Só dígitos, com pelo menos um dígito diferente de zero — a chave de
  /// comparação é o valor sem os zeros iniciais.
  numerico,

  /// Contém ao menos um caractere que não é dígito (ex.: `"TI-769"`) — a
  /// regra de zeros à esquerda é EXCLUSIVA de tombamentos só numéricos
  /// (regra 1 do pedido), então aqui a chave de comparação é o próprio
  /// valor (já em maiúsculas/trim), sem remover nada.
  naoNumerico,

  /// Vazio (depois de trim) — nunca gera correspondência com nada, nem
  /// com outro valor vazio.
  vazio,

  /// Só zeros (ex.: `"0000000"`) — tratado como inválido, não como
  /// "o número zero": na prática é equivalente a não ter tombamento
  /// informado, e NUNCA deve combinar com outro "somente zeros" (regra 9:
  /// "sem permitir correspondência indiscriminada").
  somenteZeros,
}

/// Resultado da normalização — [original] é só para exibição/relatório
/// (nunca comparar por ele); [chaveComparacao] é o que [saoEquivalentes]
/// usa, e é `null` exatamente quando [tipo] é [TombamentoTipo.vazio] ou
/// [TombamentoTipo.somenteZeros] (nunca combina com nada).
class TombamentoNormalizado {
  const TombamentoNormalizado({
    required this.original,
    required this.chaveComparacao,
    required this.tipo,
  });

  final String? original;
  final String? chaveComparacao;
  final TombamentoTipo tipo;

  @override
  String toString() =>
      'TombamentoNormalizado(original: $original, chaveComparacao: $chaveComparacao, tipo: $tipo)';
}

final RegExp _apenasDigitos = RegExp(r'^\d+$');
final RegExp _zerosIniciais = RegExp(r'^0+');

/// Normaliza [valor] para fins de comparação — nunca converte para `int`/
/// `double` (regra 2 do pedido): a remoção de zeros à esquerda é sempre
/// feita como manipulação de texto.
TombamentoNormalizado normalizarTombamentoParaComparacao(String? valor) {
  final semEspacos = valor?.trim();
  if (semEspacos == null || semEspacos.isEmpty) {
    return const TombamentoNormalizado(
      original: null,
      chaveComparacao: null,
      tipo: TombamentoTipo.vazio,
    );
  }

  if (!_apenasDigitos.hasMatch(semEspacos)) {
    return TombamentoNormalizado(
      original: semEspacos,
      chaveComparacao: semEspacos.toUpperCase(),
      tipo: TombamentoTipo.naoNumerico,
    );
  }

  final semZerosIniciais = semEspacos.replaceFirst(_zerosIniciais, '');
  if (semZerosIniciais.isEmpty) {
    // Só zeros: "0", "00", "000000" etc. — nunca uma chave válida.
    return TombamentoNormalizado(
      original: semEspacos,
      chaveComparacao: null,
      tipo: TombamentoTipo.somenteZeros,
    );
  }

  return TombamentoNormalizado(
    original: semEspacos,
    chaveComparacao: semZerosIniciais,
    tipo: TombamentoTipo.numerico,
  );
}

/// Dois tombamentos representam o MESMO número patrimonial quando suas
/// chaves de comparação coincidem — `false` sempre que qualquer um dos
/// dois for vazio ou só-zeros (nunca combina "nenhum valor" com "nenhum
/// valor").
bool tombamentosSaoEquivalentes(String? a, String? b) {
  final chaveA = normalizarTombamentoParaComparacao(a).chaveComparacao;
  final chaveB = normalizarTombamentoParaComparacao(b).chaveComparacao;
  if (chaveA == null || chaveB == null) return false;
  return chaveA == chaveB;
}
