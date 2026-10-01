import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../application/sei_conclusao_erros.dart';
import '../../application/sei_conclusao_lote_plano.dart';
import '../../application/sei_conclusao_plano.dart';
import '../../application/sei_selecao_aptos_lote.dart';
import '../../domain/sei_conclusao_lote_resultado.dart';
import '../../domain/sei_decisao_campo.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_item_pendente.dart';
import '../sei_conclusao_lote_controller.dart';

/// como o diálogo de LOTE terminou. `null` (o `showDialog`
/// devolve `null`) só quando o usuário cancelou ANTES de confirmar (nenhuma
/// chamada foi feita) — nesses três campos preenchidos, sempre HOUVE uma
/// tentativa de `confirmar()`.
class SeiConclusaoLoteDesfecho {
  const SeiConclusaoLoteDesfecho({this.resultado, this.incerto = false, this.conflito = false});

  /// Preenchido quando a RPC respondeu com sucesso (nova conclusão OU
  /// retry idêntico/`ja_executado`).
  final SeiConclusaoLoteResultado? resultado;

  /// A tentativa terminou com RESULTADO DESCONHECIDO e o usuário fechou o
  /// diálogo sem resolver — a decisão continua CONGELADA no controller
  /// (`SeiConclusaoLoteController`), preservada para uma futura reabertura.
  final bool incerto;

  /// A tentativa caiu em CONFLITO DE INTEGRIDADE — a decisão continua
  /// congelada, exigindo investigação (nenhuma ação automática possível).
  final bool conflito;
}

const textoAvisoLote = 'Esta ação registrará movimentações patrimoniais reais e marcará estes itens como concluídos.';
const textoConfirmacaoEntregaFisicaLote =
    'Confirmo que TODOS os patrimônios listados acima foram efetivamente entregues aos destinos informados.';

/// "1 item"/"2 itens" (nunca "item(ns)"): só a FORMA da palavra — a contagem
/// é sempre escrita por quem chama, ao lado.
String _plural(int quantidade, String singular, String plural) => quantidade == 1 ? singular : plural;

/// Revisão e confirmação da conclusão em LOTE de itens SEI.
///
/// NADA é executado ao abrir: carrega a situação ATUAL de cada patrimônio
/// selecionado, monta o [SeiPlanoConclusaoLote] via [planejarConclusaoLote]
/// e exige (1) confirmação de que a entrega física de TODOS os itens
/// aconteceu e (2) — só quando o lote exigiria limpeza de
/// localização/responsável em algum item — uma segunda confirmação
/// explícita e AGREGADA (a RPC só recebe uma flag para o lote inteiro).
///
/// O diálogo NÃO tem máquina de estados própria: só RENDERIZA o estado atual
/// de [seiConclusaoLoteControllerProvider] — o `loteId` é gerado uma única
/// vez pelo controller, nunca reenviado com parâmetros diferentes. Reabrir
/// este diálogo com uma tentativa anterior pendente mostra o PAINEL daquele
/// estado diretamente, ignorando [itensSelecionados] — o controller decide,
/// nunca o widget.
Future<SeiConclusaoLoteDesfecho?> showSeiConcluirLoteDialog(
  BuildContext context, {
  required SeiDocumentoPendente documento,
  required List<SeiItemPendente> itensSelecionados,
  List<SeiItemNaoIncluidoLote> naoIncluidos = const [],
  // `null` (padrão) preserva [textoAvisoLote] exatamente como no app
  // operacional. Existe só para a prévia local mostrar, no MESMO widget
  // real, que a movimentação ali é fictícia.
  String? textoAviso,
}) {
  return showDialog<SeiConclusaoLoteDesfecho>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SeiConcluirLoteDialog(
      documento: documento,
      itensSelecionados: itensSelecionados,
      naoIncluidos: naoIncluidos,
      textoAviso: textoAviso,
    ),
  );
}

class _SeiConcluirLoteDialog extends ConsumerStatefulWidget {
  const _SeiConcluirLoteDialog({
    required this.documento,
    required this.itensSelecionados,
    required this.naoIncluidos,
    this.textoAviso,
  });

  final SeiDocumentoPendente documento;
  final List<SeiItemPendente> itensSelecionados;
  final List<SeiItemNaoIncluidoLote> naoIncluidos;
  final String? textoAviso;

  @override
  ConsumerState<_SeiConcluirLoteDialog> createState() => _SeiConcluirLoteDialogState();
}

