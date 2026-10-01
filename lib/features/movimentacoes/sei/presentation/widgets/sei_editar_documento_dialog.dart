import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/setor_display.dart';
import '../../../../../core/validation/app_validators.dart';
import '../../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../../../patrimonios/presentation/patrimonio_reference_data.dart';
import '../../../../setores/domain/setor.dart';
import '../../data/documentos_sei_repository_supabase.dart';
import '../../domain/documentos_sei_repository.dart';
import '../../domain/sei_decisao_campo.dart';
import '../../domain/sei_documento_pendente.dart';
import '../../domain/sei_item_pendencia_status.dart';
import '../../domain/sei_item_pendente.dart';
import '../../domain/sei_pendencia_exceptions.dart';

/// Formulário de edição de um Documento SEI pendente — usa a RPC
/// `editar_documento_sei_pendente` (via
/// [DocumentosSeiRepository.editarDocumento]) para corrigir dados do
/// documento e de itens ainda PENDENTES. Nunca chama `registrarMovimentacao`:
/// esta tela só corrige a SOLICITAÇÃO, nunca executa a transferência em si.
///
/// Nada é escrito enquanto o usuário só digita ou seleciona: toda alteração
/// fica em memória (controllers locais + [_edicoesPorItem]) até "Salvar
/// alterações" ser tocado. Devolve `true` quando a edição foi salva com
/// sucesso (para o chamador recarregar o detalhe/listagem), `false`/`null`
/// quando o usuário descartou sem salvar.
Future<bool?> showSeiEditarDocumentoDialog(BuildContext context, SeiDocumentoPendente documento) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SeiEditarDocumentoDialog(documento: documento),
  );
}

class _SeiEditarDocumentoDialog extends ConsumerStatefulWidget {
  const _SeiEditarDocumentoDialog({required this.documento});

  final SeiDocumentoPendente documento;

  @override
  ConsumerState<_SeiEditarDocumentoDialog> createState() => _SeiEditarDocumentoDialogState();
}

class _SeiEditarDocumentoDialogState extends ConsumerState<_SeiEditarDocumentoDialog> {
  late final _numeroDocumentoSeiController = TextEditingController(text: widget.documento.numeroDocumentoSei ?? '');
  late final _numeroProcessoController = TextEditingController(text: widget.documento.numeroProcesso ?? '');
  late final _numeroDocumentoFormatadoController = TextEditingController(
    text: widget.documento.numeroDocumentoFormatado ?? '',
  );
  late final _assuntoController = TextEditingController(text: widget.documento.assunto ?? '');
  final _motivoController = TextEditingController();

