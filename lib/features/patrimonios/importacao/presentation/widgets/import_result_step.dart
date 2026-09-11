import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../domain/import_row.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Resultado" (seção 31): contagens finais e o que fazer a seguir —
/// nunca trata uma falha parcial como fracasso da importação inteira
/// (seção 28: os registros já concluídos permanecem).
class ImportResultStep extends ConsumerWidget {
  const ImportResultStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final enviadas = state.linhas.where((l) => l.seraEnviada).toList();
    final concluidas = enviadas.where((l) => l.resultado?.sucesso == true).toList();
    final falhas = enviadas.where((l) => l.resultado?.sucesso == false).toList();
    final novosOk = concluidas.where((l) => l.status == ImportRowStatus.pronto || l.status == ImportRowStatus.aviso);
    final atualizadosOk = concluidas.where((l) => l.status == ImportRowStatus.atualizar);
    final ignorados = state.linhas.where((l) => l.status == ImportRowStatus.ignorado).length;
    final avisos = state.linhas.where((l) => l.status == ImportRowStatus.aviso).length;

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
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () {
                controller.reiniciar();
                context.go('/patrimonios');
              },
              child: const Text('Concluir'),
            ),
            const SizedBox(width: AppSpacing.sm),
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
}