class _SeiConcluirLoteDialogState extends ConsumerState<_SeiConcluirLoteDialog> {
  final _observacao = TextEditingController();

  final Map<String, PatrimonioDetalhe?> _patrimonios = {};
  bool _carregandoPatrimonios = true;

  bool _entregaConfirmada = false;
  bool _limpezaConfirmada = false;
  bool _mostrarTecnico = false;

  // Só FEEDBACK VISUAL da última consulta de reconciliação, nunca uma
  // segunda máquina de estados: quando `state.status` muda, o `switch` de
  // `build` já troca de painel sozinho. Só importam quando `state.status`
  // permanece `resultadoDesconhecido` antes e depois da consulta.
  bool _consultando = false;
  String? _avisoConsulta;

  @override
  void initState() {
    super.initState();
    _carregarPatrimonios();
  }

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  /// Só LÊ a situação ATUAL de cada patrimônio selecionado — nunca escreve
  /// nada, e NUNCA reaproveita um [PatrimonioDetalhe] que a tela anterior já
  /// tinha em mãos: uma foto antiga não é suficiente para confirmar a
  /// conclusão.
  Future<void> _carregarPatrimonios() async {
    final repositorio = ref.read(patrimonioRepositoryProvider);
    final buscas = <Future<void>>[];
    for (final item in widget.itensSelecionados) {
      final patrimonioId = item.patrimonioId;
      if (patrimonioId == null) continue;
      buscas.add(() async {
        try {
          _patrimonios[item.id] = await repositorio.buscarDetalhePorId(patrimonioId);
        } catch (_) {
          _patrimonios[item.id] = null;
        }
      }());
    }
    await Future.wait(buscas);
    if (!mounted) return;
    setState(() => _carregandoPatrimonios = false);
  }

  void _confirmar(SeiPlanoConclusaoLote plano) {
    // Protege contra clique duplo: o próprio controller já ignora uma
    // segunda chamada enquanto `executando`/pendente (guarda síncrona,
    // antes de qualquer `await`) — aqui é só uma segunda camada.
    ref
        .read(seiConclusaoLoteControllerProvider.notifier)
        .confirmar(
          documentoId: widget.documento.id,
          itemIds: widget.itensSelecionados.map((i) => i.id).toList(),
          versaoEsperada: widget.documento.versao,
          observacao: _observacao.text,
          confirmarLimpezaDestino: plano.exigeConfirmacaoDeLimpezaAgregada && _limpezaConfirmada,
        );
  }

  /// Dispara [SeiConclusaoLoteController.reconciliar] e traduz o
  /// [SeiReconciliacaoResultado] num aviso visível quando `state.status`
  /// continuar [SeiConclusaoLoteStatus.resultadoDesconhecido] depois da
  /// chamada — nos outros casos o `switch` de `build` já troca de painel.
  Future<void> _consultar() async {
    setState(() {
      _consultando = true;
      _avisoConsulta = null;
    });
    final resultado = await ref.read(seiConclusaoLoteControllerProvider.notifier).reconciliar();
    if (!mounted) return;
    setState(() {
      _consultando = false;
      // Texto CURTO de propósito: as informações de segurança completas já
      // estão no bloco principal (inalterado). Isto é só um rótulo de "o
      // que a última consulta encontrou", renderizado à parte.
      _avisoConsulta = switch (resultado) {
        SeiReconciliacaoResultado.aindaDesconhecido => 'Última consulta: ainda sem confirmação.',
        SeiReconciliacaoResultado.falhaDeConsulta =>
          'Última consulta: não foi possível completar (falha de comunicação/permissão).',
        SeiReconciliacaoResultado.sucesso ||
        SeiReconciliacaoResultado.conflito ||
        SeiReconciliacaoResultado.semEfeito => null,
      };
    });
  }