  /// itemId -> edição corrente daquele item (vazia até o usuário alterar
  /// algo). Só existe em memória — nunca escrito no banco antes de "Salvar
  /// alterações".
  final Map<String, SeiItemPendenteEdicao> _edicoesPorItem = {};

  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _numeroDocumentoSeiController,
      _numeroProcessoController,
      _numeroDocumentoFormatadoController,
      _assuntoController,
      _motivoController,
    ]) {
      controller.addListener(_atualizarTela);
    }
  }

  @override
  void dispose() {
    _numeroDocumentoSeiController.dispose();
    _numeroProcessoController.dispose();
    _numeroDocumentoFormatadoController.dispose();
    _assuntoController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _atualizarTela() {
    if (mounted) setState(() {});
  }

  String? _campoOuNulo(String texto) {
    final aparado = texto.trim();
    return aparado.isEmpty ? null : aparado;
  }

  bool get _houveAlteracao {
    final documento = widget.documento;
    if (_campoOuNulo(_numeroDocumentoSeiController.text) != documento.numeroDocumentoSei) return true;
    if (_campoOuNulo(_numeroProcessoController.text) != documento.numeroProcesso) return true;
    if (_campoOuNulo(_numeroDocumentoFormatadoController.text) != documento.numeroDocumentoFormatado) return true;
    if (_campoOuNulo(_assuntoController.text) != documento.assunto) return true;
    return _edicoesPorItem.values.any((e) => !e.vazia);
  }

  void _registrarEdicaoItem(String itemId, SeiItemPendenteEdicao edicao) {
    _edicoesPorItem[itemId] = edicao;
    setState(() {});
  }

  Future<void> _salvar() async {
    final motivo = _motivoController.text.trim();
    if (motivo.isEmpty || !_houveAlteracao || _salvando) return;

    setState(() {
      _salvando = true;
      _erro = null;
    });

    final documento = widget.documento;
    final novoNumeroDocumentoSei = _campoOuNulo(_numeroDocumentoSeiController.text);
    final novoNumeroProcesso = _campoOuNulo(_numeroProcessoController.text);
    final novoNumeroDocumentoFormatado = _campoOuNulo(_numeroDocumentoFormatadoController.text);
    final novoAssunto = _campoOuNulo(_assuntoController.text);

    try {
      final repositorio = ref.read(documentosSeiRepositoryProvider);
      await repositorio.editarDocumento(
        documentoId: documento.id,
        versaoEsperada: documento.versao,
        motivo: motivo,
        numeroDocumentoSei: novoNumeroDocumentoSei != documento.numeroDocumentoSei
            ? () => novoNumeroDocumentoSei
            : null,
        numeroProcesso: novoNumeroProcesso != documento.numeroProcesso ? () => novoNumeroProcesso : null,
        numeroDocumentoFormatado: novoNumeroDocumentoFormatado != documento.numeroDocumentoFormatado
            ? () => novoNumeroDocumentoFormatado
            : null,
        assunto: novoAssunto != documento.assunto ? () => novoAssunto : null,
        itensAlterados: {
          for (final entrada in _edicoesPorItem.entries)
            if (!entrada.value.vazia) entrada.key: entrada.value,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Documento SEI atualizado com sucesso.')));
      Navigator.of(context).pop(true);
    } on SeiEdicaoConflitoException catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro =
            'Este documento foi alterado por outra sessão enquanto você editava '
            '(versão esperada ${e.versaoEsperada}, versão atual ${e.versaoAtual}). '
            'Feche este formulário e reabra o detalhe para reler os dados antes de tentar novamente.';
      });
    } on SeiDocumentoBloqueadoParaEdicaoException {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro =
            'Este documento recebeu sua primeira conclusão durante a edição — os dados originais '
            'agora estão bloqueados permanentemente. Feche este formulário e reabra o detalhe.';
      });
    } on SeiItemEdicaoInvalidaException catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro =
            'Não foi possível salvar: um dos itens não pôde mais ser corrigido (${e.motivo}). '
            'Feche este formulário e reabra o detalhe para reler os dados.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = 'Não foi possível salvar as alterações. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final documento = widget.documento;
    final theme = Theme.of(context);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final itensPendentes = documento.itens.where((i) => i.status == SeiItemPendenciaStatus.pendente).toList();
    final itensNaoPendentes = documento.itens.where((i) => i.status != SeiItemPendenciaStatus.pendente).toList();
    final podeSalvar =
        !_salvando &&
        _houveAlteracao &&
        _motivoController.text.trim().isNotEmpty &&
        AppValidators.numeroDocumentoSei(_numeroDocumentoSeiController.text) == null;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Editar documento', style: AppTypography.pageSubtitle(context))),
                  IconButton(
                    tooltip: 'Fechar sem salvar',
                    onPressed: _salvando ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DADOS DO DOCUMENTO',
                        style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _numeroDocumentoSeiController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'Número do documento SEI',
                          errorText: AppValidators.numeroDocumentoSei(_numeroDocumentoSeiController.text),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _numeroProcessoController,
                        decoration: const InputDecoration(labelText: 'Processo'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _numeroDocumentoFormatadoController,
                        decoration: const InputDecoration(labelText: 'Número formatado'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _assuntoController,
                        decoration: const InputDecoration(labelText: 'Assunto'),
                        minLines: 1,
                        maxLines: 3,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'ITENS PENDENTES (${itensPendentes.length})',
                        style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tipo de movimentação e origem não são editáveis aqui — a origem sempre reflete o '
                        'estado atual do InvTec.',
                        style: AppTypography.auxiliary(context),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (itensPendentes.isEmpty)
                        Text('Nenhum item pendente neste documento.', style: AppTypography.auxiliary(context))
                      else
                        setoresAsync.when(
                          data: (setores) => Column(
                            children: [
                              for (final item in itensPendentes)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                  child: _ItemEdicaoCard(
                                    key: ValueKey(item.id),
                                    item: item,
                                    setoresAtivos: setores,
                                    onChanged: (edicao) => _registrarEdicaoItem(item.id, edicao),
                                  ),
                                ),
                            ],
                          ),
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (_, _) => Text(
                            'Não foi possível carregar os setores para correção de destino.',
                            style: AppTypography.auxiliary(context),
                          ),
                        ),
                      if (itensNaoPendentes.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'ITENS NÃO EDITÁVEIS (${itensNaoPendentes.length}) — já concluído(s)/cancelado(s)',
                          style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        for (final item in itensNaoPendentes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'Linha ${item.linha} — ${item.numeroPatrimonio.valorEfetivo ?? '—'} (${item.status.label})',
                              style: AppTypography.auxiliary(context),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _motivoController,
                decoration: const InputDecoration(labelText: 'Motivo da edição (obrigatório)'),
                minLines: 1,
                maxLines: 2,
              ),
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_erro!, style: AppTypography.auxiliary(context)?.copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _salvando ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Descartar'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: podeSalvar ? _salvar : null,
                    child: _salvando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Salvar alterações'),
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

/// Edição individual de UM item PENDENTE — cada card mantém seu próprio
/// estado local e notifica o pai a cada alteração via [onChanged], sempre
/// com a edição COMPLETA e atual daquele item (nunca um delta), comparada
/// contra os valores originais de [item] para decidir o que efetivamente
/// mudou — nunca sobrescreve o original, só [SeiValorCorrigivel.corrigido]
/// muda.
class _ItemEdicaoCard extends StatefulWidget {
  const _ItemEdicaoCard({super.key, required this.item, required this.setoresAtivos, required this.onChanged});

  final SeiItemPendente item;
  final List<Setor> setoresAtivos;
  final ValueChanged<SeiItemPendenteEdicao> onChanged;

  @override
  State<_ItemEdicaoCard> createState() => _ItemEdicaoCardState();
}

class _ItemEdicaoCardState extends State<_ItemEdicaoCard> {
  late final _numeroPatrimonioController = TextEditingController(text: widget.item.numeroPatrimonio.valorEfetivo ?? '');
  late final _destinoTextoController = TextEditingController(text: widget.item.destinoTexto.valorEfetivo ?? '');
  late final _numeroChamadoController = TextEditingController(text: widget.item.numeroChamado.valorEfetivo ?? '');
  late final _equipamentoController = TextEditingController(text: widget.item.equipamentoTexto.valorEfetivo ?? '');
  late final _responsavelController = TextEditingController(text: widget.item.responsavelDestino ?? '');

  String? _destinoSetorId;
  String? _localizacaoDestinoId;

  /// `null` = decisão de localização não tocada nesta sessão de edição (não
  /// entra no payload). Só passa a ter um valor por uma ação explícita do
  /// usuário — nunca inferido do texto sozinho.
  SeiDecisaoCampo? _decisaoLocalizacaoManual;
  SeiDecisaoCampo? _decisaoResponsavelManual;

  @override
  void initState() {
    super.initState();
    _destinoSetorId = widget.item.destinoSetorId;
    _localizacaoDestinoId = widget.item.localizacaoDestinoId;
    for (final controller in [
      _numeroPatrimonioController,
      _destinoTextoController,
      _numeroChamadoController,
      _equipamentoController,
    ]) {
      controller.addListener(_notificar);
    }
    _responsavelController.addListener(_onResponsavelDigitado);
  }

  @override
  void dispose() {
    _numeroPatrimonioController.dispose();
    _destinoTextoController.dispose();
    _numeroChamadoController.dispose();
    _equipamentoController.dispose();
    _responsavelController.dispose();
    super.dispose();
  }

  String? _valorOuNulo(String texto) {
    final aparado = texto.trim();
    return aparado.isEmpty ? null : aparado;
  }

  bool _diferente(String textoAtual, String? valorOriginal) => textoAtual.trim() != (valorOriginal ?? '');

  void _onResponsavelDigitado() {
    final texto = _responsavelController.text.trim();
    setState(() => _decisaoResponsavelManual = texto.isEmpty ? null : SeiDecisaoCampo.definido);
    _notificar();
  }

  void _selecionarSetor(String? novoSetorId) {
    if (novoSetorId == null || novoSetorId == _destinoSetorId) return;
    setState(() {
      _destinoSetorId = novoSetorId;
      // Trocar o setor de destino invalida a localização já escolhida: a
      // base rejeita uma localização que não pertence ao novo setor. Se o
      // item já tinha localização presa ao setor antigo, a limpeza precisa
      // ser enviada (nunca "não tocada"), por isso já marca PENDENTE.
      _localizacaoDestinoId = null;
      _decisaoLocalizacaoManual = widget.item.localizacaoDestinoId != null ? SeiDecisaoCampo.pendente : null;
    });
    _notificar();
  }

  void _selecionarLocalizacao(String id) {
    setState(() {
      _localizacaoDestinoId = id;
      _decisaoLocalizacaoManual = SeiDecisaoCampo.definido;
    });
    _notificar();
  }

  void _confirmarSemLocalizacao() {
    setState(() {
      _localizacaoDestinoId = null;
      _decisaoLocalizacaoManual = SeiDecisaoCampo.confirmadoSemInformacao;
    });
    _notificar();
  }

  void _confirmarSemResponsavel() {
    _responsavelController.clear();
    setState(() => _decisaoResponsavelManual = SeiDecisaoCampo.confirmadoSemInformacao);
    _notificar();
  }

  void _notificar() {
    final item = widget.item;

    final numeroPatrimonioCorrigido = _diferente(_numeroPatrimonioController.text, item.numeroPatrimonio.valorEfetivo)
        ? _valorOuNulo(_numeroPatrimonioController.text)
        : null;
    final destinoTextoCorrigido = _diferente(_destinoTextoController.text, item.destinoTexto.valorEfetivo)
        ? _valorOuNulo(_destinoTextoController.text)
        : null;
    final numeroChamadoCorrigido = _diferente(_numeroChamadoController.text, item.numeroChamado.valorEfetivo)
        ? _valorOuNulo(_numeroChamadoController.text)
        : null;
    final equipamentoTextoCorrigido = _diferente(_equipamentoController.text, item.equipamentoTexto.valorEfetivo)
        ? _valorOuNulo(_equipamentoController.text)
        : null;

    final destinoSetorAlterado = _destinoSetorId != item.destinoSetorId;
    final localizacaoAlterada =
        _decisaoLocalizacaoManual != null &&
        (_localizacaoDestinoId != item.localizacaoDestinoId || _decisaoLocalizacaoManual != item.decisaoLocalizacao);
    final responsavelAlterado =
        _decisaoResponsavelManual != null &&
        (_valorOuNulo(_responsavelController.text) != item.responsavelDestino ||
            _decisaoResponsavelManual != item.decisaoResponsavel);

    widget.onChanged(
      SeiItemPendenteEdicao(
        numeroPatrimonioCorrigido: numeroPatrimonioCorrigido,
        destinoTextoCorrigido: destinoTextoCorrigido,
        numeroChamadoCorrigido: numeroChamadoCorrigido,
        equipamentoTextoCorrigido: equipamentoTextoCorrigido,
        destinoSetorId: destinoSetorAlterado ? () => _destinoSetorId : null,
        localizacaoDestinoId: localizacaoAlterada ? () => _localizacaoDestinoId : null,
        decisaoLocalizacao: localizacaoAlterada ? _decisaoLocalizacaoManual : null,
        responsavelDestino: responsavelAlterado ? () => _valorOuNulo(_responsavelController.text) : null,
        decisaoResponsavel: responsavelAlterado ? _decisaoResponsavelManual : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Linha ${item.linha}',
                  style: AppTypography.label(context)?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                if (item.origemSetorNome != null)
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Origem (somente leitura): ', style: AppTypography.auxiliary(context)),
                        Flexible(
                          child: Text(
                            siglaOuNomeSetor(sigla: item.origemSetorSigla, nome: item.origemSetorNome) ?? '—',
                            style: AppTypography.auxiliary(context),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _numeroPatrimonioController,
                    decoration: InputDecoration(
                      labelText: 'Número patrimonial',
                      helperText: item.numeroPatrimonio.original == null
                          ? null
                          : 'Original: ${item.numeroPatrimonio.original}',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _numeroChamadoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Número do chamado',
                      helperText: item.numeroChamado.original == null
                          ? null
                          : 'Original: ${item.numeroChamado.original}',
                      errorText: AppValidators.numeroChamado(_numeroChamadoController.text),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _destinoTextoController,
              decoration: InputDecoration(
                labelText: 'Destino (texto do documento)',
                helperText: item.destinoTexto.original == null ? null : 'Original: ${item.destinoTexto.original}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _equipamentoController,
              decoration: InputDecoration(
                labelText: 'Equipamento',
                helperText: item.equipamentoTexto.original == null
                    ? null
                    : 'Original: ${item.equipamentoTexto.original}',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _destinoSetorId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Setor de destino resolvido'),
              items: [
                for (final setor in widget.setoresAtivos)
                  DropdownMenuItem(
                    value: setor.id,
                    child: Tooltip(
                      message: setor.nome,
                      child: Text(setor.rotuloCompacto, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                // Setor atual do item pode não estar entre os ativos (ex.:
                // foi desativado depois da importação) — nunca omitido do
                // dropdown, só assim `initialValue` sempre bate com um item
                // real da lista.
                if (_destinoSetorId != null && !widget.setoresAtivos.any((s) => s.id == _destinoSetorId))
                  DropdownMenuItem(
                    value: _destinoSetorId,
                    child: Tooltip(
                      message: item.destinoSetorNome ?? 'Setor não listado (inativo)',
                      child: Text(
                        siglaOuNomeSetor(sigla: item.destinoSetorSigla, nome: item.destinoSetorNome) ??
                            _destinoSetorId!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              onChanged: _selecionarSetor,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Localização de destino', style: AppTypography.body(context)),
            const SizedBox(height: AppSpacing.xs),
            if (_destinoSetorId == null)
              Text(
                'Selecione um setor de destino para escolher a localização.',
                style: AppTypography.auxiliary(context),
              )
            else
              Consumer(
                builder: (context, ref, _) {
                  final localizacoesAsync = ref.watch(localizacoesAtivasPorSetorProvider(_destinoSetorId!));
                  return localizacoesAsync.when(
                    data: (localizacoes) => Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final localizacao in localizacoes)
                          ChoiceChip(
                            label: Text(localizacao.nome),
                            selected: _localizacaoDestinoId == localizacao.id,
                            onSelected: (_) => _selecionarLocalizacao(localizacao.id),
                          ),
                        ActionChip(label: const Text('Não informar localização'), onPressed: _confirmarSemLocalizacao),
                      ],
                    ),
                    loading: () =>
                        const SizedBox(height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (_, _) => Text(
                      'Não foi possível carregar as localizações deste setor.',
                      style: AppTypography.auxiliary(context),
                    ),
                  );
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            Text('Responsável de destino', style: AppTypography.body(context)),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _responsavelController,
              decoration: const InputDecoration(hintText: 'Nome do responsável'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(onPressed: _confirmarSemResponsavel, child: const Text('Confirmar sem responsável')),
          ],
        ),
      ),
    );
  }
}
