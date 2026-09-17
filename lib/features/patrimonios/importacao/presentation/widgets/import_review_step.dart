import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../localizacoes/domain/localizacao.dart';
import '../../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../../../setores/domain/setor.dart';
import '../../../domain/patrimonio.dart';
import '../../../presentation/patrimonio_reference_data.dart';
import '../../domain/import_column_field.dart';
import '../../domain/import_row.dart';
import '../../domain/import_summary.dart';
import '../../domain/profiles/getec_summary.dart';
import '../../domain/profiles/import_profile_id.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Revisar" (seções 20-24): resumo, filtros, navegação para
/// problemas e decisão individual por linha antes da confirmação final.
class ImportReviewStep extends ConsumerWidget {
  const ImportReviewStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);

    if (state.carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final resumo = state.resumo;
    final linhas = state.linhasFiltradas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Arquivo: ${state.nomeArquivo ?? ''}', style: Theme.of(context).textTheme.bodyMedium),
        Text('Linhas lidas: ${resumo.total}', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        _ResumoFinalPanel(resumo: resumo),
        const SizedBox(height: AppSpacing.md),
        _ResumoChips(resumo: resumo, filtroAtual: state.filtroRevisao, onFiltrar: controller.filtrar),
        if (state.perfilAtivo == ImportProfileId.getecLegado) ...[
          const SizedBox(height: AppSpacing.md),
          _GetecResumoPanel(linhas: state.linhas),
        ],
        const SizedBox(height: AppSpacing.md),
        Card(
          child: SizedBox(
            height: 520,
            child: linhas.isEmpty
                ? const Center(child: Text('Nenhuma linha para esta categoria.'))
                : ListView.builder(
                    itemCount: linhas.length,
                    itemBuilder: (context, index) => _ImportRowTile(linha: linhas[index]),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
            FilledButton(
              onPressed: resumo.totalParaEnviar == 0
                  ? null
                  : () => _iniciarConfirmacao(context, ref, controller),
              child: Text('Importar (${resumo.totalParaEnviar})'),
            ),
          ],
        ),
      ],
    );
  }

  /// PROMPT 8.14, seção 7/9: a confirmação NUNCA fica disponível sem antes
  /// revalidar contra o Supabase real — a análise pode ter sido feita
  /// minutos antes, e outra pessoa pode ter cadastrado um dos mesmos
  /// números nesse intervalo. `revalidarAntesDeConfirmar` é sempre chamado
  /// aqui, no início deste fluxo, antes de mostrar o diálogo de
  /// confirmação — é assim, estruturalmente, que a "permissão de
  /// confirmar" fica condicionada à revalidação (nunca uma escrita: só
  /// leitura em lote).
  Future<void> _iniciarConfirmacao(BuildContext context, WidgetRef ref, PatrimonioImportController controller) async {
    await controller.revalidarAntesDeConfirmar();
    if (!context.mounted) return;

    final estadoAtual = ref.read(patrimonioImportControllerProvider);
    final resumoAtual = estadoAtual.resumo;
    final alterados = estadoAtual.revalidacaoNumerosQueViraramExistentes;

    if (resumoAtual.totalParaEnviar == 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nada a importar'),
          content: Text(
            alterados.isEmpty
                ? 'Não há mais nenhuma linha pronta para envio.'
                : 'A revalidação encontrou ${alterados.length} patrimônio(s) que já existem no '
                    'banco (${alterados.join(', ')}) — não há mais nenhuma linha nova para enviar.',
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar patrimônios?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alterados.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Revalidação: ${alterados.length} patrimônio(s) passaram a existir no banco '
                  'desde a análise (${alterados.join(', ')}) — foram movidos para "Já existente" '
                  'e NÃO serão enviados.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text('Novos: ${resumoAtual.prontos}'),
            Text('Avisos: ${resumoAtual.avisos}'),
            Text('Existentes (mantidos): ${resumoAtual.existentes}'),
            Text('Atualizações: ${resumoAtual.atualizar}'),
            Text('Ignorados: ${resumoAtual.ignorados}'),
            Text('Erros (não serão importados): ${resumoAtual.erros + resumoAtual.duplicados}'),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Serão enviados: ${resumoAtual.totalParaEnviar}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar importação'),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await controller.confirmarImportacao();
    }
  }
}

