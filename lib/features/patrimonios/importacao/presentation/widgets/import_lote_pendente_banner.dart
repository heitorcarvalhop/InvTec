import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../presentation/widgets/confirm_discard_dialog.dart';
import '../../domain/import_lote_persistencia.dart';
import '../patrimonio_import_controller.dart';

/// Banner exibido no passo "Selecionar arquivo" quando o controller
/// encontrou uma sessão de importação em lote incompleta (ver
/// [PatrimonioImportState.loteAnteriorPendente]/
/// [PatrimonioImportController.retomarLoteAnterior]) — nunca descarta nada
/// silenciosamente: "Retomar" pede ao usuário para re-selecionar o MESMO
/// arquivo original (a reconciliação por `numeroLinha` só é segura contra
/// o arquivo que gerou a sessão), e "Descartar" exige confirmação explícita
/// num diálogo.
///
/// GATE OBRIGATÓRIO (segunda camada, UI): mesmo que uma sessão pendente
/// exista (ex.: persistida numa versão anterior com a flag ligada), o botão
/// "Retomar" fica desabilitado enquanto
/// [PatrimonioImportController.importacaoLoteExecucaoHabilitada] for
/// `false` — só "Descartar" continua disponível. Nunca remove nem contorna
/// esse gate.
class ImportLotePendenteBanner extends ConsumerWidget {
  const ImportLotePendenteBanner({super.key, required this.sessao});

  final ImportLoteSessaoPersistida sessao;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    final sucesso = sessao.linhas.where((l) => l.status == ImportLoteLinhaPersistidaStatus.sucesso).length;
    final falha = sessao.linhas.where((l) => l.status == ImportLoteLinhaPersistidaStatus.falha).length;
    final pendente = sessao.linhas.where((l) => l.status == ImportLoteLinhaPersistidaStatus.pendente).length;
    final dataFormatada = _formatarDataHora(sessao.criadoEm);
    final podeRetomar = controller.importacaoLoteExecucaoHabilitada;

    return Card(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_outlined, color: colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Importação interrompida encontrada',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Arquivo "${sessao.nomeArquivo ?? '(nome não registrado)'}", iniciada em $dataFormatada: '
              '$sucesso linha(s) concluída(s) com sucesso, $falha com falha e $pendente ainda pendente(s).',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (podeRetomar)
              const Text(
                'Para retomar, selecione novamente o MESMO arquivo original abaixo — as linhas já '
                'concluídas com sucesso não serão reenviadas.',
              )
            else
              Text(
                'A retomada automática está temporariamente indisponível — você pode descartar esta '
                'sessão e revisar manualmente o que já foi importado.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => _confirmarDescarte(context, controller),
                  child: const Text('Descartar'),
                ),
                if (podeRetomar)
                  FilledButton.icon(
                    onPressed: () => _selecionarArquivoParaRetomar(context, ref),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Selecionar arquivo e retomar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarDescarte(BuildContext context, PatrimonioImportController controller) async {
    final descartar = await confirmarDescartarAlteracoes(
      context,
      title: 'Descartar esta importação pendente?',
      message:
          'As linhas já importadas com sucesso permanecem cadastradas. Esta ação só remove o registro '
          'local da sessão pendente — a tela deixará de oferecer "retomar".',
    );
    if (!descartar) return;
    await controller.descartarLoteAnterior();
  }

  Future<void> _selecionarArquivoParaRetomar(BuildContext context, WidgetRef ref) async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'Selecionar o mesmo arquivo original para retomar',
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
    );
    if (arquivo == null) return;

    final bytes = await arquivo.readAsBytes();
    await ref
        .read(patrimonioImportControllerProvider.notifier)
        .carregarArquivo(nomeArquivo: arquivo.name, bytes: bytes);
  }
}

String _duasCasas(int valor) => valor.toString().padLeft(2, '0');

String _formatarDataHora(DateTime data) =>
    '${_duasCasas(data.day)}/${_duasCasas(data.month)}/${data.year} '
    '${_duasCasas(data.hour)}:${_duasCasas(data.minute)}';
