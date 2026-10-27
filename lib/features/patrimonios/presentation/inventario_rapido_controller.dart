import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/patrimonio_repository_supabase.dart';
import '../domain/inventario_rapido.dart';
import '../domain/patrimonio_scanner.dart';

/// Estado de uma sessão de Inventário Rápido — existe SÓ em memória
/// (nunca persistida; "sessão temporária" do pedido). `null` enquanto
/// nenhuma localização foi escolhida ainda (ver [InventarioRapidoController.build]).
class InventarioRapidoEstado {
  const InventarioRapidoEstado({
    required this.localizacaoId,
    required this.localizacaoNome,
    this.leituras = const [],
    this.processando = false,
  });

  final String localizacaoId;
  final String localizacaoNome;
  final List<InventarioLeitura> leituras;

  /// `true` entre o momento em que um código foi lido e a resposta do
  /// servidor chegar — mesma trava de [ScannerResultadoTipo] (nunca
  /// dispara uma segunda consulta enquanto uma já está em voo).
  final bool processando;

  int get totalLeituras => leituras.length;
  int get totalEncontrados => leituras.where((l) => !l.ePendencia).length;
  int get totalPendencias => leituras.where((l) => l.ePendencia).length;

  InventarioRapidoEstado copiarCom({
    List<InventarioLeitura>? leituras,
    bool? processando,
  }) => InventarioRapidoEstado(
    localizacaoId: localizacaoId,
    localizacaoNome: localizacaoNome,
    leituras: leituras ?? this.leituras,
    processando: processando ?? this.processando,
  );
}

/// Controla a sessão de Inventário Rápido (Android, protótipo local) —
/// NUNCA grava nada no Supabase: só consulta (via [resolverCodigoEscaneado],
/// a MESMA resolução exata do leitor de patrimônio já existente) e
/// mantém a lista de leituras em memória.
class InventarioRapidoController extends Notifier<InventarioRapidoEstado?> {
  int _proximoId = 1;
  String _gerarId() => 'leitura-${_proximoId++}';

  @override
  InventarioRapidoEstado? build() => null;

  /// Inicia uma nova sessão para [localizacaoId] — substitui qualquer
  /// sessão anterior (o pedido é de UMA sessão temporária por vez; quem
  /// chama decide se confirma a perda de uma sessão em andamento antes
  /// disso, ver `InventarioRapidoPage`).
  void iniciarSessao({
    required String localizacaoId,
    required String localizacaoNome,
  }) {
    _proximoId = 1;
    state = InventarioRapidoEstado(
      localizacaoId: localizacaoId,
      localizacaoNome: localizacaoNome,
    );
  }

  /// Encerra a sessão atual (volta para `null`) — usado ao finalizar a
  /// conferência (depois de gerar o relatório) ou ao descartar
  /// explicitamente.
  void encerrarSessao() => state = null;

  /// Resolve [codigoLido] (câmera ou entrada manual) e registra o
  /// resultado na sessão — reaproveita [resolverCodigoEscaneado] (MESMA
  /// resolução exata do leitor de patrimônio avulso, nunca uma segunda
  /// lógica de busca). Nunca dispara uma segunda consulta enquanto uma
  /// já está em voo.
  Future<void> processarCodigo(String codigoLido) async {
    final atual = state;
    if (atual == null || atual.processando) return;

    state = atual.copiarCom(processando: true);
    final repositorio = ref.read(patrimonioRepositoryProvider);
    final resultado = await resolverCodigoEscaneado(repositorio, codigoLido);

    // A sessão pode ter sido encerrada enquanto a consulta estava em
    // voo (ex.: usuário saiu da tela) — nunca reviver um estado antigo.
    final depois = state;
    if (depois == null) return;

    state = depois.copiarCom(
      processando: false,
      leituras: registrarLeitura(
        leituras: depois.leituras,
        resultado: resultado,
        agora: DateTime.now(),
        gerarId: _gerarId,
      ),
    );
  }

  /// Remove a linha [id] da sessão — ação explícita de revisão manual.
  void removerLeitura(String id) {
    final atual = state;
    if (atual == null) return;
    state = atual.copiarCom(
      leituras: removerLeituraPorId(atual.leituras, id),
    );
  }

  /// Reconsulta o MESMO código já lido na linha [id] ("tentar de novo"/
  /// corrigir uma pendência) — mesma resolução exata, nunca decide nada
  /// sozinho além de atualizar aquela linha.
  Future<void> tentarNovamente(String id) async {
    final atual = state;
    if (atual == null || atual.processando) return;
    final leitura = _buscarPorId(atual.leituras, id);
    if (leitura == null) return;

    state = atual.copiarCom(processando: true);
    final repositorio = ref.read(patrimonioRepositoryProvider);
    final resultado = await resolverCodigoEscaneado(
      repositorio,
      leitura.codigoLido,
    );

    final depois = state;
    if (depois == null) return;

    state = depois.copiarCom(
      processando: false,
      leituras: atualizarLeitura(
        leituras: depois.leituras,
        id: id,
        resultado: resultado,
        agora: DateTime.now(),
      ),
    );
  }

  InventarioLeitura? _buscarPorId(List<InventarioLeitura> leituras, String id) {
    for (final leitura in leituras) {
      if (leitura.id == id) return leitura;
    }
    return null;
  }
}

final inventarioRapidoControllerProvider =
    NotifierProvider<InventarioRapidoController, InventarioRapidoEstado?>(
      InventarioRapidoController.new,
    );
