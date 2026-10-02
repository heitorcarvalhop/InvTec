import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
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

/// Wizard de registro de movimentação — a ÚNICA escrita que ele realiza é
/// `registrar_movimentacao(...)`, e só depois do clique humano explícito em
/// "Confirmar movimentação" no último passo. Retorna `true` quando a
/// movimentação foi registrada com sucesso.
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
  /// patrimônio anterior; nunca herdar um estado que não corresponde mais à
  /// escolha atual.
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
    // Guarda contra double-submit: o botão já fica desabilitado durante o
    // envio, mas a checagem aqui é a garantia real — um segundo clique que
    // escape à desabilitação do botão (ex.: chegando antes do primeiro
    // `setState` repintar a UI) ainda não dispara uma segunda chamada.
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

      // Sucesso: invalida só o que pode ter mudado, nunca um refresh
      // completo do app. Inclui o histórico/timeline do patrimônio
      // (`patrimonioHistoricoProvider`) — sem isso, a tela de detalhe
      // continuaria mostrando a timeline antiga até o usuário sair e
      // voltar. `ref.invalidate` é seguro mesmo para um provider que não
      // está sendo assistido no momento — ele só marca a próxima leitura
      // como precisando recarregar.
      ref.invalidate(patrimonioDetalheProvider(patrimonioId));
      ref.invalidate(patrimonioHistoricoProvider(patrimonioId));
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(patrimoniosControllerProvider);
      await ref.read(movimentacoesControllerProvider.notifier).recarregar();

      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      // Erro da RPC: nunca escondido, nunca uma segunda escrita
      // compensatória — só mostra a mensagem e mantém o formulário/revisão
      // preenchidos para o usuário corrigir ou tentar de novo.
      //
      // Concorrência: o estado mostrado na abertura do formulário pode ter
      // mudado antes da confirmação (outra sessão moveu o mesmo patrimônio
      // nesse meio-tempo) — a RPC já é a autoridade que rejeitou, mas a UI
      // ainda mostraria o status ANTIGO se o usuário voltasse para revisar.
      // Refaz a leitura do patrimônio (melhor esforço: se essa leitura
      // falhar, o erro original da RPC já foi mostrado, então não
      // sobrescreve por um erro secundário) para que "voltar e revisar de
      // novo" realmente parta do estado atual.
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
    final ultimoPasso = _step == _tituloPassos.length - 1;

    return PopScope(
      // Bloqueia fechar o diálogo (tecla Voltar/clique fora) enquanto a RPC
      // está em voo — nunca deixa o usuário achar que cancelou algo que já
      // está sendo gravado.
      canPop: !_isSubmitting,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 600, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Nova movimentação', style: AppTypography.cardTitle(context)),
                const SizedBox(height: AppSpacing.smd),
                _IndicadorDePasso(atual: _step, total: _tituloPassos.length),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Passo ${_step + 1} de ${_tituloPassos.length} · ${_tituloPassos[_step]}',
                  style: AppTypography.auxiliary(context),
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
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Flexible(child: SingleChildScrollView(child: _conteudoDoPasso())),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErroBanner(mensagem: _errorMessage!),
                ],
                const SizedBox(height: AppSpacing.lg),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
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

/// Barra de progresso do wizard: um segmento por passo, preenchido até o
/// passo atual — só reforça visualmente o que o texto "Passo X de N" já diz,
/// nunca a única fonte dessa informação (o texto continua presente para
/// leitores de tela e para os testes).
class _IndicadorDePasso extends StatelessWidget {
  const _IndicadorDePasso({required this.atual, required this.total});

  final int atual;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: i <= atual ? colorScheme.primary : colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const SizedBox(height: 4),
            ),
          ),
        ],
      ],
    );
  }
}

/// Banner de erro da RPC — mais visível que um texto solto, reaproveitando
/// `statusColors` (o mesmo token usado nos chips/cards de status do resto do
/// app) em vez de uma cor nova.
class _ErroBanner extends StatelessWidget {
  const _ErroBanner({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).statusColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: statusColors.errorBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.smd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: statusColors.errorForeground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                mensagem,
                style: AppTypography.body(context)?.copyWith(color: statusColors.errorForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