/// Resumo final da revisão (PROMPT 8.14, seção 4) — cada linha deste painel
/// vem de [ImportSummary] (calculado do estado EFETIVO das linhas, nunca de
/// uma fórmula separada), então nunca pode divergir do que os filtros abaixo
/// mostram. "Serão enviados" é sempre [ImportSummary.totalParaEnviar]: só
/// conta o que efetivamente vai para `cadastrar`/`atualizar`.
class _ResumoFinalPanel extends StatelessWidget {
  const _ResumoFinalPanel({required this.resumo});

  final ImportSummary resumo;

  @override
  Widget build(BuildContext context) {
    final linhas = <(String, int)>[
      ('Total no arquivo', resumo.total),
      ('Novos', resumo.novos),
      ('Já existentes', resumo.existentes),
      ('Duplicados no arquivo', resumo.duplicados),
      ('Avisos', resumo.avisos),
      ('Erros', resumo.erros),
      ('Ignorados', resumo.ignorados),
      ('Atualizações selecionadas', resumo.atualizar),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (rotulo, valor) in linhas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(rotulo), Text('$valor')],
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('SERÃO ENVIADOS', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${resumo.totalParaEnviar}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoChips extends StatelessWidget {
  const _ResumoChips({required this.resumo, required this.filtroAtual, required this.onFiltrar});

  final ImportSummary resumo;
  final ImportFiltroRevisao filtroAtual;
  final ValueChanged<ImportFiltroRevisao> onFiltrar;

  @override
  Widget build(BuildContext context) {
    final itens = <(ImportFiltroRevisao, int)>[
      (ImportFiltroRevisao.todos, resumo.total),
      (ImportFiltroRevisao.prontos, resumo.prontos),
      (ImportFiltroRevisao.avisos, resumo.avisos),
      (ImportFiltroRevisao.erros, resumo.erros),
      (ImportFiltroRevisao.duplicados, resumo.duplicados),
      (ImportFiltroRevisao.existentes, resumo.existentes),
      (ImportFiltroRevisao.atualizar, resumo.atualizar),
      (ImportFiltroRevisao.ignorados, resumo.ignorados),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (filtro, contagem) in itens)
          FilterChip(
            label: Text('${filtro.label}: $contagem'),
            selected: filtroAtual == filtro,
            onSelected: (_) => onFiltrar(filtro),
          ),
      ],
    );
  }
}

/// Resumo específico do perfil GETEC (seção 28) — complementa, nunca
/// substitui, os cartões genéricos de Prontos/Avisos/Erros acima.
class _GetecResumoPanel extends ConsumerWidget {
  const _GetecResumoPanel({required this.linhas});

  final List<ImportRow> linhas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiposAsync = ref.watch(tiposAtivosProvider);

