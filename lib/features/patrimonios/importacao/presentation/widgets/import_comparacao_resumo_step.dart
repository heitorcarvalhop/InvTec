import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/config/env_config.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../auth/domain/profile.dart';
import '../../../../auth/presentation/auth_controller.dart';
import '../comparacao_execucao_controller.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Resumo das decisões" (PROMPT 11.6.3, seção 8 + PROMPT 11.6.4).
/// Continua mostrando o resumo só de LEITURA de
/// [PatrimonioImportState.resumoDecisoes] — a diferença do PROMPT 11.6.4 é
/// que agora existe um botão real de execução, que só aparece depois de uma
/// confirmação explícita com justificativa administrativa.
class ImportComparacaoResumoStep extends ConsumerWidget {
  const ImportComparacaoResumoStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final theme = Theme.of(context);
    final resumo = state.resumoDecisoes;
    final execucao = ref.watch(comparacaoExecucaoControllerProvider);
    // PROMPT 11.6.4, seção 3 — defesa em profundidade: mesmo alcançando esta
    // tela (já protegida no controller/toggle), o botão de execução some se
    // a sessão atual não for ADMIN (ex.: perfil rebaixado no meio da
    // revisão) — a autoridade de verdade continua sendo a RPC no servidor.
    final ehAdmin = ref.watch(authControllerProvider).value?.profile?.perfil == ProfilePerfil.admin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resumo das decisões', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                _LinhaResumo(
                  label: 'Patrimônios com alterações selecionadas',
                  valor: resumo.patrimoniosComAlteracaoSelecionada,
                ),
                _LinhaResumo(label: 'Campos a atualizar', valor: resumo.camposAAtualizar),
                _LinhaResumo(
                  label: 'Alterações de localização/setor',
                  valor: resumo.alteracoesLocalizacaoOuSetor,
                ),
                _LinhaResumo(label: 'Alterações de metadados', valor: resumo.alteracoesMetadados),
                _LinhaResumo(label: 'Patrimônios ignorados', valor: resumo.patrimoniosIgnorados),
                _LinhaResumo(label: 'Itens bloqueados', valor: resumo.itensBloqueados),
                _LinhaResumo(label: 'Decisões ainda pendentes', valor: resumo.decisoesPendentes),
              ],
            ),
          ),
        ),
        if (resumo.alteracoesLocalizacaoOuSetor > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onTertiaryContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Alterações de localização/setor serão registradas como uma movimentação '
                      'patrimonial auditável (regularização cadastral) — nunca uma sobrescrita '
                      'silenciosa do setor/responsável atual. Uma troca de setor sem uma nova '
                      'localização selecionada limpa a localização atual (ela pertence só ao setor '
                      'anterior).',
                      style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (execucao.fase == ComparacaoExecucaoFase.ociosa) ...[
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Nenhuma alteração foi enviada ao banco ainda. Idênticos nunca são reenviados, '
                      'novos nunca são cadastrados automaticamente, e nenhum campo/patrimônio ignorado '
                      'é alterado.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!ehAdmin)
            Text(
              'Sua sessão não tem mais perfil ADMIN — a execução não está disponível.',
              style: TextStyle(color: theme.colorScheme.error),
            )
          else if (!EnvConfig.comparacaoExecucaoHabilitada)
            // PROMPT 11.6.5, seção 9 — trava operacional explícita: a
            // execução real fica indisponível até uma liberação explícita
            // de configuração, independente de perfil/kReleaseMode/a
            // migration já existir no banco.
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'A execução real desta funcionalidade ainda está desabilitada por configuração '
                        '(pendente de homologação). A comparação e a revisão de divergências continuam '
                        'disponíveis normalmente.',
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            FilledButton.icon(
              key: const Key('comparacao-executar-alteracoes'),
              onPressed: resumo.patrimoniosComAlteracaoSelecionada == 0 || resumo.decisoesPendentes > 0
                  ? null
                  : () => _abrirConfirmacao(context, ref, resumo),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Executar alterações selecionadas'),
            ),
          if (resumo.decisoesPendentes > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Resolva as ${resumo.decisoesPendentes} decisões ainda pendentes antes de executar.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ] else
          _PainelExecucao(execucao: execucao),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: execucao.executando ? null : controller.voltar,
            child: const Text('Voltar para a lista'),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirConfirmacao(BuildContext context, WidgetRef ref, ComparacaoDecisoesResumo resumo) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final exigeJustificativa = resumo.alteracoesLocalizacaoOuSetor > 0;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar execução'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${resumo.patrimoniosComAlteracaoSelecionada} patrimônio(s) serão alterados, '
                '${resumo.camposAAtualizar} campo(s) atualizados e '
                '${resumo.alteracoesLocalizacaoOuSetor} movimentação(ões) de regularização registradas.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('comparacao-justificativa'),
                controller: controller,
                decoration: InputDecoration(
                  labelText: exigeJustificativa
                      ? 'Justificativa administrativa (obrigatória)'
                      : 'Justificativa administrativa (opcional)',
                ),
                maxLines: 3,
                validator: (valor) {
                  if (!exigeJustificativa) return null;
                  if (valor == null || valor.trim().isEmpty) {
                    return 'Alterações de localização/setor exigem uma justificativa.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('comparacao-confirmar-execucao'),
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? true)) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Executar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    final comparacao = state.comparacao;
    if (comparacao == null) return;
    await ref
        .read(comparacaoExecucaoControllerProvider.notifier)
        .confirmar(comparacao: comparacao, decisoes: state.decisoes, justificativa: controller.text.trim());
  }
}

