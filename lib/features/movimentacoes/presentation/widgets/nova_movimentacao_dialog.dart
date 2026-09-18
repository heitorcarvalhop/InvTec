import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../dashboard/presentation/dashboard_providers.dart';
import '../../../patrimonios/data/patrimonio_repository_supabase.dart';
import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../patrimonios/presentation/patrimonio_detalhe_providers.dart';
import '../../../patrimonios/presentation/patrimonios_controller.dart';
import '../../data/movimentacao_repository_supabase.dart';
import '../../domain/movimentacao.dart';
import '../movimentacao_historico_providers.dart';
import '../movimentacoes_controller.dart' show movimentacoesControllerProvider;
import 'nova_movimentacao/detalhes_step.dart';
import 'nova_movimentacao/nova_movimentacao_rascunho.dart';
import 'nova_movimentacao/patrimonio_busca_step.dart';
import 'nova_movimentacao/revisao_step.dart';
import 'nova_movimentacao/tipo_step.dart';

const _tituloPassos = ['Patrimônio', 'Tipo', 'Detalhes', 'Revisão'];

/// Wizard de registro de movimentação (PROMPT 10.2) — a ÚNICA escrita que
/// ele realiza é `registrar_movimentacao(...)`, e só depois do clique
/// humano explícito em "Confirmar movimentação" no último passo. Retorna
/// `true` quando a movimentação foi registrada com sucesso.
Future<bool?> showNovaMovimentacaoDialog(BuildContext context) {
  return showDialog<bool>(context: context, builder: (context) => const NovaMovimentacaoDialog());
}

class NovaMovimentacaoDialog extends ConsumerStatefulWidget {
  const NovaMovimentacaoDialog({super.key});

  @override
  ConsumerState<NovaMovimentacaoDialog> createState() => _NovaMovimentacaoDialogState();
}

