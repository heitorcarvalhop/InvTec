import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../localizacoes/domain/localizacao.dart';
import '../../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../../../patrimonios/domain/patrimonio.dart';
import '../../../../patrimonios/presentation/patrimonio_reference_data.dart';
import '../../../../setores/domain/setor.dart';
import '../../../domain/movimentacao.dart';
import '../../nova_movimentacao_regras.dart';
import 'nova_movimentacao_rascunho.dart';

/// Passo 3 do wizard (PROMPT 10.2, seções 6-9): campos adaptados ao tipo
/// escolhido. A UI só adapta QUAIS campos aparecem — os valores enviados são
/// exatamente o que o usuário escolheu, sem a UI derivar ou "corrigir" nada
/// que a RPC já deriva/valida sozinha (seção 6/16 do prompt).
class DetalhesStep extends ConsumerWidget {
  const DetalhesStep({
    super.key,
    required this.patrimonio,
    required this.rascunho,
    required this.onChanged,
    required this.enabled,
  });

  final Patrimonio patrimonio;
  final NovaMovimentacaoRascunho rascunho;
  final VoidCallback onChanged;
  final bool enabled;

  void _onDestinoChanged(String? novoSetorId) {
    rascunho.destinoSetorId = novoSetorId;
    // Trocar de setor invalida qualquer localização já escolhida — ela
    // pertence ao setor ANTERIOR (mesmo raciocínio de
    // `PatrimonioFormPage._LocalizacaoSelector`, seção 26 da spec de
    // localizações: nunca oferecer localização de outra gerência).
    rascunho.localizacaoDestinoId = null;
    rascunho.localizacaoEscolha = LocalizacaoEscolha.manter;
    onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tipo = rascunho.tipo;
    if (tipo == null) return const SizedBox.shrink();

    final exigeDestino = tipoExigeDestino(tipo);
    final destinoOpcional = tipoDestinoOpcional(tipo);
    final exigeDestinoDiferente = tipoExigeDestinoDiferente(tipo);
    final permiteLimpar = tipoPermiteLimparLocalizacao(tipo);
    final exigeResponsavel = tipoExigeResponsavel(tipo);
    final proibeResponsavel = tipoProibeResponsavel(tipo);
    final interna = ehTransferenciaInterna(
      tipo: tipo,
      destinoId: rascunho.destinoSetorId,
      setorAtualId: patrimonio.setorAtualId,
    );
    final setorParaLocalizacao = rascunho.destinoSetorId ?? patrimonio.setorAtualId;

    // PROMPT 10.2.2, seção 6: a RPC real permite AJUSTE_INVENTARIO em
    // patrimônio BAIXADO só para registrar motivo/observação/documento/
    // chamado — proíbe mudar setor, localização (trocar OU limpar) e
    // responsável (responsável já é proibido para AJUSTE_INVENTARIO em
    // qualquer status). Nunca oferece esses campos aqui: a RPC rejeitaria
    // de qualquer forma, mas a UI não pode nem sugerir que é possível.
    final ajusteEmBaixado = tipo == MovimentacaoTipo.ajusteInventario && patrimonio.status == PatrimonioStatus.baixado;
    final mostraDestino = !ajusteEmBaixado && (exigeDestino || destinoOpcional);
    final mostraLocalizacao = !ajusteEmBaixado && tipoPermiteLocalizacao(tipo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detalhes da movimentação', style: AppTypography.pageSubtitle(context)),
        const SizedBox(height: AppSpacing.md),
        if (ajusteEmBaixado) ...[
          Text(
            'Este patrimônio está baixado: o ajuste de inventário aqui só registra '
            'motivo, observação, documento ou chamado — não altera setor, '
            'localização ou responsável, e não reativa o patrimônio.',
            style: AppTypography.auxiliary(context),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (mostraDestino) ...[
          _SetorDestinoField(
            setorAtualId: patrimonio.setorAtualId,
            value: rascunho.destinoSetorId,
            obrigatorio: exigeDestino,
            // Seção 3 do PROMPT 10.2.2: a RPC rejeita destino == setor atual
            // para estes tipos — nunca oferece a opção em vez de deixar o
            // usuário descobrir isso só depois de tentar confirmar.
            excluirSetorAtual: exigeDestinoDiferente,
            enabled: enabled,
            onChanged: _onDestinoChanged,
          ),
          if (interna) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Movimentação interna (mesmo setor): a localização de destino é '
              'obrigatória e precisa ser diferente da localização atual.',
              style: AppTypography.auxiliary(context)?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
        if (mostraLocalizacao) ...[
          if (permiteLimpar)
            _LocalizacaoComLimpar(
              setorId: setorParaLocalizacao,
              rascunho: rascunho,
              enabled: enabled,
              onChanged: onChanged,
              setorMudou: ajusteInventarioTrocouSetor(
                destinoId: rascunho.destinoSetorId,
                setorAtualId: patrimonio.setorAtualId,
              ),
            )
          else
            _LocalizacaoSimples(
              setorId: setorParaLocalizacao,
              value: rascunho.localizacaoDestinoId,
              obrigatoria: interna,
              enabled: enabled,
              // Movimentação interna: a localização atual pertence ao MESMO
              // setor de destino (setor não muda), então apareceria na
              // lista — a RPC rejeita se for reselecionada, então a UI nunca
              // a oferece (seção 4 do PROMPT 10.2.2).
              idExcluido: interna ? patrimonio.localizacaoAtualId : null,
              onChanged: (value) {
                rascunho.localizacaoDestinoId = value;
                onChanged();
              },
            ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (!proibeResponsavel) ...[
          TextFormField(
            controller: rascunho.responsavelController,
            enabled: enabled,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: exigeResponsavel ? 'Responsável *' : 'Responsável',
              helperText: exigeResponsavel
                  ? null
                  : 'Se preenchido, o patrimônio fica Em uso; se vazio, fica Disponível.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        TextFormField(
          controller: rascunho.motivoController,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: rascunho.observacaoController,
          enabled: enabled,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: rascunho.documentoController,
                enabled: enabled,
                decoration: const InputDecoration(labelText: 'Número do documento'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextFormField(
                controller: rascunho.chamadoController,
                enabled: enabled,
                decoration: const InputDecoration(labelText: 'Número do chamado'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SetorDestinoField extends ConsumerWidget {
  const _SetorDestinoField({
    required this.setorAtualId,
    required this.value,
    required this.obrigatorio,
    required this.excluirSetorAtual,
    required this.enabled,
    required this.onChanged,
  });

  final String setorAtualId;
  final String? value;
  final bool obrigatorio;

  /// PROMPT 10.2.2, seção 3: para os tipos em que a RPC rejeita
  /// `destino_id == setor_atual_id`, o setor atual nem aparece na lista —
  /// nunca depende só do erro da RPC para impedir essa escolha.
  final bool excluirSetorAtual;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);

    return setoresAsync.when(
      data: (setores) => DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: obrigatorio ? 'Setor de destino *' : 'Setor de destino'),
        items: [
          if (!obrigatorio) const DropdownMenuItem(value: null, child: Text('Manter o setor atual')),
          for (final Setor setor in setores)
            if (!excluirSetorAtual || setor.id != setorAtualId)
              DropdownMenuItem(value: setor.id, child: Text(setor.nome)),
        ],
        onChanged: enabled ? onChanged : null,
      ),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(
        'Não foi possível carregar os setores.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _LocalizacaoSimples extends ConsumerWidget {
  const _LocalizacaoSimples({
    required this.setorId,
    required this.value,
    required this.obrigatoria,
    required this.enabled,
    required this.onChanged,
    this.idExcluido,
  });

  final String setorId;
  final String? value;
  final bool obrigatoria;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  /// PROMPT 10.2.2, seção 4: em movimentação interna, a localização ATUAL
  /// não pode ser reescolhida como destino — a RPC rejeita ("precisa ser
  /// diferente da localização atual"), então nunca aparece na lista.
  final String? idExcluido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizacoesAsync = ref.watch(localizacoesAtivasPorSetorProvider(setorId));

    return localizacoesAsync.when(
      data: (localizacoes) => _dropdown(context, localizacoes),
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(
        'Não foi possível carregar as localizações.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _dropdown(BuildContext context, List<Localizacao> localizacoesTodas) {
    final localizacoes = idExcluido == null
        ? localizacoesTodas
        : localizacoesTodas.where((l) => l.id != idExcluido).toList();
    if (localizacoes.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: obrigatoria ? 'Localização de destino *' : 'Localização de destino'),
        child: const Text('Este setor não possui localizações cadastradas.'),
      );
    }
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: obrigatoria ? 'Localização de destino *' : 'Localização de destino',
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Sem localização')),
        for (final localizacao in localizacoes) DropdownMenuItem(value: localizacao.id, child: Text(localizacao.nome)),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Controle de três estados de AJUSTE_INVENTARIO (PROMPT 10.2, seção 15):
/// Manter / Definir nova / Limpar — nunca confunde os três (ver
/// `p_localizacao_destino_id` × `p_limpar_localizacao` em docs/database.md).
class _LocalizacaoComLimpar extends StatelessWidget {
  const _LocalizacaoComLimpar({
    required this.setorId,
    required this.rascunho,
    required this.enabled,
    required this.onChanged,
    required this.setorMudou,
  });

  final String setorId;
  final NovaMovimentacaoRascunho rascunho;
  final bool enabled;
  final VoidCallback onChanged;

  /// PROMPT 10.2.2, seção 5: quando o setor de destino é diferente do atual,
  /// "Manter a localização atual" deixa de fazer sentido (a localização
  /// atual pertence ao setor ANTERIOR) — o controle muda de 3 para 2
  /// segmentos e nunca usa a palavra "Manter" nesse modo.
  final bool setorMudou;

  @override
  Widget build(BuildContext context) {
    final segments = setorMudou
        ? const [
            ButtonSegment(value: LocalizacaoEscolha.definir, label: Text('Selecionar localização do novo setor')),
            ButtonSegment(value: LocalizacaoEscolha.manter, label: Text('Não informar localização')),
          ]
        : const [
            ButtonSegment(value: LocalizacaoEscolha.manter, label: Text('Manter atual')),
            ButtonSegment(value: LocalizacaoEscolha.definir, label: Text('Definir nova')),
            ButtonSegment(value: LocalizacaoEscolha.limpar, label: Text('Limpar')),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Localização', style: AppTypography.label(context)),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<LocalizacaoEscolha>(
          segments: segments,
          selected: {rascunho.localizacaoEscolha},
          onSelectionChanged: enabled
              ? (selecao) {
                  rascunho.localizacaoEscolha = selecao.first;
                  if (selecao.first != LocalizacaoEscolha.definir) {
                    rascunho.localizacaoDestinoId = null;
                  }
                  onChanged();
                }
              : null,
        ),
        if (rascunho.localizacaoEscolha == LocalizacaoEscolha.definir) ...[
          const SizedBox(height: AppSpacing.sm),
          _LocalizacaoSimples(
            setorId: setorId,
            value: rascunho.localizacaoDestinoId,
            obrigatoria: true,
            enabled: enabled,
            onChanged: (value) {
              rascunho.localizacaoDestinoId = value;
              onChanged();
            },
          ),
        ],
      ],
    );
  }
}