class _PainelExecucao extends ConsumerWidget {
  const _PainelExecucao({required this.execucao});

  final ComparacaoExecucaoState execucao;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  execucao.executando ? 'Executando alterações...' : 'Execução concluída',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text('${execucao.processados} de ${execucao.total}', key: const Key('comparacao-execucao-progresso')),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (execucao.executando) const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            _LinhaResumo(label: 'Aplicados com sucesso', valor: execucao.sucessos),
            _LinhaResumo(label: 'Recusados (nada foi gravado)', valor: execucao.falhas),
            _LinhaResumo(label: 'Resultado desconhecido (rede)', valor: execucao.desconhecidos),
            if (!execucao.executando) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              for (final entrada in execucao.itens.entries) _LinhaItemExecucao(patrimonioId: entrada.key, item: entrada.value),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaItemExecucao extends ConsumerWidget {
  const _LinhaItemExecucao({required this.patrimonioId, required this.item});

  final String patrimonioId;
  final ItemExecucaoEstado item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(comparacaoExecucaoControllerProvider.notifier);
    final (icone, cor, texto) = switch (item.status) {
      ItemExecucaoStatus.sucesso => (
        Icons.check_circle,
        theme.colorScheme.primary,
        item.resultado?.jaExecutado ?? false ? 'Já executado (retry seguro)' : 'Aplicado',
      ),
      ItemExecucaoStatus.falha => (Icons.error, theme.colorScheme.error, item.falha?.message ?? 'Falhou'),
      ItemExecucaoStatus.resultadoDesconhecido => (
        Icons.help_outline,
        theme.colorScheme.tertiary,
        'Resultado desconhecido — nada foi confirmado nem descartado',
      ),
      ItemExecucaoStatus.executando || ItemExecucaoStatus.pendente => (Icons.hourglass_empty, theme.colorScheme.outline, 'Aguardando'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        key: Key('comparacao-execucao-item-$patrimonioId'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patrimônio ${item.decisao.numeroPatrimonio}'),
                Text(texto, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (item.status == ItemExecucaoStatus.resultadoDesconhecido) ...[
            TextButton(
              key: Key('comparacao-execucao-reconciliar-$patrimonioId'),
              onPressed: () => controller.reconciliarItem(patrimonioId),
              child: const Text('Consultar'),
            ),
            TextButton(
              key: Key('comparacao-execucao-retry-$patrimonioId'),
              onPressed: () => controller.retryItem(patrimonioId),
              child: const Text('Tentar novamente'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({required this.label, required this.valor});

  final String label;
  final int valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Text('$valor', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
