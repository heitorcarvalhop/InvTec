import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../../patrimonios/domain/patrimonio.dart';
import '../../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../application/sei_conclusao_plano.dart';
import '../../data/documentos_sei_repository_supabase.dart';
import '../../domain/sei_conclusao_item_resultado.dart';
import '../../domain/sei_decisao_campo.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_item_pendente.dart';
import '../../domain/sei_pendencia_exceptions.dart';

/// Texto do aviso quando o resultado da conclusão é INCERTO (a chamada pode ou
/// não ter chegado ao servidor).
const mensagemConclusaoIncerta =
    'Não foi possível confirmar se a entrega foi concluída (falha de comunicação). '
    'NÃO repita a ação: feche esta tela e confira o documento.';

const textoConfirmacaoEntregaFisica = 'Confirmo que este patrimônio foi efetivamente entregue ao destino informado.';
const textoAvisoMovimentacaoReal =
    'Esta ação registrará uma movimentação patrimonial real e marcará este item como concluído.';

/// Como o diálogo terminou DEPOIS de uma tentativa de conclusão (quando o
/// usuário só cancelou, o diálogo devolve `null` e nada é recarregado).
class SeiConclusaoEntregaDesfecho {
  const SeiConclusaoEntregaDesfecho({this.resultado, this.incerto = false});

  /// Preenchido quando a RPC respondeu com sucesso (nova conclusão OU
  /// `ja_concluido`).
  final SeiConclusaoItemResultado? resultado;

  /// A chamada terminou com falha de comunicação: o estado real é
  /// desconhecido, a tela precisa reler o documento.
  final bool incerto;
}

/// Confirmação de "Concluir entrega" de UM item.
///
/// Exige (1) confirmação de que a entrega física aconteceu e (2) — só
/// quando a conclusão apagaria valores atuais — uma segunda confirmação
/// explícita. Só então chama `DocumentosSeiRepository.concluirItem` UMA vez
/// (botão desabilitado durante a chamada).
Future<SeiConclusaoEntregaDesfecho?> showSeiConcluirEntregaDialog(
  BuildContext context, {
  required SeiDocumentoPendente documento,
  required SeiItemPendente item,
}) {
  return showDialog<SeiConclusaoEntregaDesfecho>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SeiConcluirEntregaDialog(documento: documento, item: item),
  );
}

class _SeiConcluirEntregaDialog extends ConsumerStatefulWidget {
  const _SeiConcluirEntregaDialog({required this.documento, required this.item});

  final SeiDocumentoPendente documento;
  final SeiItemPendente item;

  @override
  ConsumerState<_SeiConcluirEntregaDialog> createState() => _SeiConcluirEntregaDialogState();
}

class _SeiConcluirEntregaDialogState extends ConsumerState<_SeiConcluirEntregaDialog> {
  final _observacao = TextEditingController();

  PatrimonioDetalhe? _patrimonio;
  bool _carregandoPatrimonio = true;

  bool _entregaConfirmada = false;
  bool _limpezaConfirmada = false;

  bool _executando = false;
  bool _tentou = false;
  bool _incerto = false;
  SeiEscritaFalhouException? _falha;
  bool _mostrarTecnico = false;

