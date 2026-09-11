import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../presentation/patrimonio_reference_data.dart';
import '../../domain/import_column_field.dart';
import '../../domain/profiles/getec_import_profile.dart';
import '../../domain/text_similarity.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Localizações encontradas" (seção 15/16), exclusivo do perfil
/// GETEC: antes de analisar linha a linha, mostra as localizações únicas da
/// planilha para o usuário mapear cada uma a um setor existente de uma vez
/// só — sem criar setores automaticamente (seção 16).
class ImportLocationsStep extends ConsumerWidget {
  const ImportLocationsStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final aba = state.abaSelecionada;
    final colunaLocalizacao = state.mapeamento.colunaDe(ImportColumnField.setor);

    if (aba == null || colunaLocalizacao == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nenhuma coluna de localização foi mapeada.'),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
              FilledButton(onPressed: controller.analisar, child: const Text('Analisar planilha')),
            ],
          ),
        ],
      );
    }

    final localizacoes = GetecImportProfile.localizacoesUnicas(
      linhas: aba.linhas,
      indiceCabecalho: state.indiceCabecalho,
      colunaLocalizacao: colunaLocalizacao,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estas são as localizações encontradas na planilha. Mapeie cada uma '
          'para um setor do InvTec — o mapeamento se aplica a todas as linhas '
          'com essa localização. Localizações não mapeadas usam o destino '
          'padrão configurado no passo anterior, ou ficam pendentes de decisão '
          'individual na revisão.',
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: SizedBox(
            height: 420,
            child: setoresAsync.when(
              data: (setores) => ListView.separated(
                itemCount: localizacoes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final localizacao = localizacoes[index];
                  final chave = localizacao.texto;
                  final resolvida = GetecImportProfile.localizacaoResolvida(
                    chave,
                    setores,
                    state.mapeamentoLocalizacoes,
                  );
                  final setorEscolhidoNome = state.mapeamentoLocalizacoes[normalizarTextoComparacao(chave)];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          resolvida ? Icons.check_circle_outline : Icons.error_outline,
                          size: 18,
                          color: resolvida ? Colors.green : Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 3,
                          child: Text(localizacao.texto, overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            '${localizacao.contagem}',
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String?>(
                            initialValue: setorEscolhidoNome,
                            isExpanded: true,
                            decoration: const InputDecoration(isDense: true, hintText: 'Selecionar setor'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Deixar pendente')),
                              for (final setor in setores)
                                DropdownMenuItem(value: setor.nome, child: Text(setor.nome)),
                            ],
                            onChanged: (nomeSetor) =>
                                controller.definirMapeamentoLocalizacao(localizacao.texto, nomeSetor),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Não foi possível carregar os setores.')),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
            FilledButton(onPressed: controller.analisar, child: const Text('Analisar planilha')),
          ],
        ),
      ],
    );
  }
}
