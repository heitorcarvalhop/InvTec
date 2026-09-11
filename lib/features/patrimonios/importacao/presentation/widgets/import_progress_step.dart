import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Importando" (seção 26/27): progresso em lotes controlados, sem
/// travar a interface, com opção de cancelar antes que todas as linhas
/// tenham sido enviadas.
class ImportProgressStep extends ConsumerWidget {
  const ImportProgressStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final total = state.progressoTotal == 0 ? 1 : state.progressoTotal;
    final progresso = state.progressoAtual / total;
    final percentual = (progresso * 100).clamp(0, 100).toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Importando patrimônios', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Text('${state.progressoAtual} / ${state.progressoTotal}'),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: progresso.clamp(0, 1)),
            const SizedBox(height: AppSpacing.sm),
            Text('$percentual%'),
            const SizedBox(height: AppSpacing.lg),
            if (state.cancelamentoSolicitado)
              const Text('Cancelando após as operações em andamento — os registros já importados permanecerão.')
            else
              OutlinedButton(
                onPressed: controller.solicitarCancelamento,
                child: const Text('Cancelar importação'),
              ),
          ],
        ),
      ),
    );
  }
}