  @override
  void initState() {
    super.initState();
    _carregarPatrimonio();
  }

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  /// Só LÊ a situação atual do patrimônio (setor, localização, responsável,
  /// status) para mostrar as consequências — nunca escreve nada.
  Future<void> _carregarPatrimonio() async {
    final id = widget.item.patrimonioId;
    if (id == null) {
      setState(() => _carregandoPatrimonio = false);
      return;
    }
    try {
      final detalhe = await ref.read(patrimonioRepositoryProvider).buscarDetalhePorId(id);
      if (!mounted) return;
      setState(() {
        _patrimonio = detalhe;
        _carregandoPatrimonio = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoPatrimonio = false);
    }
  }

  bool get _houveFalha => _falha != null || _incerto;

  Future<void> _confirmar(SeiPlanoConclusao plano) async {
    // Protege contra clique duplo: o flag é marcado de forma SÍNCRONA, antes
    // de qualquer `await`.
    if (_executando) return;
    setState(() {
      _executando = true;
      _tentou = true;
      _falha = null;
      _incerto = false;
    });
    try {
      final resultado = await ref
          .read(documentosSeiRepositoryProvider)
          .concluirItem(
            documentoId: widget.documento.id,
            itemId: widget.item.id,
            versaoEsperada: widget.documento.versao,
            observacao: _observacao.text,
            // `true` SÓ quando a conclusão realmente limparia algo E o usuário
            // marcou a confirmação — nunca automático.
            confirmarLimpezaDestino: plano.exigeConfirmacaoDeLimpeza && _limpezaConfirmada,
          );
      if (!mounted) return;
      Navigator.of(context).pop(SeiConclusaoEntregaDesfecho(resultado: resultado));
    } on SeiEscritaFalhouException catch (falha) {
      if (!mounted) return;
      setState(() {
        _executando = false;
        _falha = falha;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _executando = false;
        _incerto = true;
      });
    }
  }

  void _fechar() {
    Navigator.of(context).pop(_tentou ? SeiConclusaoEntregaDesfecho(incerto: _incerto) : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plano = planejarConclusaoEntrega(
      documento: widget.documento,
      item: widget.item,
      patrimonioAtual: _carregandoPatrimonio ? null : _patrimonio,
    );
    // Enquanto o patrimônio carrega, a falta dele não é (ainda) um bloqueio.
    final bloqueios = _carregandoPatrimonio ? const <String>[] : plano.bloqueios;

    final limpezaOk = !plano.exigeConfirmacaoDeLimpeza || _limpezaConfirmada;
    final podeConcluir =
        !_carregandoPatrimonio && !_executando && !_houveFalha && bloqueios.isEmpty && _entregaConfirmada && limpezaOk;

    return PopScope(
      canPop: !_executando,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Concluir entrega', style: AppTypography.pageSubtitle(context)),
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(textoAvisoMovimentacaoReal, style: AppTypography.body(context)),
                        const SizedBox(height: AppSpacing.md),
                        if (_carregandoPatrimonio)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          _Resumo(plano: plano),
                          if (plano.limpaResponsavel || plano.limpaLocalizacao) ...[
                            const SizedBox(height: AppSpacing.md),
                            _CaixaDeAviso(
                              cor: theme.colorScheme.tertiaryContainer,
                              corTexto: theme.colorScheme.onTertiaryContainer,
                              icone: Icons.warning_amber_rounded,
                              linhas: [
                                if (plano.limpaResponsavel)
                                  'A conclusão removerá o responsável atual (${plano.responsavelAtual}) '
                                      'e o patrimônio ficará DISPONÍVEL.',
                                if (plano.limpaLocalizacao)
                                  'A conclusão removerá a localização atual'
                                      '${plano.localizacaoAtual != null ? ' (${plano.localizacaoAtual})' : ''}.',
                              ],
                            ),
                          ],
                          if (bloqueios.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            _CaixaDeAviso(
                              key: const Key('sei-concluir-bloqueios'),
                              cor: theme.colorScheme.errorContainer,
                              corTexto: theme.colorScheme.onErrorContainer,
                              icone: Icons.block,
                              titulo: 'Não é possível concluir esta entrega agora:',
                              linhas: bloqueios,
                            ),
                          ],
                        ],
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          key: const Key('sei-concluir-observacao'),
                          controller: _observacao,
                          enabled: !_executando && !_houveFalha,
                          decoration: const InputDecoration(labelText: 'Observação (opcional)'),
                          minLines: 1,
                          maxLines: 3,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (plano.exigeConfirmacaoDeLimpeza)
                          CheckboxListTile(
                            key: const Key('sei-concluir-checkbox-limpeza'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _limpezaConfirmada,
                            onChanged: (_executando || _houveFalha)
                                ? null
                                : (v) => setState(() => _limpezaConfirmada = v ?? false),
                            title: Text(_textoConfirmacaoLimpeza(plano), style: AppTypography.body(context)),
                          ),
                        CheckboxListTile(
                          key: const Key('sei-concluir-checkbox-entrega'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _entregaConfirmada,
                          onChanged: (_executando || _houveFalha)
                              ? null
                              : (v) => setState(() => _entregaConfirmada = v ?? false),
                          title: Text(textoConfirmacaoEntregaFisica, style: AppTypography.body(context)),
                        ),
                        if (_falha != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _CaixaDeAviso(
                            key: const Key('sei-concluir-erro'),
                            cor: theme.colorScheme.errorContainer,
                            corTexto: theme.colorScheme.onErrorContainer,
                            icone: Icons.error_outline,
                            linhas: [_falha!.message],
                            rodape: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextButton(
                                  onPressed: () => setState(() => _mostrarTecnico = !_mostrarTecnico),
                                  child: Text(_mostrarTecnico ? 'Ocultar detalhes técnicos' : 'Detalhes técnicos'),
                                ),
                                if (_mostrarTecnico)
                                  SelectableText(
                                    _falha!.textoTecnico,
                                    style: AppTypography.body(
                                      context,
                                    )?.copyWith(color: theme.colorScheme.onErrorContainer),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        if (_incerto) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _CaixaDeAviso(
                            key: const Key('sei-concluir-incerto'),
                            cor: theme.colorScheme.errorContainer,
                            corTexto: theme.colorScheme.onErrorContainer,
                            icone: Icons.error_outline,
                            linhas: const [mensagemConclusaoIncerta],
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
                  children: [
                    TextButton(
                      key: const Key('sei-concluir-voltar'),
                      onPressed: _executando ? null : _fechar,
                      child: Text(_houveFalha ? 'Fechar e atualizar' : 'Voltar'),
                    ),
                    FilledButton(
                      key: const Key('sei-concluir-botao-confirmar'),
                      onPressed: podeConcluir ? () => _confirmar(plano) : null,
                      child: _executando
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: AppSpacing.sm),
                                Text('Concluindo…'),
                              ],
                            )
                          : const Text('Concluir entrega'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _textoConfirmacaoLimpeza(SeiPlanoConclusao plano) {
  final partes = [if (plano.limpaResponsavel) 'o responsável atual', if (plano.limpaLocalizacao) 'a localização atual'];
  return 'Entendo e confirmo que a conclusão removerá ${partes.join(' e ')} deste patrimônio.';
}

/// PENDENTE não é "sem informação": só CONFIRMADO_SEM_INFORMACAO mostra
/// [textoNaoInformado]; PENDENTE mostra [textoPendenteDeDefinicao].
String _valorDoDestino(SeiDecisaoCampo decisao, String? valor) {
  switch (decisao) {
    case SeiDecisaoCampo.pendente:
      return textoPendenteDeDefinicao;
    case SeiDecisaoCampo.definido:
      return valor ?? textoPendenteDeDefinicao;
    case SeiDecisaoCampo.confirmadoSemInformacao:
      return textoNaoInformado;
  }
}

/// Resumo do que será registrado: patrimônio, origem, destino e documento.
class _Resumo extends StatelessWidget {
  const _Resumo({required this.plano});

  final SeiPlanoConclusao plano;

  @override
  Widget build(BuildContext context) {
    final equipamento = plano.equipamento;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Secao(
          titulo: 'Patrimônio',
          linhas: [
            ('Número', plano.numeroPatrimonio),
            if (equipamento != null && equipamento.isNotEmpty) ('Equipamento', equipamento),
          ],
        ),
        _Secao(
          titulo: 'Origem',
          linhas: [
            ('Setor', plano.origemAtual ?? plano.origemDoDocumento ?? '—'),
            if (plano.localizacaoAtual != null) ('Localização atual', plano.localizacaoAtual!),
            if (plano.responsavelAtual != null) ('Responsável atual', plano.responsavelAtual!),
          ],
        ),
        _Secao(
          titulo: 'Destino',
          linhas: [
            ('Setor', plano.destinoSetor),
            ('Localização de destino', _valorDoDestino(plano.decisaoLocalizacao, plano.destinoLocalizacao)),
            ('Responsável de destino', _valorDoDestino(plano.decisaoResponsavel, plano.destinoResponsavel)),
            ('Situação após a conclusão', plano.statusResultante?.label ?? textoSituacaoIndeterminada),
          ],
        ),
        _Secao(
          titulo: 'Documento',
          linhas: [('Número SEI', plano.numeroDocumento ?? '—'), ('Chamado', plano.numeroChamado ?? '—')],
        ),
      ],
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.linhas});

  final String titulo;
  final List<(String, String)> linhas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: AppTypography.label(context)),
          for (final (rotulo, valor) in linhas)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  Text('$rotulo:', style: AppTypography.auxiliary(context)),
                  Text(valor, style: AppTypography.body(context)),
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
