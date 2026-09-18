import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../sei_import_controller.dart';

/// Passo 1 do assistente (PROMPT 11.1, seção 4) — só seleciona e envia o
/// arquivo para leitura; nome/tamanho são mostrados assim que escolhidos,
/// quantidade de páginas só depois de o PDF ser aberto (passo "Lendo
/// documento..." é o próprio [SeiImportStep.lendo], sem UI própria aqui).
class SeiArquivoStep extends ConsumerWidget {
  const SeiArquivoStep({super.key});

  Future<void> _selecionarArquivo(WidgetRef ref) async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'Selecionar documento SEI (PDF)',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (arquivo == null) return;

    final bytes = await arquivo.readAsBytes();
    await ref.read(seiImportControllerProvider.notifier).selecionarArquivo(nomeArquivo: arquivo.name, bytes: bytes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 48),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Selecione o PDF de um documento SEI (ex.: Despacho de transferência de patrimônio). O '
              'arquivo é lido localmente — nenhuma movimentação é registrada nesta etapa, só uma análise.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _selecionarArquivo(ref),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Selecionar PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado "Lendo documento..." (seção 4) — extração de PDF + parsing +
/// cruzamento com o InvTec acontecem em segundo plano; a interface nunca
/// trava (nenhum `flutter analyze`/build travou testando com o PDF de 5
/// páginas / 33 bens de referência).
class SeiLendoDocumentoStep extends StatelessWidget {
  const SeiLendoDocumentoStep({super.key, this.nomeArquivo});

  final String? nomeArquivo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            const Text('Lendo documento...'),
            if (nomeArquivo != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(nomeArquivo!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