    return tiposAsync.when(
      data: (tipos) {
        final nomePorTipoId = {for (final tipo in tipos) tipo.id: tipo.nome};
        final resumo = GetecResumo.fromRows(linhas, nomePorTipoId);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resumo GETEC', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                for (final tipo in resumo.tiposIdentificados)
                  Text('${tipo.nome}: ${tipo.quantidade}', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  'Não identificados: ${resumo.naoIdentificados}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Tombamentos anteriores encontrados: ${resumo.tombamentosAnterioresEncontrados}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Séries não informadas: ${resumo.seriesNaoInformadas}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Possíveis séries repetidas: ${resumo.possiveisSeriesRepetidas}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Linhas relacionadas a baixas: ${resumo.linhasComPossivelBaixa}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _ImportRowTile extends ConsumerWidget {
  const _ImportRowTile({required this.linha});

  final ImportRow linha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _abrirDecisoes(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            _StatusDot(status: linha.status, colorScheme: colorScheme),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(width: 48, child: Text('L.${linha.numeroLinha}', style: Theme.of(context).textTheme.bodySmall)),
            Expanded(
              flex: 2,
              child: Text(
                linha.numeroPatrimonio ?? '(sem número)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                [linha.marca, linha.modelo].where((v) => v != null && v.isNotEmpty).join(' '),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                linha.status.label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              icon: Icon(linha.ignoradaManualmente ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              tooltip: linha.ignoradaManualmente ? 'Reincluir linha' : 'Ignorar linha',
              onPressed: () => controller.alternarIgnorarLinha(linha, !linha.ignoradaManualmente),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirDecisoes(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ImportRowDecisionSheet(linha: linha),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status, required this.colorScheme});

  final ImportRowStatus status;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final cor = switch (status) {
      ImportRowStatus.pronto => colorScheme.primary,
      ImportRowStatus.aviso => Theme.of(context).statusColors.warningForeground,
      ImportRowStatus.erro => colorScheme.error,
      ImportRowStatus.ignorado => colorScheme.onSurfaceVariant,
      ImportRowStatus.existente => colorScheme.tertiary,
      ImportRowStatus.atualizar => colorScheme.secondary,
    };
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle));
  }
}

/// Painel de decisão de uma linha (aberto ao tocar nela): mostra os campos
/// lidos e as ações relevantes ao problema atual (tipo/setor não
/// encontrado, duplicidade no arquivo, patrimônio já existente).
class _ImportRowDecisionSheet extends ConsumerWidget {
  const _ImportRowDecisionSheet({required this.linha});

  final ImportRow linha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final tiposAsync = ref.watch(tiposAtivosProvider);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final todasAsLinhas = ref.watch(patrimonioImportControllerProvider).linhas;
    final localizacoesAsync = linha.destinoIdResolvido == null
        ? null
        : ref.watch(localizacoesAtivasPorSetorProvider(linha.destinoIdResolvido!));

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Linha ${linha.numeroLinha}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            // PROMPT 8.14, seção 6: decisão de importação sempre visível e
            // explícita — nunca deixar o usuário adivinhar pelo status.
            Text(
              _decisaoImportacaoLabel(linha),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: linha.seraEnviada
                    ? Theme.of(context).statusColors.successForeground
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Patrimônio: ${linha.numeroPatrimonio ?? '(sem número)'}'),
            if (linha.descricao != null) Text('Descrição: ${linha.descricao}'),
            if (linha.numeroSerie != null) Text('Série: ${linha.numeroSerie}'),
            if (linha.marca != null || linha.modelo != null)
              Text('Marca/Modelo: ${linha.marca ?? ''} ${linha.modelo ?? ''}'),
            // Seção 25 (perfil GETEC): mostra o tombamento anterior lido da
            // planilha, para o usuário validar que a informação será
            // preservada em `observacao` — não ocupa a tabela principal.
            if (linha.celulas[ImportColumnField.tombamentoAnterior] != null)
              Text('Tombamento anterior: ${linha.celulas[ImportColumnField.tombamentoAnterior]}'),
            if (linha.tipoInferidoAutomaticamente)
              Text(
                'Tipo inferido automaticamente pela descrição — você pode alterar.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            _CampoComOrigem(
              rotulo: 'Gerência destino',
              valor: _nomeSetor(setoresAsync, linha.destinoIdResolvido),
              usouPadrao: linha.usouDestinoPadrao,
            ),
            // Localização (seção 6): distinta da gerência acima — só
            // preenchida quando o perfil resolve uma (hoje, só GETEC).
            // "Sem localização" cobre tanto texto vazio quanto uma decisão
            // CONHECIDA (INTANGÍVEIS/TI - SOFTWARE/BAIXAS LOCALIZADAS —
            // nunca um erro, ver `GetecImportProfile`).
            if (linha.localizacaoTexto != null)
              Text(
                'Localização destino: ${_nomeLocalizacao(localizacoesAsync, linha.localizacaoIdResolvida) ?? 'Sem localização'}',
              ),
            _CampoComOrigem(
              rotulo: 'Origem',
              valor: _nomeSetor(setoresAsync, linha.origemIdResolvido),
              usouPadrao: linha.usouOrigemPadrao,
            ),
            _CampoComOrigem(
              rotulo: 'Data da entrada',
              valor: linha.dataEntrada == null ? null : _formatarDataHora(linha.dataEntrada!),
              usouPadrao: linha.usouDataPadrao,
            ),
            _CampoComOrigem(
              rotulo: 'Responsável',
              valor: linha.responsavelDestino,
              usouPadrao: linha.usouResponsavelPadrao,
            ),
            _CampoComOrigem(
              rotulo: 'Motivo',
              valor: linha.motivo,
              usouPadrao: linha.usouMotivoPadrao,
            ),
            if (linha.observacao != null && linha.observacao!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Observação: ${linha.observacao}'),
              ),
            const SizedBox(height: AppSpacing.md),
            for (final issue in linha.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      issue.severity == ImportIssueSeverity.erro ? Icons.error_outline : Icons.warning_amber_outlined,
                      size: 18,
                      color: issue.severity == ImportIssueSeverity.erro
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).statusColors.warningForeground,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(issue.message)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),

            if (linha.duplicadoNoArquivo && linha.numeroPatrimonioNormalizado != null) ...[
              Text('DUPLICADO NO ARQUIVO', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Motivo: número patrimonial repetido no próprio arquivo — '
                'nenhuma ocorrência será enviada enquanto o conflito não for resolvido.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('Patrimônio ${linha.numeroPatrimonio}', style: Theme.of(context).textTheme.bodySmall),
              // PROMPT 8.14, seção 1: mostra explicitamente QUAIS linhas do
              // arquivo têm o mesmo número — nunca escolhe "a primeira" ou
              // "a última" sozinho, só lista para o usuário decidir.
              for (final outra in todasAsLinhas.where(
                (l) => l.numeroPatrimonioNormalizado == linha.numeroPatrimonioNormalizado,
              ))
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: Text(
                    'Linha ${outra.numeroLinha}${identical(outra, linha) ? ' (esta)' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      controller.manterPrimeiraOcorrencia(linha.numeroPatrimonioNormalizado!);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Usar primeira ocorrência'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      controller.manterUltimaOcorrencia(linha.numeroPatrimonioNormalizado!);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Usar última ocorrência'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      controller.ignorarGrupoDuplicado(linha.numeroPatrimonioNormalizado!);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Ignorar todas'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            if (linha.existenteNoBanco != null) ...[
              Text('Patrimônio já existente no InvTec', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              _ComparacaoExistente(linha: linha),
              const SizedBox(height: AppSpacing.xs),
              const _NotaSetorResponsavel(),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('Manter existente'),
                    selected: linha.acaoExistente != ImportExistingAction.atualizarMetadados,
                    onSelected: (_) => controller.decidirExistente(linha, ImportExistingAction.manterExistente),
                  ),
                  ChoiceChip(
                    label: const Text('Atualizar metadados'),
                    selected: linha.acaoExistente == ImportExistingAction.atualizarMetadados,
                    onSelected: (_) => controller.decidirExistente(linha, ImportExistingAction.atualizarMetadados),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ] else ...[
              if (linha.tipoIdResolvido == null && linha.tipoTexto != null) ...[
                Text('Tipo "${linha.tipoTexto}" não encontrado', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                tiposAsync.when(
                  data: (tipos) => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (linha.tipoIdSugerido != null)
                        OutlinedButton(
                          onPressed: () => controller.definirTipoDaLinha(linha, linha.tipoIdSugerido),
                          child: Text(
                            'Usar ${tipos.firstWhere((t) => t.id == linha.tipoIdSugerido).nome}',
                          ),
                        ),
                      DropdownButton<String>(
                        hint: const Text('Selecionar tipo'),
                        items: [
                          for (final tipo in tipos) DropdownMenuItem(value: tipo.id, child: Text(tipo.nome)),
                        ],
                        onChanged: (id) => controller.definirTipoDaLinha(linha, id),
                      ),
                    ],
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (_, _) => const Text('Não foi possível carregar os tipos.'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (linha.destinoIdResolvido == null) ...[
                Text(
                  linha.setorTexto != null
                      ? 'Setor "${linha.setorTexto}" não encontrado'
                      : 'Nenhum setor de destino definido',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                setoresAsync.when(
                  data: (setores) => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (linha.destinoIdSugerido != null)
                        OutlinedButton(
                          onPressed: () => controller.definirDestinoDaLinha(linha, linha.destinoIdSugerido),
                          child: Text(
                            'Usar ${setores.firstWhere((s) => s.id == linha.destinoIdSugerido).nome}',
                          ),
                        ),
                      DropdownButton<String>(
                        hint: const Text('Selecionar setor'),
                        items: [
                          for (final setor in setores) DropdownMenuItem(value: setor.id, child: Text(setor.nome)),
                        ],
                        onChanged: (id) => controller.definirDestinoDaLinha(linha, id),
                      ),
                    ],
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (_, _) => const Text('Não foi possível carregar os setores.'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: Icon(linha.ignoradaManualmente ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                label: Text(linha.ignoradaManualmente ? 'Reincluir esta linha' : 'Ignorar esta linha'),
                onPressed: () {
                  controller.alternarIgnorarLinha(linha, !linha.ignoradaManualmente);
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparacaoExistente extends StatelessWidget {
  const _ComparacaoExistente({required this.linha});

  final ImportRow linha;

  @override
  Widget build(BuildContext context) {
    final detalhe = linha.existenteNoBanco!;
    final existente = detalhe.patrimonio;
    // PROMPT 8.14, seção 2: comparação completa o suficiente para o
    // usuário decidir com segurança — número patrimonial (título do painel,
    // já mostrado acima), descrição, tipo, setor atual, localização atual e
    // status atual, além dos campos que já existiam.
    final linhas = <(String, String?, String?)>[
      ('Descrição', existente.descricao, linha.descricao),
      ('Marca', existente.marca, linha.marca),
      ('Modelo', existente.modelo, linha.modelo),
      ('Série', existente.numeroSerie, linha.numeroSerie),
      ('Tipo atual', detalhe.tipoNome, null),
      ('Setor atual', detalhe.setorNome, null),
      ('Localização atual', detalhe.localizacaoNome ?? '(sem localização)', null),
      ('Status atual', existente.status.label, null),
    ];

    return Table(
      columnWidths: const {0: IntrinsicColumnWidth()},
      children: [
        const TableRow(
          children: [
            Text('Campo', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('InvTec', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Planilha', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        for (final (campo, atual, novo) in linhas)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.only(right: AppSpacing.sm), child: Text(campo)),
              Text(atual ?? '—'),
              Text(novo ?? '—'),
            ],
          ),
      ],
    );
  }
}

class _NotaSetorResponsavel extends StatelessWidget {
  const _NotaSetorResponsavel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Diferenças de setor ou responsável exigem uma movimentação '
      'patrimonial e não são aplicadas por esta importação.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Mostra um campo resolvido da linha com uma etiqueta "Valor padrão"
/// quando o valor não veio da própria planilha (seção 6) — importante em
/// cargas grandes, para o usuário não confundir dado real com padrão
/// aplicado silenciosamente.
class _CampoComOrigem extends StatelessWidget {
  const _CampoComOrigem({required this.rotulo, required this.valor, required this.usouPadrao});

  final String rotulo;
  final String? valor;
  final bool usouPadrao;

  @override
  Widget build(BuildContext context) {
    if (valor == null || valor!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$rotulo: '),
          Expanded(child: Text(valor!, overflow: TextOverflow.ellipsis)),
          if (usouPadrao) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Valor padrão',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Nome do setor resolvido, quando a lista de setores já carregou —
/// evita mostrar o UUID cru no painel de decisão da linha.
String? _nomeSetor(AsyncValue<List<Setor>> setoresAsync, String? setorId) {
  if (setorId == null) return null;
  return setoresAsync.maybeWhen(
    data: (setores) {
      for (final setor in setores) {
        if (setor.id == setorId) return setor.nome;
      }
      return setorId;
    },
    orElse: () => setorId,
  );
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}

/// Nome da localização resolvida, quando a lista já carregou — evita
/// mostrar o UUID cru. `null` quando não há id resolvido (localização
/// pendente/sem localização/ainda carregando), distinto de "carregou e não
/// achou" (que devolve o próprio id como último recurso).
String? _nomeLocalizacao(AsyncValue<List<Localizacao>>? localizacoesAsync, String? localizacaoId) {
  if (localizacaoId == null || localizacoesAsync == null) return null;
  return localizacoesAsync.maybeWhen(
    data: (localizacoes) {
      for (final localizacao in localizacoes) {
        if (localizacao.id == localizacaoId) return localizacao.nome;
      }
      return localizacaoId;
    },
    orElse: () => localizacaoId,
  );
}

/// Decisão de importação em uma frase (PROMPT 8.14, seção 6) — nunca deixa
/// o usuário adivinhar pelo status técnico sozinho.
String _decisaoImportacaoLabel(ImportRow linha) {
  if (linha.ignoradaManualmente) return 'Ignorado manualmente — não será enviado.';
  if (linha.duplicadoNoArquivo) return 'DUPLICADO NO ARQUIVO — bloqueado até decisão do usuário.';
  switch (linha.status) {
    case ImportRowStatus.pronto:
      return 'Será cadastrado como novo patrimônio.';
    case ImportRowStatus.aviso:
      return 'Será cadastrado como novo patrimônio (com aviso — não bloqueia).';
    case ImportRowStatus.erro:
      return 'NÃO será enviado — bloqueado por erro (ver detalhes abaixo).';
    case ImportRowStatus.existente:
      return 'Já existe no InvTec — será mantido como está, nenhuma escrita nesta linha.';
    case ImportRowStatus.atualizar:
      return 'Patrimônio já existente — metadados serão atualizados.';
    case ImportRowStatus.ignorado:
      return 'Ignorado — não será enviado.';
  }
}
