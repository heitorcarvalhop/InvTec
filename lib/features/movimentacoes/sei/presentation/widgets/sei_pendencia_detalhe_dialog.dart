import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/compact_icon_button.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../../../auth/domain/profile.dart';
import '../../../../auth/presentation/auth_controller.dart';
import '../../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../domain/movimentacao.dart';
import '../../application/sei_conclusao_lote_plano.dart';
import '../../application/sei_pendencia_regras.dart';
import '../../application/sei_selecao_aptos_lote.dart';
import '../../data/documentos_sei_repository_supabase.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_documento_situacao.dart';
import '../../domain/sei_item_pendente.dart';
import '../../domain/sei_pendencia_exceptions.dart';
import '../sei_conclusao_lote_controller.dart';
import '../sei_situacao_visual.dart';
import 'sei_concluir_entrega_dialog.dart';
import 'sei_concluir_lote_dialog.dart';
import 'sei_editar_documento_dialog.dart';
import 'sei_historico_alteracoes.dart';
import 'sei_itens_pendencia_lista.dart';

/// Detalhe de um Documento SEI pendente — mostra os itens e permite CANCELAR
/// um item PENDENTE ou os pendentes restantes (cancelamento parcial nunca
/// desfaz conclusões anteriores).
///
/// Mensagens das três situações distintas de uma escrita
/// (cancelar item / cancelar pendentes). Constantes públicas para os testes.
const mensagemSeiEscritaRecusada =
    'Não foi possível concluir a ação: o servidor recusou a operação e o documento NÃO foi alterado.';
const mensagemSeiEscritaConcluidaRecargaFalhou =
    'A ação foi enviada ao servidor e provavelmente concluída, mas não foi possível atualizar a tela. '
    'NÃO repita a ação: confira o resultado no documento.';
const mensagemSeiEscritaIncerta =
    'Não foi possível confirmar o resultado da ação (falha de comunicação). '
    'Atualizamos o documento — confira o estado antes de tentar de novo.';

/// desfecho de "Concluir entrega".
const mensagemSeiEntregaConcluida = 'Entrega concluída e movimentação registrada com sucesso.';
const mensagemSeiItemJaConcluido = 'Este item já havia sido concluído.';

Future<void> showSeiPendenciaDetalheDialog(
  BuildContext context,
  String documentoId, {
  // `null` (padrão) preserva o aviso de responsabilidade REAL do app
  // operacional. Existe só para a prévia local avisar que a movimentação
  // simulada ali é fictícia, usando o MESMO diálogo real.
  String? textoAvisoConclusaoLote,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _SeiPendenciaDetalheDialog(documentoId: documentoId, textoAvisoConclusaoLote: textoAvisoConclusaoLote),
  );
}

class _SeiPendenciaDetalheDialog extends ConsumerStatefulWidget {
  const _SeiPendenciaDetalheDialog({required this.documentoId, this.textoAvisoConclusaoLote});

  final String documentoId;
  final String? textoAvisoConclusaoLote;

  @override
  ConsumerState<_SeiPendenciaDetalheDialog> createState() => _SeiPendenciaDetalheDialogState();
}

class _SeiPendenciaDetalheDialogState extends ConsumerState<_SeiPendenciaDetalheDialog> {
  SeiDocumentoPendente? _documento;
  bool _carregando = true;
  String? _erro;
  bool _executandoAcao = false;

  /// seleção em LOTE, controlada por ESTE diálogo
  /// (`SeiItensPendenciaLista` só reflete/alterna, nunca guarda sozinha) e
  /// identificada pelos ids dos itens.
  final Set<String> _selecionados = {};

