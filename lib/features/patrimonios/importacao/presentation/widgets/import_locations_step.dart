import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../localizacoes/domain/localizacao.dart';
import '../../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../domain/import_column_field.dart';
import '../../domain/profiles/getec_import_profile.dart';
import '../../domain/text_similarity.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Sentinela do dropdown para "Importar sem localização" — distinto de
/// `null` (que significa "deixar pendente", seção 32).
const _semLocalizacao = '__sem_localizacao__';

/// Passo "Localizações encontradas" (seção 15/16/32/33), exclusivo do
/// perfil GETEC: antes de analisar linha a linha, mostra as localizações
/// únicas da planilha para o usuário mapear cada uma a uma `Localizacao`
/// já existente na gerência FIXA da carga — nunca cria localização nova, e
/// nunca confunde localização com setor/gerência (seção 30).
class ImportLocationsStep extends ConsumerWidget {
  const ImportLocationsStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final aba = state.abaSelecionada;
    final colunaLocalizacao = state.mapeamento.colunaDe(ImportColumnField.localizacao);
    final gerenciaId = state.padroes.destinoPadraoId;

    if (gerenciaId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Defina a gerência de destino padrão no passo anterior antes de '
            'resolver as localizações — toda esta carga pertence a uma única '
            'gerência.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
          ),
        ],
      );
    }

    if (aba == null || colunaLocalizacao == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nenhuma coluna de localização foi mapeada — todos os patrimônios '
            'desta carga ficarão sem localização (só com a gerência).',
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

    final localizacoesPlanilha = GetecImportProfile.localizacoesUnicas(
      linhas: aba.linhas,
      indiceCabecalho: state.indiceCabecalho,
      colunaLocalizacao: colunaLocalizacao,
    );

    final localizacoesAsync = ref.watch(localizacoesAtivasPorSetorProvider(gerenciaId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estas são as localizações encontradas na planilha, dentro da '
          'gerência GETEC. Mapeie cada uma para uma das localizações já '
          'cadastradas da gerência, ou confirme "Importar sem localização" — '
          'localização e gerência/setor são entidades diferentes, e o InvTec '
          'nunca cria localizações novas automaticamente.',
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: SizedBox(
            height: 420,
            child: localizacoesAsync.when(
              data: (localizacoesDaGerencia) {
                if (localizacoesDaGerencia.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        'Esta gerência não possui localizações cadastradas. Você '
                        'pode importar sem localização, ou cadastrar localizações '
                        'em Setores antes de continuar.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: localizacoesPlanilha.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final localizacaoPlanilha = localizacoesPlanilha[index];
                    final texto = localizacaoPlanilha.texto;
                    final chave = normalizarTextoComparacao(texto);
                    final semLocalizacaoEscolhido = state.localizacoesSemMapeamento.contains(chave);
                    final idEscolhido = state.mapeamentoLocalizacoes[chave];

                    // PROMPT 8.9: diferencia claramente as 3 categorias no
                    // preview — resolvida (manual ou automática, com ou sem
                    // canonicalização de apelido conhecido), sem localização
                    // por regra conhecida (nunca pendência), e não resolvida.
                    //
                    // PROMPT 8.13.1: `valorDropdown` é calculado NA MESMA
                    // passagem que decide `status`/`detalhe`, nunca
                    // separadamente — antes disso era possível o texto à
                    // esquerda dizer "Localização resolvida" (por resolução
                    // automática) enquanto o dropdown mostrava "Deixar
                    // pendente", uma contradição visual. O dropdown agora
                    // sempre reflete a decisão EFETIVA, mesmo quando ela veio
                    // de uma resolução automática/regra conhecida, não só de
                    // uma escolha manual anterior.
                    final _StatusPreviewLocalizacao status;
                    String? detalhe;
                    String? valorDropdown;
                    if (idEscolhido != null) {
                      status = _StatusPreviewLocalizacao.resolvida;
                      final escolhida = _localizacaoPorId(localizacoesDaGerencia, idEscolhido);
                      if (escolhida != null) detalhe = 'Mapeada manualmente para "${escolhida.nome}"';
                      valorDropdown = idEscolhido;
                    } else if (semLocalizacaoEscolhido) {
                      status = _StatusPreviewLocalizacao.resolvida;
                      detalhe = 'Confirmado pelo usuário: importar sem localização';
                      valorDropdown = _semLocalizacao;
                    } else if (GetecImportProfile.ehValorSemLocalizacaoConhecido(texto)) {
                      status = _StatusPreviewLocalizacao.semLocalizacaoRegra;
                      detalhe = null;
                      valorDropdown = _semLocalizacao;
                    } else {
                      final resolvidaAutomaticamente = GetecImportProfile.resolverLocalizacao(
                        texto,
                        localizacoesDaGerencia,
                      );
                      if (resolvidaAutomaticamente != null) {
                        status = _StatusPreviewLocalizacao.resolvida;
                        detalhe = normalizarTextoComparacao(resolvidaAutomaticamente.nome) != chave
                            ? 'Será importada como "${resolvidaAutomaticamente.nome}"'
                            : null;
                        valorDropdown = resolvidaAutomaticamente.id;
                      } else {
                        // nome oficial ausente entre as ativas OU
                        // genuinamente desconhecido: em ambos os casos ainda
                        // não há uma decisão efetiva — "Deixar pendente" é
                        // honesto aqui, nunca um valor inventado.
                        status = _StatusPreviewLocalizacao.naoResolvida;
                        detalhe = null;
                        valorDropdown = null;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(status.icone, size: 18, color: status.cor(context)),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(texto, overflow: TextOverflow.ellipsis),
                                Text(
                                  status.rotulo,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(color: status.cor(context)),
                                ),
                                if (detalhe != null)
                                  Text(
                                    detalhe,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              '${localizacaoPlanilha.contagem}',
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String?>(
                              key: ValueKey('loc-dropdown-$chave-$valorDropdown'),
                              initialValue: valorDropdown,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true, hintText: 'Selecionar localização'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Deixar pendente')),
                                const DropdownMenuItem(
                                  value: _semLocalizacao,
                                  child: Text('Importar sem localização'),
                                ),
                                for (final localizacao in localizacoesDaGerencia)
                                  DropdownMenuItem(value: localizacao.id, child: Text(localizacao.nome)),
                              ],
                              onChanged: (valor) {
                                if (valor == _semLocalizacao) {
                                  controller.definirImportarSemLocalizacao(texto, true);
                                } else {
                                  controller.definirImportarSemLocalizacao(texto, false);
                                  controller.definirMapeamentoLocalizacao(texto, valor);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Não foi possível carregar as localizações.')),
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

Localizacao? _localizacaoPorId(List<Localizacao> localizacoes, String id) {
  for (final localizacao in localizacoes) {
    if (localizacao.id == id) return localizacao;
  }
  return null;
}

/// As 3 categorias de status do preview de localização (PROMPT 8.9) —
/// nunca um "não resolvido" disfarçado de resolvido, nem uma regra
/// conhecida disfarçada de pendência.
enum _StatusPreviewLocalizacao { resolvida, semLocalizacaoRegra, naoResolvida }

extension on _StatusPreviewLocalizacao {
  String get rotulo => switch (this) {
    _StatusPreviewLocalizacao.resolvida => 'Localização resolvida',
    _StatusPreviewLocalizacao.semLocalizacaoRegra => 'Sem localização — regra conhecida',
    _StatusPreviewLocalizacao.naoResolvida => 'Localização não resolvida',
  };

  IconData get icone => switch (this) {
    _StatusPreviewLocalizacao.resolvida => Icons.check_circle_outline,
    _StatusPreviewLocalizacao.semLocalizacaoRegra => Icons.info_outline,
    _StatusPreviewLocalizacao.naoResolvida => Icons.error_outline,
  };

  Color cor(BuildContext context) => switch (this) {
    _StatusPreviewLocalizacao.resolvida => Theme.of(context).statusColors.successForeground,
    _StatusPreviewLocalizacao.semLocalizacaoRegra => Theme.of(context).colorScheme.onSurfaceVariant,
    _StatusPreviewLocalizacao.naoResolvida => Theme.of(context).colorScheme.error,
  };
}
