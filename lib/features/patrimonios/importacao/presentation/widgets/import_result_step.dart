import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../domain/import_report_export.dart';
import '../../domain/import_row.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Resultado": contagens finais e o que fazer a seguir — nunca
/// trata uma falha parcial como fracasso da importação inteira, os
/// registros já concluídos permanecem.
class ImportResultStep extends ConsumerWidget {
  const ImportResultStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final enviadas = state.linhas.where((l) => l.seraEnviada).toList();
    final concluidas = enviadas.where((l) => l.resultado?.sucesso == true).toList();
    final falhas = enviadas.where((l) => l.resultado?.sucesso == false).toList();
    // "resultado desconhecido" (seção/item 3 da tarefa): uma linha que
    // deveria ter sido enviada mas ainda não tem nenhum resultado — ex.:
    // a importação foi cancelada no meio, ou o processo foi interrompido
    // antes de concluir esta linha. Nunca confundida com "ignorado"
    // (decisão explícita do usuário, nem chega a `seraEnviada`).
    final pendentes = enviadas.where((l) => l.resultado == null).toList();
    final novosOk = concluidas.where((l) => l.status == ImportRowStatus.pronto || l.status == ImportRowStatus.aviso);
    final atualizadosOk = concluidas.where((l) => l.status == ImportRowStatus.atualizar);
    final ignorados = state.linhas.where((l) => l.status == ImportRowStatus.ignorado).length;
    final avisos = state.linhas.where((l) => l.status == ImportRowStatus.aviso).length;
    // "já existentes" (item 3): mantidos como estavam, nunca enviados —
    // diferente de "Atualizados" (status `atualizar`, que É enviado).
    final jaExistentes = state.linhas.where((l) => l.status == ImportRowStatus.existente).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Importação concluída', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                Text('Novos patrimônios: ${novosOk.length}'),
                Text('Atualizados: ${atualizadosOk.length}'),
                Text('Ignorados: $ignorados'),
                Text('Falharam: ${falhas.length}'),
                Text('Avisos: $avisos'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Totais consolidados pedidos explicitamente: importados / já
        // existentes / rejeitados (falha) / pendentes (resultado
        // desconhecido) — derivados de `ImportRow.status`/`resultado`
        // já existentes, nunca um modelo paralelo.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Totais da rodada', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text('Importados: ${concluidas.length}'),
                Text('Já existentes (mantidos): $jaExistentes'),
                Text('Rejeitados (falha): ${falhas.length}'),
                Text('Pendentes (resultado desconhecido): ${pendentes.length}'),
              ],
            ),
          ),
        ),
        if (falhas.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Linhas que falharam', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  for (final linha in falhas.take(20))
                    Text('Linha ${linha.numeroLinha}: ${linha.resultado?.mensagemErro ?? 'Erro desconhecido'}'),
                  if (falhas.length > 20) Text('... e mais ${falhas.length - 20} linha(s).'),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: controller.tentarNovamenteFalhas,
                    child: const Text('Tentar novamente as falhas'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: enviadas.any((l) => l.resultado != null) ? () => _exportarCsv(context) : null,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Exportar CSV'),
            ),
            OutlinedButton(
              onPressed: () {
                controller.reiniciar();
                context.go('/patrimonios');
              },
              child: const Text('Concluir'),
            ),
            FilledButton(
              onPressed: () {
                controller.reiniciar();
                context.go('/patrimonios');
              },
              child: const Text('Ver patrimônios'),
            ),
          ],
        ),
      ],
    );
  }

  /// item 4 — relatório final exportável: reaproveita a função PURA já
  /// existente ([gerarCsvRelatorioImportacao]) e o mesmo padrão de
  /// salvamento local já usado em `InventarioRapidoPage`
  /// (`FilePicker.saveFile`, sem inventar um segundo mecanismo).
  Future<void> _exportarCsv(BuildContext context) async {
    final linhasComResultado = state.linhas.where((l) => l.resultado != null).map(ImportReportLinha.fromImportRow);
    final bytes = gerarCsvRelatorioImportacao(linhasComResultado.toList());
    final nomeArquivo = 'relatorio_importacao_${DateTime.now().millisecondsSinceEpoch}.csv';

    Uri? salvo;
    try {
      salvo = await FilePicker.saveFile(
        fileName: nomeArquivo,
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...bytes]),
        mimeType: 'text/csv',
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Não foi possível salvar o relatório.')));
      return;
    }
    if (!context.mounted || salvo == null) return; // usuário cancelou o diálogo.

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Relatório salvo: $nomeArquivo')));
  }
}
