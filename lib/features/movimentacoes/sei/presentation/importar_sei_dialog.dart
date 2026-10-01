import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../application/sei_resumo_diagnostico.dart';
import '../application/sei_resumo_plano.dart';
import '../domain/sei_analise_resultado.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_plano_execucao.dart';
import 'sei_import_controller.dart';
import 'sei_pendencia_salvar_controller.dart';
import 'steps/sei_arquivo_step.dart';
import 'steps/sei_revisao_step.dart';

/// Assistente de leitura de documentos SEI — o fluxo inteiro é: selecionar
/// PDF → ler documento → extrair metadados/itens → cruzar com o InvTec
/// (leitura) → revisão → "Salvar como pendência". Salvar cria uma
/// SOLICITAÇÃO PENDENTE (`DocumentosSeiRepository.salvarRascunho`) — nunca
/// altera um patrimônio, nunca registra uma movimentação (esta versão nem
/// tem acesso a `MovimentacaoRepository` a partir daqui — ver
/// `SeiImportController`/`SeiPendenciaSalvarController`). Retorna `true`
/// quando uma pendência foi efetivamente salva, para a tela que abriu o
/// diálogo poder atualizar a lista de pendências.
Future<bool?> showImportarSeiDialog(BuildContext context) {
  return showDialog<bool>(context: context, builder: (context) => const _ImportarSeiDialog());
}

class _ImportarSeiDialog extends ConsumerWidget {
  const _ImportarSeiDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seiImportControllerProvider);
    final salvarState = ref.watch(seiPendenciaSalvarControllerProvider);

    ref.listen(seiPendenciaSalvarControllerProvider, (previous, next) {
      if (next.status == SeiSalvarPendenciaStatus.sucesso && next.documentoSalvo != null) {
        Navigator.of(context).pop(true);
      }
    });

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
                  Expanded(child: Text('Importar documento SEI', style: AppTypography.pageSubtitle(context))),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Lê um PDF do SEI, extrai os bens da tabela e compara com o InvTec — somente leitura, '
                'nenhuma movimentação é registrada aqui.',
                style: AppTypography.auxiliary(context),
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.mensagemErro != null) ...[
                _ErroBanner(mensagem: state.mensagemErro!),
                const SizedBox(height: AppSpacing.md),
              ],
              if (salvarState.mensagemErro != null) ...[
                _ErroBanner(mensagem: salvarState.mensagemErro!),
                const SizedBox(height: AppSpacing.md),
              ],
              if (salvarState.status == SeiSalvarPendenciaStatus.aguardandoConfirmacaoDuplicidade) ...[
                _DuplicidadeDocumentoBanner(duplicatas: salvarState.duplicatas),
                const SizedBox(height: AppSpacing.md),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: switch (state.step) {
                    SeiImportStep.selecionarArquivo => const SeiArquivoStep(),
                    SeiImportStep.lendo => SeiLendoDocumentoStep(nomeArquivo: state.nomeArquivo),
                    SeiImportStep.revisao =>
                      state.resultado == null ? const SizedBox.shrink() : SeiRevisaoStep(resultado: state.resultado!),
                  },
                ),
              ),
              if (state.step == SeiImportStep.revisao) ...[
                const SizedBox(height: AppSpacing.lg),
                // `OverflowBar` (não `Row`): o rodapé tem 5 botões em 2
                // grupos e pode superar a largura disponível. Cai para uma
                // coluna em vez de estourar; cada grupo também é um `Wrap`,
                // para quebrar linha internamente sem esconder um botão.
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: AppSpacing.lg,
                  overflowSpacing: AppSpacing.sm,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () => ref.read(seiImportControllerProvider.notifier).reiniciar(),
                          child: const Text('Analisar outro documento'),
                        ),
                        // Só diagnóstico — copia um resumo textual (JSON) da
                        // análise para facilitar auditoria sem depender de
                        // screenshots. Nunca dispara nenhuma escrita.
                        TextButton.icon(
                          onPressed: state.resultado == null
                              ? null
                              : () => _copiarResumoDiagnostico(context, state.resultado!),
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Copiar resumo da análise'),
                        ),
                        // Prévia somente leitura do que uma futura
                        // confirmação enviaria à RPC — nunca chama
                        // `registrarMovimentacao`.
                        TextButton.icon(
                          onPressed: state.resultado == null ? null : () => _copiarPlano(context, state.plano),
                          icon: const Icon(Icons.checklist_outlined),
                          label: Text('Copiar plano (${state.plano.totalItens})'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Fechar sem salvar'),
                        ),
                        // Importar e salvar um despacho cria uma solicitação
                        // pendente — nunca altera um patrimônio, nunca chama
                        // `registrarMovimentacao` (ver
                        // `SeiPendenciaSalvarController`).
                        FilledButton.icon(
                          onPressed: state.resultado == null || _salvando(salvarState.status)
                              ? null
                              : () => ref
                                    .read(seiPendenciaSalvarControllerProvider.notifier)
                                    .salvar(resultado: state.resultado!, execucao: state.execucao),
                          icon: _salvando(salvarState.status)
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: const Text('Salvar como pendência'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copiarResumoDiagnostico(BuildContext context, SeiAnaliseResultado resultado) async {
    await Clipboard.setData(ClipboardData(text: construirResumoDiagnosticoSei(resultado)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Resumo da análise copiado para a área de transferência.')));
  }

  Future<void> _copiarPlano(BuildContext context, SeiPlanoExecucao plano) async {
    await Clipboard.setData(ClipboardData(text: construirResumoPlanoExecucao(plano)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Plano de execução (leitura) copiado para a área de transferência.')),
      );
  }

  bool _salvando(SeiSalvarPendenciaStatus status) =>
      status == SeiSalvarPendenciaStatus.verificandoDuplicidade || status == SeiSalvarPendenciaStatus.salvando;
}

/// Mostra as possíveis duplicatas encontradas pelo número do documento SEI
/// (nunca pelo hash) e exige confirmação explícita antes de salvar mesmo
/// assim — nunca bloqueia nem prossegue sozinho.
class _DuplicidadeDocumentoBanner extends ConsumerWidget {
  const _DuplicidadeDocumentoBanner({required this.duplicatas});

  final List<SeiDocumentoPendente> duplicatas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_outlined, color: colorScheme.onTertiaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Já existe${duplicatas.length > 1 ? 'm' : ''} ${duplicatas.length} documento(s) pendente(s) '
                    'com este mesmo número SEI. Confira antes de salvar de novo.',
                    style: TextStyle(color: colorScheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final duplicata in duplicatas)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xl),
                child: Text(
                  '• ${duplicata.numeroDocumentoFormatado ?? duplicata.numeroDocumentoSei ?? duplicata.id} — '
                  '${duplicata.totalItens} item(ns), criado por ${duplicata.criadoPorNome}',
                  style: TextStyle(color: colorScheme.onTertiaryContainer),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => ref.read(seiPendenciaSalvarControllerProvider.notifier).confirmarApesarDeDuplicata(),
                child: const Text('Salvar mesmo assim'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErroBanner extends StatelessWidget {
  const _ErroBanner({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(mensagem, style: TextStyle(color: colorScheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}