class _NovaMovimentacaoDialogState extends ConsumerState<NovaMovimentacaoDialog> {
  final _rascunho = NovaMovimentacaoRascunho();
  PatrimonioDetalhe? _patrimonio;
  int _step = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _rascunho.dispose();
    super.dispose();
  }

  bool get _podeAvancar {
    switch (_step) {
      case 0:
        return _patrimonio != null;
      case 1:
        return _rascunho.tipo != null;
      case 2:
        return detalhesValidos(_rascunho, _patrimonio!.patrimonio);
      default:
        return false;
    }
  }

  bool get _podeConfirmar {
    if (_patrimonio == null || !detalhesValidos(_rascunho, _patrimonio!.patrimonio)) return false;
    if (_rascunho.tipo == MovimentacaoTipo.baixa && !_rascunho.confirmacaoBaixa) return false;
    return true;
  }

  void _selecionarPatrimonio(PatrimonioDetalhe detalhe) {
    setState(() {
      _patrimonio = detalhe;
      _step = 1;
    });
  }

  void _trocarPatrimonio() {
    setState(() {
      _patrimonio = null;
      _step = 0;
      _resetarEscolhasDeTipo();
    });
  }

  void _selecionarTipo(MovimentacaoTipo tipo) {
    setState(() {
      _rascunho.tipo = tipo;
      _resetarEscolhasDeTipo(preservarTipo: true);
    });
  }

  /// Trocar de patrimônio ou de tipo invalida destino/localização/
  /// confirmação já escolhidos — eles só fazem sentido para o tipo/
  /// patrimônio anterior (seção 6 do prompt: nunca herdar um estado que não
  /// corresponde mais à escolha atual).
  void _resetarEscolhasDeTipo({bool preservarTipo = false}) {
    if (!preservarTipo) _rascunho.tipo = null;
    _rascunho.destinoSetorId = null;
    _rascunho.localizacaoDestinoId = null;
    _rascunho.localizacaoEscolha = LocalizacaoEscolha.manter;
    _rascunho.confirmacaoBaixa = false;
  }

  void _avancar() {
    if (!_podeAvancar) return;
    setState(() => _step++);
  }

  void _voltar() => setState(() => _step--);

  Future<void> _confirmar() async {
    // Guarda contra double-submit (PROMPT 10.2, seção 11): o botão já fica
    // desabilitado durante o envio, mas a checagem aqui é a garantia real —
    // um segundo clique que escape à desabilitação do botão (ex.: chegando
    // antes do primeiro `setState` repintar a UI) ainda não dispara uma
    // segunda chamada.
    if (_isSubmitting || !_podeConfirmar) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final patrimonioId = _patrimonio!.patrimonio.id;

    try {
      await ref
          .read(movimentacaoRepositoryProvider)
          .registrarMovimentacao(
            patrimonioId: patrimonioId,
            tipo: _rascunho.tipo!,
            destinoId: _rascunho.destinoSetorId,
            localizacaoDestinoId: _rascunho.localizacaoEscolha == LocalizacaoEscolha.definir
                ? _rascunho.localizacaoDestinoId
                : null,
            limparLocalizacao: _rascunho.localizacaoEscolha == LocalizacaoEscolha.limpar,
            responsavelDestino: _rascunho.responsavelController.text,
            motivo: _rascunho.motivoController.text,
            observacao: _rascunho.observacaoController.text,
            numeroDocumento: _rascunho.documentoController.text,
            numeroChamado: _rascunho.chamadoController.text,
          );

      // Sucesso (PROMPT 10.2, seção 12; PROMPT 10.2.1, seção 3): invalida só
      // o que pode ter mudado, nunca um refresh completo do app. Inclui o
      // histórico/timeline do patrimônio (`patrimonioHistoricoProvider`) —
      // sem isso, a tela de detalhe continuaria mostrando a timeline antiga
      // até o usuário sair e voltar. `ref.invalidate` é seguro mesmo para um
      // provider que não está sendo assistido no momento (ex.: o dashboard,
      // se a tela atual for Movimentações) — ele só marca a próxima leitura
      // como precisando recarregar.
      ref.invalidate(patrimonioDetalheProvider(patrimonioId));
      ref.invalidate(patrimonioHistoricoProvider(patrimonioId));
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(patrimoniosControllerProvider);
      await ref.read(movimentacoesControllerProvider.notifier).recarregar();

      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      // Erro da RPC (seção 13): nunca escondido, nunca uma segunda escrita
      // compensatória — só mostra a mensagem e mantém o formulário/revisão
      // preenchidos para o usuário corrigir ou tentar de novo.
      //
      // Concorrência (seção 14): o estado mostrado na abertura do
      // formulário pode ter mudado antes da confirmação (outra sessão
      // moveu o mesmo patrimônio nesse meio-tempo) — a RPC já é a
      // autoridade que rejeitou, mas a UI ainda mostraria o status ANTIGO
      // se o usuário voltasse para revisar. Refaz a leitura do patrimônio
      // (melhor esforço: se essa leitura falhar, o erro original da RPC já
      // foi mostrado, então não sobrescreve por um erro secundário) para
      // que "voltar e revisar de novo" realmente parta do estado atual.
      final atualizado = await ref.read(patrimonioRepositoryProvider).buscarDetalhePorId(patrimonioId).catchError(
        (_) => _patrimonio,
      );
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          if (atualizado != null) _patrimonio = atualizado;
        });
      }
    } catch (_) {
      setState(() => _errorMessage = 'Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _conteudoDoPasso() {
    switch (_step) {
      case 0:
        return PatrimonioBuscaStep(
          selecionado: _patrimonio,
          onSelecionar: _selecionarPatrimonio,
          onTrocar: _trocarPatrimonio,
        );
      case 1:
        return TipoStep(
          status: _patrimonio!.patrimonio.status,
          selecionado: _rascunho.tipo,
          onSelecionar: _selecionarTipo,
        );
      case 2:
        return DetalhesStep(
          patrimonio: _patrimonio!.patrimonio,
          rascunho: _rascunho,
          onChanged: () => setState(() {}),
          enabled: !_isSubmitting,
        );
      case 3:
        return RevisaoStep(
          detalhe: _patrimonio!,
          rascunho: _rascunho,
          onConfirmacaoBaixaChanged: (valor) => setState(() => _rascunho.confirmacaoBaixa = valor),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ultimoPasso = _step == _tituloPassos.length - 1;

    return PopScope(
      // Bloqueia fechar o diálogo (tecla Voltar/clique fora) enquanto a RPC
      // está em voo — nunca deixa o usuário achar que cancelou algo que já
      // está sendo gravado.
      canPop: !_isSubmitting,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Nova movimentação', style: AppTypography.pageSubtitle(context)),
                    ),
                    Text(
                      'Passo ${_step + 1} de ${_tituloPassos.length} · ${_tituloPassos[_step]}',
                      style: AppTypography.auxiliary(context),
                    ),
                  ],
                ),
                // Lembrete de qual patrimônio está sendo movimentado, visível
                // em todos os passos depois da seleção — o passo Patrimônio
                // já mostra o resumo completo, então não repete aqui.
                if (_patrimonio != null && _step > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Patrimônio: ${_patrimonio!.patrimonio.numeroPatrimonio ?? '(sem número)'}',
                    style: AppTypography.auxiliary(context),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Flexible(child: SingleChildScrollView(child: _conteudoDoPasso())),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                // `Wrap` (não `Row`) para o rótulo mais longo ("Confirmar
                // movimentação") nunca estourar a largura do diálogo — em
                // vez de overflow, os botões simplesmente quebram para uma
                // segunda linha quando não cabem lado a lado.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        if (_step > 0)
                          OutlinedButton(onPressed: _isSubmitting ? null : _voltar, child: const Text('Voltar')),
                        if (!ultimoPasso)
                          FilledButton(onPressed: _podeAvancar ? _avancar : null, child: const Text('Avançar'))
                        else
                          FilledButton(
                            key: const ValueKey('nova-movimentacao-confirmar'),
                            onPressed: (!_isSubmitting && _podeConfirmar) ? _confirmar : null,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Confirmar movimentação'),
                          ),
                      ],
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