  /// aviso do resultado da última ação, mostrado DENTRO do
  /// diálogo. Um `SnackBar` do Scaffold da página aparece ATRÁS da barreira
  /// do diálogo modal: o texto até é visível, mas nenhum botão dele (como
  /// "Detalhes técnicos") recebe o clique.
  _AvisoDeAcao? _aviso;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final repositorio = ref.read(documentosSeiRepositoryProvider);
      final documento = await repositorio.obterPorId(widget.documentoId);
      if (!mounted) return;
      setState(() {
        _documento = documento;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar o documento. Tente novamente.';
        _carregando = false;
      });
    }
  }

  /// `true` quando existe uma decisão de conclusão em LOTE pendente para
  /// ESTE MESMO documento — o controller é GLOBAL, então comparar
  /// `documentoId` é o que torna o bloqueio contextual a este documento, sem
  /// afetar outros. Chamada no início de cada handler de escrita.
  bool _bloqueadoPorLotePendente(SeiDocumentoPendente documento) {
    final estado = ref.read(seiConclusaoLoteControllerProvider);
    return estado.temTentativaPendente && estado.decisao?.documentoId == documento.id;
  }

  Future<void> _editarDocumento(SeiDocumentoPendente documento) async {
    if (_bloqueadoPorLotePendente(documento)) return;
    final salvou = await showSeiEditarDocumentoDialog(context, documento);
    if (salvou == true && mounted) await _carregar();
  }

  Future<void> _cancelarItem(SeiDocumentoPendente documento, String itemId) async {
    if (_bloqueadoPorLotePendente(documento)) return;
    final motivo = await _pedirMotivo(context, titulo: 'Cancelar item');
    if (motivo == null) return;
    await _executar(() async {
      final repositorio = ref.read(documentosSeiRepositoryProvider);
      await repositorio.cancelarItem(itemId: itemId, motivo: motivo);
    });
  }

  /// Abre a confirmação de "Concluir entrega". A RPC só roda dentro do
  /// diálogo; aqui só se interpreta o desfecho e se relê o documento. A
  /// checagem de bloqueio vem antes de ler o [item]: com um lote pendente
  /// para este documento, nenhum diálogo de confirmação é aberto.
  Future<void> _concluirItem(SeiDocumentoPendente documento, String itemId) async {
    if (_bloqueadoPorLotePendente(documento)) return;
    final item = documento.itens.firstWhere((i) => i.id == itemId);
    if (!itemPodeSerConcluido(item)) return;
    final desfecho = await showSeiConcluirEntregaDialog(context, documento: documento, item: item);
    if (desfecho == null || !mounted) return;

    final resultado = desfecho.resultado;
    setState(() {
      _aviso = resultado != null
          ? _AvisoDeAcao(resultado.jaConcluido ? mensagemSeiItemJaConcluido : mensagemSeiEntregaConcluida)
          : desfecho.incerto
          ? const _AvisoDeAcao(mensagemConclusaoIncerta, erro: true)
          : null;
    });
    await _carregar();
  }

  void _alternarSelecao(String itemId) {
    setState(() {
      if (!_selecionados.remove(itemId)) _selecionados.add(itemId);
    });
  }

  /// "Concluir selecionados": abre a revisão com EXATAMENTE a seleção
  /// explícita do usuário — nenhum item inválido é removido automaticamente.
  /// Com uma tentativa de LOTE pendente para este documento, este botão vira
  /// o caminho de acesso à recuperação daquela tentativa, sem criar uma
  /// decisão nova.
  Future<void> _concluirSelecionados(SeiDocumentoPendente documento) async {
    if (_bloqueadoPorLotePendente(documento)) {
      await _abrirRevisaoLote(documento, const []);
      return;
    }
    if (_selecionados.isEmpty) return;
    final itens = documento.itens.where((i) => _selecionados.contains(i.id)).toList();
    await _abrirRevisaoLote(documento, itens);
  }

  /// "Concluir todos os aptos": busca o patrimônio ATUAL de cada candidato
  /// da triagem preliminar e delega a [selecionarAptosParaLoteComPatrimonios]
  /// a reavaliação completa, incluindo o limite de itens aplicado à
  /// contagem FINAL. Acima do limite, NUNCA trunca sozinho — pede seleção
  /// manual. Não gera `loteId` nem cria decisão no
  /// [SeiConclusaoLoteController] — só leitura.
  Future<void> _concluirTodosAptos(SeiDocumentoPendente documento) async {
    // Com uma tentativa de LOTE pendente para este documento, pula direto
    // para a revisão/recuperação em vez de gastar uma consulta de
    // patrimônios inteira para uma seleção que nunca vira decisão nova.
    if (_bloqueadoPorLotePendente(documento)) {
      await _abrirRevisaoLote(documento, const []);
      return;
    }
    final candidatos = selecionarAptosParaLote(documento.itens);
    if (candidatos.aptos.isEmpty) {
      setState(() => _aviso = const _AvisoDeAcao('Nenhum item pendente está apto para conclusão em lote no momento.'));
      return;
    }

    setState(() => _executandoAcao = true);
    final Map<String, PatrimonioDetalhe?> patrimonios;
    try {
      patrimonios = await _buscarPatrimoniosAtuais(candidatos.aptos);
    } finally {
      if (mounted) setState(() => _executandoAcao = false);
    }
    if (!mounted) return;

    final selecao = selecionarAptosParaLoteComPatrimonios(documento: documento, patrimoniosPorItemId: patrimonios);

    if (selecao.aptos.isEmpty) {
      setState(
        () => _aviso = const _AvisoDeAcao(
          'Nenhum item permaneceu apto depois de conferir a situação atual dos patrimônios — veja os motivos '
          'na lista (ex.: origem divergente).',
        ),
      );
      return;
    }

    // contra a contagem FINAL (nunca a preliminar):
    // acima do limite, bloqueia a seleção automática e pede seleção
    // manual — nunca trunca os 200 primeiros silenciosamente.
    if (selecao.excedeLimite) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Limite de itens por lote excedido'),
          content: Text(
            'Há ${selecao.aptos.length} itens efetivamente aptos para conclusão (depois de conferir a situação '
            'atual dos patrimônios), acima do limite de $limiteItensLote por lote. Marque manualmente, pelos '
            'checkboxes da lista, quais itens concluir (até $limiteItensLote de cada vez).',
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entendi'))],
        ),
      );
      return;
    }

    await _abrirRevisaoLote(documento, selecao.aptos, naoIncluidos: selecao.naoIncluidos);
  }

  /// Busca a situação ATUAL de cada patrimônio de [itens] (nunca reaproveita
  /// nada antigo). Uma falha na consulta de UM item específico NUNCA presume
  /// elegibilidade: vira `null` no mapa, que [planejarConclusaoLote] já
  /// trata como bloqueio.
  Future<Map<String, PatrimonioDetalhe?>> _buscarPatrimoniosAtuais(List<SeiItemPendente> itens) async {
    final repositorio = ref.read(patrimonioRepositoryProvider);
    final resultado = <String, PatrimonioDetalhe?>{};
    final buscas = <Future<void>>[];
    for (final item in itens) {
      final patrimonioId = item.patrimonioId;
      if (patrimonioId == null) continue;
      buscas.add(() async {
        try {
          resultado[item.id] = await repositorio.buscarDetalhePorId(patrimonioId);
        } catch (_) {
          resultado[item.id] = null;
        }
      }());
    }
    await Future.wait(buscas);
    return resultado;
  }

  /// Abre [showSeiConcluirLoteDialog] e interpreta o desfecho — a RPC só
  /// roda DENTRO do diálogo (via `SeiConclusaoLoteController`), depois das
  /// confirmações; aqui só se trata o resultado e se relê o documento.
  Future<void> _abrirRevisaoLote(
    SeiDocumentoPendente documento,
    List<SeiItemPendente> itens, {
    List<SeiItemNaoIncluidoLote> naoIncluidos = const [],
  }) async {
    final desfecho = await showSeiConcluirLoteDialog(
      context,
      documento: documento,
      itensSelecionados: itens,
      naoIncluidos: naoIncluidos,
      textoAviso: widget.textoAvisoConclusaoLote,
    );
    if (desfecho == null || !mounted) return;

    final resultado = desfecho.resultado;
    if (resultado != null) {
      final n = resultado.itens.length;
      setState(() {
        _selecionados.clear();
        _aviso = _AvisoDeAcao(
          resultado.jaExecutado
              ? 'Este lote já havia sido concluído anteriormente ($n ${_plural(n, 'item', 'itens')}) — nenhuma '
                    'nova movimentação foi criada.'
              : '$n ${_plural(n, 'item concluído', 'itens concluídos')} em lote e '
                    '${_plural(n, 'movimentação registrada', 'movimentações registradas')} com sucesso.',
        );
      });
      // A conclusão já foi CONFIRMADA pelo servidor: uma falha aqui é só de
      // releitura, nunca deve substituir o aviso de sucesso por um erro.
      try {
        final documentoAtualizado = await ref.read(documentosSeiRepositoryProvider).obterPorId(widget.documentoId);
        if (!mounted) return;
        setState(() => _documento = documentoAtualizado);
      } catch (_) {
        if (!mounted) return;
        setState(
          () => _aviso = const _AvisoDeAcao(
            'A conclusão em lote foi confirmada pelo servidor, mas não foi possível atualizar a tela agora. '
            'NÃO repita a ação: feche e reabra o documento para conferir o resultado.',
          ),
        );
      }
      return;
    }

    if (desfecho.conflito) {
      setState(
        () => _aviso = const _AvisoDeAcao(
          'Há uma conclusão em lote com conflito de integridade pendente de investigação para este documento. '
          'Nenhuma ação automática é permitida — contate o suporte técnico.',
          erro: true,
        ),
      );
      return;
    }

    if (desfecho.incerto) {
      setState(
        () => _aviso = const _AvisoDeAcao(
          'Não foi possível confirmar o resultado da conclusão em lote (falha de comunicação). A tentativa '
          'continua pendente — use "Concluir selecionados" de novo para consultar ou tentar de novo.',
          erro: true,
        ),
      );
    }
    // Usuário só cancelou antes de confirmar (nenhum campo preenchido no
    // desfecho): nada a fazer.
  }

  Future<void> _cancelarPendentes(SeiDocumentoPendente documento) async {
    if (_bloqueadoPorLotePendente(documento)) return;
    final motivo = await _pedirMotivo(context, titulo: 'Cancelar itens pendentes deste documento');
    if (motivo == null) return;
    await _executar(() async {
      final repositorio = ref.read(documentosSeiRepositoryProvider);
      await repositorio.cancelarPendentesDoDocumento(documentoId: documento.id, motivo: motivo);
    });
  }

  Future<void> _executar(Future<void> Function() acao) async {
    setState(() {
      _executandoAcao = true;
      _aviso = null;
    });
    try {
      await acao();
      await _carregar();
    } on SeiItemNaoElegivelException {
      if (!mounted) return;
      setState(() => _aviso = const _AvisoDeAcao('Este item não está mais pendente — releia o documento.'));
      await _carregar();
    } on SeiEscritaFalhouException catch (falha) {
      // A RPC recusou/falhou: a transação foi desfeita e o documento NÃO
      // mudou. O erro técnico original fica em "Detalhes técnicos" (antes
      // era engolido pela mensagem genérica).
      if (!mounted) return;
      setState(() => _aviso = _AvisoDeAcao(mensagemSeiEscritaRecusada, erro: true, falha: falha));
    } on SeiEscritaConcluidaRecargaFalhouException {
      // A RPC deu sucesso; só a releitura falhou. Nunca sugerir "tentar de
      // novo": a escrita provavelmente já foi aplicada.
      if (!mounted) return;
      setState(() => _aviso = const _AvisoDeAcao(mensagemSeiEscritaConcluidaRecargaFalhou));
      await _carregar();
    } catch (_) {
      // Resultado INCERTO (ex.: falha de comunicação — a RPC pode ou não ter
      // chegado ao servidor): relê o documento para mostrar o estado real e
      // não repete a escrita às cegas.
      if (!mounted) return;
      setState(() => _aviso = const _AvisoDeAcao(mensagemSeiEscritaIncerta));
      await _carregar();
    } finally {
      if (mounted) setState(() => _executandoAcao = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final podeGerenciar =
        perfil == ProfilePerfil.admin || perfil == ProfilePerfil.gestor || perfil == ProfilePerfil.operador;
    final documento = _documento;
    // O controller é GLOBAL (não por documento), então avisar/bloquear
    // escrita exige comparar `documentoId` — senão uma tentativa pendente
    // de outro documento bloquearia este também.
    final estadoLote = ref.watch(seiConclusaoLoteControllerProvider);
    final bloqueadoPorLote = documento != null && estadoLote.temTentativaPendente && estadoLote.decisao?.documentoId == documento.id;
    // Em tela estreita (Android) título + cabeçalho empilhado não cabiam na
    // altura do diálogo: o botão vira só ícone e o cabeçalho rola com o conteúdo.
    final compacto = MediaQuery.sizeOf(context).width < 600;

    final cabecalho = <Widget>[
      const SizedBox(height: AppSpacing.xs),
      if (documento != null) _CabecalhoDocumento(documento: documento),
      const SizedBox(height: AppSpacing.md),
      if (_aviso != null) _BannerDeAviso(aviso: _aviso!, onFechar: () => setState(() => _aviso = null)),
      // Visível mesmo sem reabrir "Concluir selecionados": o controller é
      // global, então uma tentativa pendente sobrevive a fechar/reabrir o
      // diálogo. Sem botão de fechar aqui, de propósito.
      if (bloqueadoPorLote)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(
            estadoLote.emConflitoDeIntegridade
                ? 'Há uma conclusão em lote em CONFLITO DE INTEGRIDADE, aguardando investigação — nenhuma nova '
                      'ação de escrita (conclusão individual, cancelamento ou edição) é permitida neste documento '
                      'até que ela seja resolvida.'
                : 'Há uma conclusão em lote com resultado ainda desconhecido para este documento — nenhuma nova '
                      'ação de escrita (conclusão individual, cancelamento ou edição) é permitida até que ela seja '
                      'esclarecida. Abra "Concluir selecionados" ou "Concluir todos os aptos" para consultar ou '
                      'tentar novamente.',
            style: AppTypography.auxiliary(context)?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      if (documento != null && documento.encerrado)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(
            'Documento encerrado: não há itens pendentes. Somente consulta e histórico.',
            style: AppTypography.auxiliary(context),
          ),
        )
      else if (documento != null && !documento.podeSerEditado)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Text(
            'Este documento já tem item(ns) concluído(s): os dados originais estão bloqueados '
            'para edição permanentemente (itens pendentes ainda podem ser concluídos/cancelados).',
            style: AppTypography.auxiliary(context),
          ),
        ),
    ];

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _carregando
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _erro != null || documento == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Text(_erro ?? 'Documento não encontrado.'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            documento.numeroDocumentoFormatado ?? documento.numeroDocumentoSei ?? 'Documento SEI',
                            style: AppTypography.pageSubtitle(context),
                          ),
                        ),
                        // Documento ENCERRADO (0 pendentes) não oferece edição.
                        if (podeGerenciar && !documento.encerrado)
                          Tooltip(
                            message: bloqueadoPorLote
                                ? 'Há uma conclusão em lote pendente de esclarecimento para este documento — a '
                                      'edição fica bloqueada até que ela seja resolvida.'
                                : documento.podeSerEditado
                                ? 'Corrigir os dados deste documento e de seus itens pendentes.'
                                : 'Este documento já tem item(ns) concluído(s) — os dados originais estão '
                                      'bloqueados para edição permanentemente.',
                            child: compacto
                                ? IconButton(
                                    onPressed: (!documento.podeSerEditado || _executandoAcao || bloqueadoPorLote)
                                        ? null
                                        : () => _editarDocumento(documento),
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : TextButton.icon(
                                    onPressed: (!documento.podeSerEditado || _executandoAcao || bloqueadoPorLote)
                                        ? null
                                        : () => _editarDocumento(documento),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Editar documento'),
                                  ),
                          ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (!compacto) ...cabecalho,
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (compacto) ...cabecalho,
                            SeiItensPendenciaLista(
                              documento: documento,
                              // Com o documento bloqueado por lote pendente,
                              // "Concluir entrega"/"Cancelar" somem da lista
                              // (nunca só desabilitados).
                              podeGerenciar: podeGerenciar && !_executandoAcao && !bloqueadoPorLote,
                              onCancelarItem: (itemId) => _cancelarItem(documento, itemId),
                              onConcluirItem: (itemId) => _concluirItem(documento, itemId),
                              selecionados: _selecionados,
                              onAlternarSelecao: (podeGerenciar && !_executandoAcao) ? _alternarSelecao : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            // Dentro do MESMO scroll da tabela de itens: expandir
                            // o histórico não pode estourar a altura fixa do diálogo.
                            Theme(
                              data: theme.copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text(
                                  'Histórico de alterações',
                                  style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
                                ),
                                children: [SeiHistoricoAlteracoes(documento: documento)],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (podeGerenciar && documento.totalPendentes > 0)
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          // Desabilitado com seleção vazia ou acima do limite
                          // (a revisão também bloqueia via `planejarConclusaoLote`).
                          Tooltip(
                            message: _selecionados.length > limiteItensLote
                                ? 'Seleção acima do limite de $limiteItensLote itens por lote — remova alguns.'
                                : 'Revisar e confirmar a conclusão em lote dos itens selecionados.',
                            child: OutlinedButton(
                              key: const Key('sei-botao-concluir-selecionados'),
                              onPressed: (_executandoAcao || _selecionados.isEmpty || _selecionados.length > limiteItensLote)
                                  ? null
                                  : () => _concluirSelecionados(documento),
                              child: Text('Concluir selecionados (${_selecionados.length})'),
                            ),
                          ),
                          OutlinedButton(
                            key: const Key('sei-botao-concluir-todos-aptos'),
                            onPressed: _executandoAcao ? null : () => _concluirTodosAptos(documento),
                            child: const Text('Concluir todos os aptos'),
                          ),
                          Tooltip(
                            message: bloqueadoPorLote
                                ? 'Há uma conclusão em lote pendente de esclarecimento para este documento — o '
                                      'cancelamento em massa fica bloqueado até que ela seja resolvida.'
                                : 'Cancelar todos os itens ainda pendentes deste documento.',
                            child: OutlinedButton(
                              onPressed: (_executandoAcao || bloqueadoPorLote) ? null : () => _cancelarPendentes(documento),
                              child: Text(
                                'Cancelar ${documento.totalPendentes} '
                                '${_plural(documento.totalPendentes, 'item pendente', 'itens pendentes')}',
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Resultado de uma ação de escrita que NÃO foi um sucesso limpo.
class _AvisoDeAcao {
  const _AvisoDeAcao(this.mensagem, {this.erro = false, this.falha});

  final String mensagem;

  /// `true` quando o servidor recusou a operação (nada mudou).
  final bool erro;

  /// Erro técnico original (só quando a RPC recusou), para "Detalhes técnicos".
  final SeiEscritaFalhouException? falha;
}

class _BannerDeAviso extends StatefulWidget {
  const _BannerDeAviso({required this.aviso, required this.onFechar});

  final _AvisoDeAcao aviso;
  final VoidCallback onFechar;

  @override
  State<_BannerDeAviso> createState() => _BannerDeAvisoState();
}

class _BannerDeAvisoState extends State<_BannerDeAviso> {
  bool _mostrarTecnico = false;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final aviso = widget.aviso;
    final fundo = aviso.erro ? cores.errorContainer : cores.secondaryContainer;
    final texto = aviso.erro ? cores.onErrorContainer : cores.onSecondaryContainer;
    final estilo = AppTypography.body(context)?.copyWith(color: texto);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(aviso.erro ? Icons.error_outline : Icons.info_outline, size: 20, color: texto),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(aviso.mensagem, style: estilo)),
              CompactIconButton(
                tooltip: 'Fechar aviso',
                onPressed: widget.onFechar,
                icon: Icon(Icons.close, size: 18, color: texto),
              ),
            ],
          ),
          if (aviso.falha != null) ...[
            TextButton(
              onPressed: () => setState(() => _mostrarTecnico = !_mostrarTecnico),
              child: Text(_mostrarTecnico ? 'Ocultar detalhes técnicos' : 'Detalhes técnicos'),
            ),
            if (_mostrarTecnico) SelectableText(aviso.falha!.textoTecnico, style: estilo),
          ],
        ],
      ),
    );
  }
}

class _CabecalhoDocumento extends StatelessWidget {
  const _CabecalhoDocumento({required this.documento});

  final SeiDocumentoPendente documento;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDaSituacaoDocumentoSei(documento.situacao);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusChip(label: documento.situacao.label, kind: kind, icon: icon),
        Text('Tipo: ${documento.tipoOperacaoPretendida.label}'),
        if (documento.numeroProcesso != null) Text('Processo: ${documento.numeroProcesso}'),
        if (documento.assunto != null && documento.assunto!.isNotEmpty) Text('Assunto: ${documento.assunto}'),
        Text('Cadastrado em ${_formatarDataHora(documento.criadoEm)}'),
        Text(
          '${documento.totalItens} item(ns) — ${documento.totalPendentes} pendente(s), '
          '${documento.totalConcluidos} concluído(s), ${documento.totalCancelados} cancelado(s)',
        ),
        Text('Cadastrado por ${documento.criadoPorNome}'),
      ],
    );
  }
}

Future<String?> _pedirMotivo(BuildContext context, {required String titulo}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Motivo (obrigatório)'),
        minLines: 1,
        maxLines: 3,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        // O `builder` do diálogo não roda de novo ao digitar, então escuta o
        // controller para reabilitar "Confirmar" assim que há um motivo.
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => FilledButton(
            onPressed: controller.text.trim().isEmpty ? null : () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Confirmar'),
          ),
        ),
      ],
    ),
  );
}

/// "1 item"/"2 itens" (nunca "item(ns)"): só a FORMA da palavra — a contagem
/// é sempre escrita por quem chama. Duplicado de propósito em
/// `sei_concluir_lote_dialog.dart`: é só apresentação de texto.
String _plural(int quantidade, String singular, String plural) => quantidade == 1 ? singular : plural;

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}