  void _fechar(SeiConclusaoLoteState state) {
    final notifier = ref.read(seiConclusaoLoteControllerProvider.notifier);
    switch (state.status) {
      case SeiConclusaoLoteStatus.sucesso:
        final resultado = state.resultado;
        notifier.reiniciar();
        Navigator.of(context).pop(SeiConclusaoLoteDesfecho(resultado: resultado));
      case SeiConclusaoLoteStatus.recusado:
        // Recusa DEFINITIVA do servidor: a transação foi desfeita, nada foi
        // escrito — seguro encerrar a decisão ao fechar.
        notifier.reiniciar();
        Navigator.of(context).pop(const SeiConclusaoLoteDesfecho());
      case SeiConclusaoLoteStatus.resultadoDesconhecido:
        // NUNCA reinicia: a decisão continua CONGELADA no controller para
        // uma futura reabertura (retry/reconciliar).
        Navigator.of(context).pop(const SeiConclusaoLoteDesfecho(incerto: true));
      case SeiConclusaoLoteStatus.conflitoDeIntegridade:
        // Idem — preservada para investigação; nenhum botão aqui contorna
        // os guards do controller.
        Navigator.of(context).pop(const SeiConclusaoLoteDesfecho(conflito: true));
      case SeiConclusaoLoteStatus.ocioso:
      case SeiConclusaoLoteStatus.executando:
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(seiConclusaoLoteControllerProvider);
    return PopScope(
      canPop: !state.executando,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: switch (state.status) {
              SeiConclusaoLoteStatus.ocioso => _buildRevisao(context, state),
              SeiConclusaoLoteStatus.executando => _buildExecutando(context),
              SeiConclusaoLoteStatus.sucesso => _buildSucesso(context, state),
              SeiConclusaoLoteStatus.recusado => _buildRecusado(context, state),
              SeiConclusaoLoteStatus.resultadoDesconhecido => _buildResultadoDesconhecido(context, state),
              SeiConclusaoLoteStatus.conflitoDeIntegridade => _buildConflitoDeIntegridade(context, state),
            },
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // OCIOSO — revisão + confirmações, ainda sem nenhuma chamada feita.
  // ---------------------------------------------------------------------
  Widget _buildRevisao(BuildContext context, SeiConclusaoLoteState state) {
    final theme = Theme.of(context);

    if (_carregandoPatrimonios) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final plano = planejarConclusaoLote(
      documento: widget.documento,
      itensSelecionados: widget.itensSelecionados,
      patrimoniosPorItemId: _patrimonios,
    );

    final limpezaOk = !plano.exigeConfirmacaoDeLimpezaAgregada || _limpezaConfirmada;
    final podeConcluir = plano.podeConfirmar && _entregaConfirmada && limpezaOk;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Concluir ${plano.totalSelecionado} ${_plural(plano.totalSelecionado, 'item', 'itens')} em lote',
          style: AppTypography.pageSubtitle(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.documento.numeroDocumentoFormatado ?? widget.documento.numeroDocumentoSei ?? 'Documento SEI',
          style: AppTypography.auxiliary(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.textoAviso ?? textoAvisoLote, style: AppTypography.body(context)),
                const SizedBox(height: AppSpacing.md),
                if (plano.bloqueiosGerais.isNotEmpty) ...[
                  _CaixaDeAviso(
                    key: const Key('sei-concluir-lote-bloqueios-gerais'),
                    cor: theme.colorScheme.errorContainer,
                    corTexto: theme.colorScheme.onErrorContainer,
                    icone: Icons.block,
                    titulo: 'Não é possível concluir este lote agora:',
                    linhas: plano.bloqueiosGerais,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (plano.exigeConfirmacaoDeLimpezaAgregada) ...[
                  _CaixaDeAviso(
                    key: const Key('sei-concluir-lote-aviso-limpeza'),
                    cor: theme.colorScheme.tertiaryContainer,
                    corTexto: theme.colorScheme.onTertiaryContainer,
                    icone: Icons.warning_amber_rounded,
                    linhas: const [
                      'Um ou mais itens deste lote removerão a localização e/ou o responsável atual do '
                          'patrimônio. Essa confirmação vale para TODO o lote — a RPC recebe uma única decisão de '
                          'limpeza para todos os itens selecionados.',
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.separated(
                    key: const Key('sei-concluir-lote-itens'),
                    shrinkWrap: true,
                    itemCount: plano.itens.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _ItemRevisao(item: plano.itens[index]),
                  ),
                ),
                if (widget.naoIncluidos.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _NaoIncluidos(itens: widget.naoIncluidos),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('sei-concluir-lote-observacao'),
                  controller: _observacao,
                  decoration: const InputDecoration(labelText: 'Observação (opcional, vale para todo o lote)'),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (plano.exigeConfirmacaoDeLimpezaAgregada)
                  CheckboxListTile(
                    key: const Key('sei-concluir-lote-checkbox-limpeza'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _limpezaConfirmada,
                    onChanged: (v) => setState(() => _limpezaConfirmada = v ?? false),
                    title: Text(
                      'Entendo e confirmo que a conclusão deste lote removerá a localização e/ou o responsável '
                      'atual de um ou mais patrimônios listados.',
                      style: AppTypography.body(context),
                    ),
                  ),
                CheckboxListTile(
                  key: const Key('sei-concluir-lote-checkbox-entrega'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _entregaConfirmada,
                  onChanged: (v) => setState(() => _entregaConfirmada = v ?? false),
                  title: Text(textoConfirmacaoEntregaFisicaLote, style: AppTypography.body(context)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            TextButton(
              key: const Key('sei-concluir-lote-voltar'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
            FilledButton(
              key: const Key('sei-concluir-lote-botao-confirmar'),
              onPressed: podeConcluir ? () => _confirmar(plano) : null,
              child: Text('Concluir ${plano.totalSelecionado} ${_plural(plano.totalSelecionado, 'item', 'itens')}'),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // EXECUTANDO — texto distinto quando é só uma CONSULTA (leitura) em vez
  // de uma escrita (`confirmar`/`retry`).
  // ---------------------------------------------------------------------
  Widget _buildExecutando(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(_consultando ? 'Consultando o resultado deste lote…' : 'Confirmando a conclusão em lote…'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SUCESSO
  // ---------------------------------------------------------------------
  Widget _buildSucesso(BuildContext context, SeiConclusaoLoteState state) {
    final resultado = state.resultado!;
    final theme = Theme.of(context);
    final n = resultado.itens.length;
    final mensagem = resultado.jaExecutado
        ? 'Este lote já havia sido concluído anteriormente ($n ${_plural(n, 'item', 'itens')}) — nenhuma nova '
              'movimentação foi criada.'
        : '$n ${_plural(n, 'item concluído', 'itens concluídos')} e '
              '${_plural(n, 'movimentação registrada', 'movimentações registradas')} com sucesso.';

    return _painelDesfecho(
      context,
      key: const Key('sei-concluir-lote-sucesso'),
      icone: Icons.check_circle_outline,
      cor: theme.colorScheme.secondaryContainer,
      corTexto: theme.colorScheme.onSecondaryContainer,
      titulo: 'Lote concluído',
      linhas: [mensagem],
      botaoFechar: FilledButton(
        key: const Key('sei-concluir-lote-fechar'),
        onPressed: () => _fechar(state),
        child: const Text('Fechar'),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // RECUSADO — recusa DEFINITIVA do servidor (P0010/P0036/P0037/etc.).
  // ---------------------------------------------------------------------
  Widget _buildRecusado(BuildContext context, SeiConclusaoLoteState state) {
    final theme = Theme.of(context);
    return _painelDesfecho(
      context,
      key: const Key('sei-concluir-lote-recusado'),
      icone: Icons.error_outline,
      cor: theme.colorScheme.errorContainer,
      corTexto: theme.colorScheme.onErrorContainer,
      titulo: 'Não foi possível concluir este lote',
      linhas: [state.falha!.message, 'Nada foi alterado — nenhum item deste lote foi concluído.'],
      detalhesTecnicos: state.falha!.textoTecnico,
      botaoFechar: FilledButton(
        key: const Key('sei-concluir-lote-fechar'),
        onPressed: () => _fechar(state),
        child: const Text('Fechar e atualizar'),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // RESULTADO DESCONHECIDO — timeout/falha de conexão: NUNCA é uma falha
  // definitiva. loteId e os 6 parâmetros continuam congelados no
  // controller.
  // ---------------------------------------------------------------------
  Widget _buildResultadoDesconhecido(BuildContext context, SeiConclusaoLoteState state) {
    final theme = Theme.of(context);
    final notifier = ref.read(seiConclusaoLoteControllerProvider.notifier);
    return _painelDesfecho(
      context,
      key: const Key('sei-concluir-lote-incerto'),
      icone: Icons.help_outline,
      cor: theme.colorScheme.errorContainer,
      corTexto: theme.colorScheme.onErrorContainer,
      titulo: 'Não foi possível confirmar o resultado deste lote',
      linhas: const [
        'Houve uma falha de comunicação — a conclusão pode ou pode não ter sido aplicada no servidor. '
            'NÃO repita esta ação de outra forma: use as opções abaixo, que reenviam exatamente os mesmos '
            'parâmetros já confirmados.',
      ],
      // Resultado da última consulta feita por "Consultar o que aconteceu",
      // renderizado fora do bloco vermelho principal — nenhuma informação
      // de segurança se perde (continua toda ali, inalterada).
      avisoSecundario: _avisoConsulta,
      acoes: [
        OutlinedButton(
          key: const Key('sei-concluir-lote-reconciliar'),
          onPressed: state.executando || _consultando ? null : _consultar,
          child: const Text('Consultar o que aconteceu'),
        ),
        FilledButton(
          key: const Key('sei-concluir-lote-retry'),
          onPressed: state.executando || _consultando
              ? null
              : () {
                  // "Tentar novamente" é uma ação DIFERENTE (escrita, não
                  // consulta) — limpa o aviso da consulta anterior.
                  setState(() => _avisoConsulta = null);
                  notifier.retry();
                },
          child: const Text('Tentar novamente (mesmos dados)'),
        ),
      ],
      botaoFechar: TextButton(
        key: const Key('sei-concluir-lote-fechar'),
        onPressed: () => _fechar(state),
        child: const Text('Fechar (mantém a tentativa pendente)'),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // CONFLITO DE INTEGRIDADE — nenhuma ação automática; exige investigação.
  // ---------------------------------------------------------------------
  Widget _buildConflitoDeIntegridade(BuildContext context, SeiConclusaoLoteState state) {
    final theme = Theme.of(context);
    final falha = state.falha;
    return _painelDesfecho(
      context,
      key: const Key('sei-concluir-lote-conflito'),
      icone: Icons.report_gmailerrorred,
      cor: theme.colorScheme.errorContainer,
      corTexto: theme.colorScheme.onErrorContainer,
      titulo: 'Conflito de integridade — investigação necessária',
      linhas: const [
        'O identificador desta tentativa de lote foi encontrado no servidor, mas com dados diferentes dos '
            'que esta decisão enviaria. Por segurança, NENHUMA ação automática é permitida a partir daqui — '
            'nem repetir, nem consultar de novo, nem começar uma nova decisão para este documento.',
        'Contate o suporte técnico com os detalhes técnicos abaixo.',
      ],
      // NUNCA `falha?.textoTecnico` aqui: aquele texto orienta "comece uma
      // nova conclusão", seguro para uma recusa definitiva mas contraditório
      // num conflito de integridade. `loteId` vem da decisão CONGELADA.
      detalhesTecnicos: falha == null ? null : textoTecnicoConflitoDeIntegridade(falha, loteId: state.decisao?.loteId),
      // PROPOSITALMENTE sem nenhum botão de ação além de fechar — nunca
      // contorna os guards do controller (retry/reconciliar/reiniciar
      // permanecem sem efeito neste status, por design).
      botaoFechar: FilledButton(
        key: const Key('sei-concluir-lote-fechar'),
        onPressed: () => _fechar(state),
        child: const Text('Fechar (mantém a tentativa preservada)'),
      ),
    );
  }

  Widget _painelDesfecho(
    BuildContext context, {
    required Key key,
    required IconData icone,
    required Color cor,
    required Color corTexto,
    required String titulo,
    required List<String> linhas,
    String? detalhesTecnicos,
    // Nota CURTA e SEPARADA do bloco de alerta principal (tom neutro,
    // discreto) — hoje só usada pelo resultado da última consulta em
    // [SeiConclusaoLoteStatus.resultadoDesconhecido].
    String? avisoSecundario,
    List<Widget> acoes = const [],
    required Widget botaoFechar,
  }) {
    final theme = Theme.of(context);
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CaixaDeAviso(
                  cor: cor,
                  corTexto: corTexto,
                  icone: icone,
                  titulo: titulo,
                  linhas: linhas,
                  rodape: detalhesTecnicos == null
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _mostrarTecnico = !_mostrarTecnico),
                              child: Text(_mostrarTecnico ? 'Ocultar detalhes técnicos' : 'Detalhes técnicos'),
                            ),
                            if (_mostrarTecnico)
                              SelectableText(detalhesTecnicos, style: AppTypography.body(context)?.copyWith(color: corTexto)),
                          ],
                        ),
                ),
                if (avisoSecundario != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    key: const Key('sei-concluir-lote-aviso-consulta'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          avisoSecundario,
                          style: AppTypography.auxiliary(context)?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [...acoes, botaoFechar],
        ),
      ],
    );
  }
}

/// Um item dentro da lista de revisão — patrimônio, equipamento, origem →
/// destino, localização/responsável de destino e, quando houver, os
/// bloqueios/consequências de limpeza DESTE item (vindos do
/// [SeiPlanoConclusaoLoteItem.plano], sem nenhuma regra recalculada aqui).
class _ItemRevisao extends StatelessWidget {
  const _ItemRevisao({required this.item});

  final SeiPlanoConclusaoLoteItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plano = item.plano;
    final bloqueado = !plano.podeConfirmar;

    return Padding(
      key: Key('sei-concluir-lote-item-${item.itemId}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bloqueado ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: bloqueado ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    Text(plano.numeroPatrimonio, style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w700)),
                    if (plano.equipamento != null && plano.equipamento!.isNotEmpty)
                      Text('— ${plano.equipamento}', style: AppTypography.auxiliary(context)),
                  ],
                ),
                Text(
                  '${plano.origemAtual ?? plano.origemDoDocumento ?? '—'}  →  ${plano.destinoSetor}',
                  style: AppTypography.body(context),
                ),
                Text(
                  'Localização de destino: ${_valorDoDestinoLote(plano.decisaoLocalizacao, plano.destinoLocalizacao)} · '
                  'Responsável de destino: ${_valorDoDestinoLote(plano.decisaoResponsavel, plano.destinoResponsavel)}',
                  style: AppTypography.auxiliary(context),
                ),
                if (plano.limpaLocalizacao || plano.limpaResponsavel)
                  Text(
                    'Removerá ${[
                      if (plano.limpaResponsavel) 'o responsável atual',
                      if (plano.limpaLocalizacao) 'a localização atual',
                    ].join(' e ')} deste patrimônio.',
                    style: AppTypography.auxiliary(context)?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                for (final bloqueio in plano.bloqueios)
                  Text(bloqueio, style: AppTypography.auxiliary(context)?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// PENDENTE não é "sem informação": só CONFIRMADO_SEM_INFORMACAO mostra
/// [textoNaoInformado]; PENDENTE mostra [textoPendenteDeDefinicao]. Duplicado
/// de propósito de `sei_concluir_entrega_dialog.dart` — só apresentação.
String _valorDoDestinoLote(SeiDecisaoCampo decisao, String? valor) {
  switch (decisao) {
    case SeiDecisaoCampo.pendente:
      return textoPendenteDeDefinicao;
    case SeiDecisaoCampo.definido:
      return valor ?? textoPendenteDeDefinicao;
    case SeiDecisaoCampo.confirmadoSemInformacao:
      return textoNaoInformado;
  }
}

/// Itens PENDENTES que "Concluir todos os aptos" NÃO incluiu na seleção —
/// só informativo, NUNCA enviado à RPC.
class _NaoIncluidos extends StatelessWidget {
  const _NaoIncluidos({required this.itens});

  final List<SeiItemNaoIncluidoLote> itens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [itens] chega na ordem de CONSTRUÇÃO (ver
    // `selecionarAptosParaLoteComPatrimonios`), não na ordem de LINHA do
    // documento — reordena só para exibição, nenhuma regra de elegibilidade muda.
    final itensOrdenados = [...itens]..sort((a, b) => a.item.linha.compareTo(b.item.linha));
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('sei-concluir-lote-nao-incluidos'),
        tilePadding: EdgeInsets.zero,
        title: Text(
          '${itens.length} ${_plural(itens.length, 'item NÃO incluído', 'itens NÃO incluídos')} nesta conclusão',
          style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
        ),
        children: [
          for (final naoIncluido in itensOrdenados)
            Padding(
              key: Key('sei-concluir-lote-nao-incluido-${naoIncluido.item.id}'),
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              // Mesmo Row/Icon/Expanded de `_ItemRevisao` para manter o
              // patrimônio alinhado entre as duas listas (ícone sempre
              // "bloqueado": todo item aqui é, por definição, não incluído).
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.remove_circle_outline, size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          naoIncluido.item.numeroPatrimonio.valorEfetivo ?? '(item ${naoIncluido.item.linha})',
                          style: AppTypography.body(context)?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        for (final motivo in naoIncluido.motivos)
                          Text('• $motivo', style: AppTypography.auxiliary(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CaixaDeAviso extends StatelessWidget {
  const _CaixaDeAviso({
    super.key,
    required this.cor,
    required this.corTexto,
    required this.icone,
    required this.linhas,
    this.titulo,
    this.rodape,
  });

  final Color cor;
  final Color corTexto;
  final IconData icone;
  final List<String> linhas;
  final String? titulo;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    final estilo = AppTypography.body(context)?.copyWith(color: corTexto);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20, color: corTexto),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titulo != null) Text(titulo!, style: estilo?.copyWith(fontWeight: FontWeight.w600)),
                for (final linha in linhas) Text(linha, style: estilo),
                ?rodape,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
