import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../application/sei_resumo_diagnostico.dart';
import '../domain/sei_analise_resultado.dart';
import 'sei_import_controller.dart';
import 'steps/sei_arquivo_step.dart';
import 'steps/sei_revisao_step.dart';

/// Assistente de leitura de documentos SEI (PROMPT 11.1) — o fluxo inteiro
/// é: selecionar PDF → ler documento → extrair metadados/itens → cruzar com
/// o InvTec (leitura) → revisão → "Concluir análise". Termina aí: esta V1
/// NUNCA chama `registrarMovimentacao` (nem tem acesso a
/// `MovimentacaoRepository` — ver `SeiImportController`, seção 31).
Future<void> showImportarSeiDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (context) => const _ImportarSeiDialog());
}

class _ImportarSeiDialog extends ConsumerWidget {
  const _ImportarSeiDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seiImportControllerProvider);

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
                  Expanded(
                    child: Text('Importar documento SEI', style: AppTypography.pageSubtitle(context)),
                  ),
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
              Flexible(
                child: SingleChildScrollView(
                  child: switch (state.step) {
                    SeiImportStep.selecionarArquivo => const SeiArquivoStep(),
                    SeiImportStep.lendo => SeiLendoDocumentoStep(nomeArquivo: state.nomeArquivo),
                    SeiImportStep.revisao => state.resultado == null
                        ? const SizedBox.shrink()
                        : SeiRevisaoStep(resultado: state.resultado!),
                  },
                ),
              ),
              if (state.step == SeiImportStep.revisao) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton(
                          onPressed: () => ref.read(seiImportControllerProvider.notifier).reiniciar(),
                          child: const Text('Analisar outro documento'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Seção 10 (PROMPT 11.1.1): só diagnóstico — copia um
                        // resumo textual (JSON) da análise para facilitar
                        // auditoria sem depender de screenshots. Nunca
                        // dispara nenhuma escrita.
                        TextButton.icon(
                          onPressed: state.resultado == null
                              ? null
                              : () => _copiarResumoDiagnostico(context, state.resultado!),
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Copiar resumo da análise'),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Concluir análise'),
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
            Expanded(child: Text(mensagem, style: TextStyle(color: colorScheme.onErrorContainer))),
          ],
        ),
      ),
    );
  }
}
