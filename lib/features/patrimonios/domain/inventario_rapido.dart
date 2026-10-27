import 'patrimonio_detalhe.dart';
import 'patrimonio_scanner.dart';
import 'tombamento_normalizacao.dart';

/// Extensão de [ScannerResultadoTipo] para o contexto de uma SESSÃO de
/// conferência (Inventário Rápido) — mesma classificação do scanner,
/// nunca uma segunda taxonomia paralela: só nomeia "o que não é uma
/// correspondência única já resolvida" como PENDÊNCIA, para a UI/relatório
/// nunca precisarem repetir essa lista de casos manualmente.
extension ScannerResultadoTipoInventarioX on ScannerResultadoTipo {
  bool get ePendenciaDeInventario =>
      this != ScannerResultadoTipo.encontradoAtual &&
      this != ScannerResultadoTipo.encontradoAnterior;
}

/// Uma linha da sessão de Inventário Rápido (Android, protótipo local) —
/// existe SÓ em memória enquanto a sessão estiver aberta; nunca grava nada
/// no Supabase (nem o próprio registro da leitura, nem qualquer
/// atualização de tombamento/setor/localização/responsável do
/// patrimônio).
class InventarioLeitura {
  const InventarioLeitura({
    required this.id,
    required this.chaveDedup,
    required this.resultado,
    required this.lidoEm,
  });

  /// Identidade ESTÁVEL da linha (nunca muda, mesmo quando [resultado] é
  /// substituído por uma releitura/"tentar de novo") — é o que permite
  /// remover ou corrigir UMA linha específica sem ambiguidade.
  final String id;

  /// Chave de deduplicação — `"patrimonio:<id>"` quando [resultado] já é
  /// uma correspondência única (atual ou anterior), ou
  /// `"codigo:<chave normalizada>"` nos demais casos (ambíguo/não
  /// encontrado/inválido/acesso insuficiente/falha de consulta). Duas
  /// leituras com a MESMA chave nunca geram duas linhas — [registrarLeitura]
  /// atualiza a linha existente em vez de duplicar (regra do pedido:
  /// "evitar contabilizar o mesmo patrimônio duas vezes", estendida aqui
  /// para também nunca duplicar o mesmo código problemático).
  final String chaveDedup;

  final ScannerResultado resultado;
  final DateTime lidoEm;

  String get codigoLido => resultado.codigoLido;
  ScannerResultadoTipo get status => resultado.tipo;
  bool get ePendencia => status.ePendenciaDeInventario;

  /// Não nulo exatamente quando [status] é uma correspondência única
  /// (atual ou anterior) — nunca em ambíguo (2+) nem em qualquer
  /// pendência (0).
  PatrimonioDetalhe? get patrimonioUnico =>
      resultado.encontrados.length == 1 ? resultado.encontrados.single : null;
}

/// Chave de deduplicação de um [ScannerResultado] — ver [InventarioLeitura.chaveDedup].
String chaveDedupDeResultado(ScannerResultado resultado) {
  if (!resultado.tipo.ePendenciaDeInventario) {
    return 'patrimonio:${resultado.encontrados.single.patrimonio.id}';
  }
  final chave = normalizarTombamentoParaComparacao(resultado.codigoLido).chaveComparacao;
  return 'codigo:${chave ?? resultado.codigoLido.trim().toUpperCase()}';
}

/// Registra uma nova leitura na lista — se já existir uma linha com a
/// MESMA [InventarioLeitura.chaveDedup] (o mesmo patrimônio já capturado,
/// ou o mesmo código problemático já registrado), ATUALIZA aquela linha
/// (mesmo [id], novo [resultado]/[lidoEm]) em vez de duplicar. Preserva a
/// posição original da linha na lista.
List<InventarioLeitura> registrarLeitura({
  required List<InventarioLeitura> leituras,
  required ScannerResultado resultado,
  required DateTime agora,
  required String Function() gerarId,
}) {
  final chave = chaveDedupDeResultado(resultado);
  final index = leituras.indexWhere((l) => l.chaveDedup == chave);
  final nova = InventarioLeitura(
    id: index >= 0 ? leituras[index].id : gerarId(),
    chaveDedup: chave,
    resultado: resultado,
    lidoEm: agora,
  );
  if (index < 0) return [...leituras, nova];
  final copia = [...leituras];
  copia[index] = nova;
  return copia;
}

/// Remove a linha [id] — usada pela ação "remover" (revisão manual da
/// sessão). `id` que não existir mais é um no-op (nunca lança).
List<InventarioLeitura> removerLeituraPorId(
  List<InventarioLeitura> leituras,
  String id,
) => leituras.where((l) => l.id != id).toList();

/// "Corrigir"/"tentar de novo" a linha [id] com um [resultado] atualizado
/// (nova consulta do MESMO código lido) — se o novo resultado colidir com
/// a [InventarioLeitura.chaveDedup] de OUTRA linha já existente (ex.: a
/// releitura agora resolve para um patrimônio que outra linha já
/// capturou), a linha [id] é removida e a linha colidida é quem recebe a
/// atualização — nunca duas linhas para o mesmo patrimônio, mesmo depois
/// de uma correção manual. `id` que não existir mais é um no-op.
List<InventarioLeitura> atualizarLeitura({
  required List<InventarioLeitura> leituras,
  required String id,
  required ScannerResultado resultado,
  required DateTime agora,
}) {
  final indexDestino = leituras.indexWhere((l) => l.id == id);
  if (indexDestino < 0) return leituras;

  final chave = chaveDedupDeResultado(resultado);
  final indexColisao = leituras.indexWhere(
    (l) => l.chaveDedup == chave && l.id != id,
  );
  final atualizada = InventarioLeitura(
    id: indexColisao >= 0 ? leituras[indexColisao].id : id,
    chaveDedup: chave,
    resultado: resultado,
    lidoEm: agora,
  );

  if (indexColisao < 0) {
    final copia = [...leituras];
    copia[indexDestino] = atualizada;
    return copia;
  }
  final copia = [...leituras];
  copia[indexColisao] = atualizada;
  copia.removeAt(indexDestino);
  return copia;
}

/// `true` quando a localização ATUAL cadastrada de [leitura.patrimonioUnico]
/// difere de [localizacaoSelecionadaId] (a localização que esta sessão de
/// conferência está auditando) — SÓ compara, nunca atualiza nada. `false`
/// para qualquer pendência (sem patrimônio único para comparar).
bool leituraDivergeDaLocalizacao(
  InventarioLeitura leitura,
  String localizacaoSelecionadaId,
) {
  final patrimonio = leitura.patrimonioUnico;
  if (patrimonio == null) return false;
  return patrimonio.patrimonio.localizacaoAtualId != localizacaoSelecionadaId;
}
