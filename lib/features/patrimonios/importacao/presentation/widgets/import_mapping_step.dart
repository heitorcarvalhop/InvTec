import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../domain/import_column_field.dart';
import '../../domain/profiles/import_profile_id.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Mapear colunas" (seção 8/9): para cada coluna da planilha, o
/// usuário escolhe a que campo do InvTec ela corresponde (ou "Não importar
/// esta coluna"). A sugestão automática já vem pré-selecionada, mas nada é
/// aplicado sem o usuário ver e poder corrigir.
class ImportMappingStep extends ConsumerWidget {
  const ImportMappingStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final cabecalho = state.linhaCabecalho;

    // coluna -> campo atualmente escolhido (inverso do mapeamento por campo)
    final campoPorColuna = <int, ImportColumnField>{
      for (final entry in state.mapeamento.colunaPorCampo.entries)
        if (entry.value != null) entry.value!: entry.key,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.perfilDetectado == ImportProfileId.getecLegado) ...[
          _GetecProfileBanner(state: state, controller: controller),
          const SizedBox(height: AppSpacing.md),
        ],
        const Text(
          'Para cada coluna da planilha, escolha o campo correspondente no '
          'InvTec. Colunas que não se aplicam podem ficar como "Não importar".',
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                for (var coluna = 0; coluna < cabecalho.length; coluna++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            cabecalho[coluna]?.toString().isNotEmpty == true
                                ? cabecalho[coluna].toString()
                                : '(coluna ${coluna + 1})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        const Icon(Icons.arrow_forward, size: 16),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<ImportColumnField?>(
                            initialValue: campoPorColuna[coluna],
                            isExpanded: true,
                            decoration: const InputDecoration(isDense: true),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Não importar esta coluna')),
                              for (final campo in ImportColumnField.values)
                                DropdownMenuItem(
                                  // já usado por outra coluna: ainda listado, mas
                                  // escolher aqui move o campo para esta coluna.
                                  value: campo,
                                  child: Text(campo.label, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (campo) {
                              final anterior = campoPorColuna[coluna];
                              if (anterior != null) controller.definirColuna(anterior, null);
                              if (campo != null) controller.definirColuna(campo, coluna);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
            FilledButton(onPressed: controller.avancarParaPadroes, child: const Text('Continuar')),
          ],
        ),
      ],
    );
  }
}

/// Banner de reconhecimento do perfil GETEC (seção 27): nunca esconde do
/// usuário que um perfil específico foi detectado, e deixa explícito que
/// usá-lo é uma escolha — não algo aplicado silenciosamente.
class _GetecProfileBanner extends StatelessWidget {
  const _GetecProfileBanner({required this.state, required this.controller});

  final PatrimonioImportState state;
  final PatrimonioImportController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ativo = state.perfilAtivo == ImportProfileId.getecLegado;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: colorScheme.onSecondaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Formato de inventário GETEC reconhecido.',
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ativo
                  ? 'Perfil GETEC ativo: mapeamento sugerido, inferência de tipo pela '
                        'descrição e as regras específicas desta planilha (ex.: "10" '
                        'como não informado) estão em uso.'
                  : 'Você pode aplicar o mapeamento sugerido para esta planilha ou '
                        'configurar tudo manualmente, como em uma planilha genérica.',
              style: TextStyle(color: colorScheme.onSecondaryContainer),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: ativo ? null : controller.ativarPerfilGetec,
                  child: const Text('Usar configuração sugerida'),
                ),
                OutlinedButton(
                  onPressed: !ativo ? null : controller.ignorarPerfilSugerido,
                  child: const Text('Configurar manualmente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
