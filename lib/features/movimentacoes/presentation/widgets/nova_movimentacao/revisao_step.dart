import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../../../localizacoes/data/localizacao_repository_supabase.dart';
import '../../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../../patrimonios/presentation/patrimonio_reference_data.dart';
import '../../../domain/movimentacao.dart';
import '../../nova_movimentacao_regras.dart';
import '../movimentacao_tipo_visual.dart';
import 'nova_movimentacao_rascunho.dart';

/// Passo 4 do wizard (PROMPT 10.2, seção 10): mostra exatamente o que vai
/// ser enviado à RPC antes de qualquer escrita — nenhuma RPC é chamada
/// antes deste passo. Resolve nomes (setor/localização) sob demanda: o
/// wizard nunca pré-carrega todos os setores/localizações só para exibir
/// aqui, e resolver aqui (não guardar o nome desde o passo Detalhes) também
/// garante que o rótulo mostrado é sempre coerente com o id realmente
/// selecionado.
class RevisaoStep extends ConsumerWidget {
  const RevisaoStep({
    super.key,
    required this.detalhe,
    required this.rascunho,
    required this.onConfirmacaoBaixaChanged,
  });

  final PatrimonioDetalhe detalhe;
  final NovaMovimentacaoRascunho rascunho;
  final ValueChanged<bool> onConfirmacaoBaixaChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tipo = rascunho.tipo!;
    final patrimonio = detalhe.patrimonio;
    final (icon, kind) = visualDoTipoMovimentacao(tipo);
    final interna = ehTransferenciaInterna(
      tipo: tipo,
      destinoId: rascunho.destinoSetorId,
      setorAtualId: patrimonio.setorAtualId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Revisão', style: AppTypography.pageSubtitle(context)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Confira os dados antes de confirmar — esta ação grava um '
          'registro permanente no histórico.',
          style: AppTypography.auxiliary(context),
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patrimonio.numeroPatrimonio ?? '(sem número)',
                        style: AppTypography.pageSubtitle(context),
                      ),
                    ),
                    StatusChip(label: tipo.label, kind: kind, icon: icon),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (tipo == MovimentacaoTipo.baixa)
                  const _CampoRevisao(rotulo: 'Setor/localização/responsável', valor: 'Preservados (sem alteração)')
                else if (tipo == MovimentacaoTipo.alteracaoResponsavel) ...[
                  _CampoRevisao(rotulo: 'De (responsável atual)', valor: patrimonio.responsavelAtual ?? '—'),
                  _CampoRevisao(
                    rotulo: 'Para (novo responsável)',
                    valor: rascunho.responsavelController.text.trim(),
                  ),
                ] else ...[
                  _CampoRevisao(rotulo: 'De', valor: detalhe.setorNome),
                  if (detalhe.localizacaoNome != null)
                    _CampoRevisao(rotulo: 'Localização de', valor: detalhe.localizacaoNome!),
                  if (patrimonio.responsavelAtual != null)
                    _CampoRevisao(rotulo: 'Responsável de', valor: patrimonio.responsavelAtual!),
                  const SizedBox(height: AppSpacing.sm),
                  if (interna)
                    const _CampoRevisao(rotulo: 'Para', valor: 'Mesmo setor (movimentação interna)')
                  else if (rascunho.destinoSetorId != null)
                    _NomeSetor(setorId: rascunho.destinoSetorId!)
                  else
                    const _CampoRevisao(rotulo: 'Para', valor: 'Setor mantido'),
                  _LocalizacaoDestinoResumo(
                    rascunho: rascunho,
                    mostrarNaoInformadaQuandoVazio:
                        tipo == MovimentacaoTipo.ajusteInventario &&
                        ajusteInventarioTrocouSetor(
                          destinoId: rascunho.destinoSetorId,
                          setorAtualId: patrimonio.setorAtualId,
                        ),
                  ),
                  if (rascunho.responsavelController.text.trim().isNotEmpty)
                    _CampoRevisao(rotulo: 'Responsável para', valor: rascunho.responsavelController.text.trim()),
                ],
                if (rascunho.motivoController.text.trim().isNotEmpty)
                  _CampoRevisao(rotulo: 'Motivo', valor: rascunho.motivoController.text.trim()),
                if (rascunho.observacaoController.text.trim().isNotEmpty)
                  _CampoRevisao(rotulo: 'Observação', valor: rascunho.observacaoController.text.trim()),
                if (rascunho.documentoController.text.trim().isNotEmpty)
                  _CampoRevisao(rotulo: 'Documento', valor: rascunho.documentoController.text.trim()),
                if (rascunho.chamadoController.text.trim().isNotEmpty)
                  _CampoRevisao(rotulo: 'Chamado', valor: rascunho.chamadoController.text.trim()),
              ],
            ),
          ),
        ),
        if (tipo == MovimentacaoTipo.baixa) ...[
          const SizedBox(height: AppSpacing.md),
          _AvisoBaixa(confirmado: rascunho.confirmacaoBaixa, onChanged: onConfirmacaoBaixaChanged),
        ],
      ],
    );
  }
}

class _NomeSetor extends ConsumerWidget {
  const _NomeSetor({required this.setorId});

  final String setorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reaproveita a MESMA lista de setores ativos já usada no passo
    // Detalhes (sem nova consulta) — o destino, quando preenchido, é
    // sempre um setor ativo (a RPC rejeita inativo).
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    String? nome;
    for (final setor in setoresAsync.value ?? const []) {
      if (setor.id == setorId) {
        nome = setor.nome;
        break;
      }
    }
    return _CampoRevisao(rotulo: 'Para', valor: nome ?? '...');
  }
}

class _LocalizacaoDestinoResumo extends ConsumerWidget {
  const _LocalizacaoDestinoResumo({required this.rascunho, required this.mostrarNaoInformadaQuandoVazio});

  final NovaMovimentacaoRascunho rascunho;

  /// PROMPT 10.2.2, seção 5: quando AJUSTE_INVENTARIO trocou de setor e
  /// nenhuma localização foi escolhida, a RPC real ainda assim zera a
  /// localização (regra "(b)" — setor mudou sem localização nova). A
  /// revisão deixa isso explícito em vez de simplesmente omitir a linha,
  /// para nunca dar a entender que "nada muda".
  final bool mostrarNaoInformadaQuandoVazio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rascunho.localizacaoEscolha == LocalizacaoEscolha.limpar) {
      return const _CampoRevisao(rotulo: 'Localização para', valor: 'Não informada (limpa)');
    }
    if (rascunho.localizacaoDestinoId == null) {
      if (mostrarNaoInformadaQuandoVazio) {
        return const _CampoRevisao(rotulo: 'Localização para', valor: 'Não informada');
      }
      return const SizedBox.shrink();
    }
    final nomeAsync = ref.watch(_localizacaoPorIdProvider(rascunho.localizacaoDestinoId!));
    return _CampoRevisao(rotulo: 'Localização para', valor: nomeAsync.value ?? '...');
  }
}

class _AvisoBaixa extends StatelessWidget {
  const _AvisoBaixa({required this.confirmado, required this.onChanged});

  final bool confirmado;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined, color: colorScheme.onErrorContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Baixa é uma operação relevante: depois de confirmada, este '
                    'patrimônio só aceita Ajuste de inventário — nenhuma '
                    'movimentação comum o devolve à circulação.',
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: confirmado,
              onChanged: (value) => onChanged(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Confirmo que desejo dar baixa neste patrimônio.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoRevisao extends StatelessWidget {
  const _CampoRevisao({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(rotulo, style: AppTypography.auxiliary(context))),
          Expanded(child: Text(valor, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}

final _localizacaoPorIdProvider = FutureProvider.autoDispose.family<String?, String>((ref, localizacaoId) async {
  final localizacao = await ref.watch(localizacaoRepositoryProvider).buscarPorId(localizacaoId);
  return localizacao?.nome;
});
