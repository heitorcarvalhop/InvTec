import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/domain/profile.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/presentation/current_permissions_controller.dart';
import '../domain/retificacao_comparacao.dart';
import '../domain/retificacao_relatorio.dart';
import 'retificacao_controller.dart';
import 'retificacao_execucao_relatorio.dart';

/// Retificação cadastral de unidade responsável — plano de reclassificação
/// SEMAD (104 patrimônios vinculados à GETEC que pertencem a outras
/// gerências). Protótipo local supervisionado: carrega o CSV, mostra a
/// prévia (nunca grava nada até confirmação explícita) e só então executa
/// item a item, com relatório final — nunca uma operação monolítica.
class RetificacaoPage extends ConsumerWidget {
  const RetificacaoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(retificacaoControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Retificação cadastral de unidade')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: switch (estado.fase) {
            RetificacaoFase.semArquivo => _SelecionarArquivoView(erro: estado.erroCarregamento),
            RetificacaoFase.carregando => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
            RetificacaoFase.revisao => _RevisaoView(estado: estado),
            RetificacaoFase.executando || RetificacaoFase.concluida => _ExecucaoView(estado: estado),
          },
        ),
      ),
    );
  }
}

class _SelecionarArquivoView extends ConsumerWidget {
  const _SelecionarArquivoView({required this.erro});

  final Object? erro;

  Future<void> _selecionarArquivo(WidgetRef ref) async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'Selecionar CSV do plano de reclassificação',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (arquivo == null) return;
    final bytes = await arquivo.readAsBytes();
    await ref.read(retificacaoControllerProvider.notifier).carregarCsv(bytes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(Icons.fact_check_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Selecione o CSV do plano de reclassificação (ex.: '
              'InvTec_plano_reclassificacao_104.csv) para comparar cada patrimônio, por UUID, '
              'contra o estado real do InvTec. Nenhuma gravação acontece nesta etapa.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: const Key('retificacao-selecionar-arquivo'),
              onPressed: () => _selecionarArquivo(ref),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Selecionar CSV'),
            ),
            if (erro != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Não foi possível carregar o arquivo: $erro',
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RevisaoView extends ConsumerWidget {
  const _RevisaoView({required this.estado});

  final RetificacaoState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lote = estado.lote;
    if (lote == null) return const EmptyState(icon: Icons.error_outline, message: 'Nenhum plano carregado.');

    final theme = Theme.of(context);
    final controller = ref.read(retificacaoControllerProvider.notifier);

    // Defesa em profundidade (mesmo padrão de ImportComparacaoResumoStep):
    // o botão de confirmação some se a sessão atual não for ADMIN/GESTOR
    // COM a permissão `patrimonio.rectify_unit` — a autoridade real
    // continua sendo a RPC no servidor, que também exige as duas.
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final ehAdminOuGestor = perfil == ProfilePerfil.admin || perfil == ProfilePerfil.gestor;
    final temPermissao = ref.hasPermission('patrimonio.rectify_unit');
    final podeExecutar = ehAdminOuGestor && temPermissao;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResumoCard(resumo: lote.resumo),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: SizedBox(
            height: 420,
            child: lote.itens.isEmpty
                ? const Center(child: Text('Nenhuma linha no arquivo.'))
                : ListView.builder(
                    key: const Key('retificacao-lista'),
                    itemCount: lote.itens.length,
                    itemBuilder: (context, index) => _ItemRetificacaoTile(item: lote.itens[index]),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('retificacao-justificativa'),
          decoration: const InputDecoration(
            labelText: 'Justificativa administrativa (obrigatória)',
            hintText: 'Ex.: Plano de reclassificação SEMAD — patrimônios indevidamente vinculados à GETEC.',
          ),
          maxLines: 2,
          onChanged: controller.definirJustificativa,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!podeExecutar)
          Text(
            'Sua sessão não tem perfil ADMIN/GESTOR ou a permissão patrimonio.rectify_unit — a '
            'execução não está disponível.',
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (!EnvConfig.retificacaoExecucaoHabilitada)
          // Trava operacional explícita — independente de perfil/permissão
          // e de a migration já existir no banco (ver comentário do
          // controller sobre EnvConfig.retificacaoExecucaoHabilitada).
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.block, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'A execução real desta campanha ainda está desabilitada por configuração. A '
                      'prévia/comparação continua disponível normalmente.',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          FilledButton.icon(
            key: const Key('retificacao-confirmar'),
            onPressed: lote.itensProntos.isEmpty || estado.justificativa.trim().isEmpty
                ? null
                : () => _abrirConfirmacao(context, ref, lote),
            icon: const Icon(Icons.play_arrow),
            label: Text('Retificar ${lote.itensProntos.length} patrimônio(s)'),
          ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final csv = gerarCsvPlanoRetificacao(lote);
              await FilePicker.saveFile(
                fileName: 'retificacao_previa_${DateTime.now().millisecondsSinceEpoch}.csv',
                bytes: Uint8List.fromList(_utf8ComBom(csv)),
                mimeType: 'text/csv',
              );
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Exportar prévia (CSV)'),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirConfirmacao(BuildContext context, WidgetRef ref, RetificacaoLote lote) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar retificação'),
        content: Text(
          '${lote.itensProntos.length} patrimônio(s) terão a unidade responsável corrigida. Esta '
          'ação registra uma movimentação RETIFICACAO_CADASTRAL auditável para cada um — nunca uma '
          'edição silenciosa. Confirma?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('retificacao-confirmar-dialogo'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retificar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await ref.read(retificacaoControllerProvider.notifier).confirmarExecucao();
  }
}

class _ResumoCard extends StatelessWidget {
  const _ResumoCard({required this.resumo});

  final RetificacaoResumo resumo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo da comparação', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                Text('Total: ${resumo.totalLinhas}'),
                Text('Prontos para retificar: ${resumo.prontos}', key: const Key('retificacao-resumo-prontos')),
                Text('Já na unidade correta: ${resumo.jaNaUnidadeCorreta}'),
                Text('Bloqueados: ${resumo.totalBloqueados}', key: const Key('retificacao-resumo-bloqueados')),
              ],
            ),
            if (resumo.bloqueadosPorMotivo.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Bloqueios por motivo', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final entry in resumo.bloqueadosPorMotivo.entries)
                    Chip(label: Text('${rotuloClassificacaoRetificacao(entry.key)}: ${entry.value}')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRetificacaoTile extends StatelessWidget {
  const _ItemRetificacaoTile({required this.item});

  final RetificacaoItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icone, cor) = switch (item.classificacao) {
      ClassificacaoRetificacao.pronto => (Icons.check_circle_outline, theme.colorScheme.primary),
      ClassificacaoRetificacao.jaNaUnidadeCorreta => (Icons.task_alt, theme.colorScheme.outline),
      _ => (Icons.error_outline, theme.colorScheme.error),
    };

    return ListTile(
      key: Key('retificacao-item-${item.linha.numeroLinha}'),
      leading: Icon(icone, color: cor),
      title: Text(item.linha.tombamentoOficial),
      subtitle: Text(
        item.classificacao == ClassificacaoRetificacao.pronto
            ? '${item.patrimonioDetalhe?.setorExibidoCompacto ?? "?"} → ${item.setorDestinoNome ?? "?"}'
            : item.motivoBloqueio ?? rotuloClassificacaoRetificacao(item.classificacao),
      ),
    );
  }
}

class _ExecucaoView extends ConsumerWidget {
  const _ExecucaoView({required this.estado});

  final RetificacaoState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(retificacaoControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  estado.executando ? 'Retificando (um por vez)...' : 'Retificação concluída',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${estado.processados} de ${estado.totalExecucao}',
                  key: const Key('retificacao-progresso'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (estado.executando) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('retificacao-parar'),
                  onPressed: controller.solicitarInterrupcao,
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('Parar após o item atual'),
                ),
              ),
            ],
            if (!estado.executando && estado.interrompidaPeloUsuario)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Card(
                  color: theme.colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.pause_circle_outline, color: theme.colorScheme.onTertiaryContainer),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Execução interrompida a pedido do usuário após '
                            '${estado.processados} de ${estado.totalExecucao} item(ns) — nenhuma '
                            'chamada em voo foi cancelada. Os itens restantes continuam pendentes; '
                            'inicie uma nova rodada para continuar.',
                            style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            _LinhaResumo(label: 'Retificados com sucesso', valor: estado.sucessos),
            _LinhaResumo(label: 'Recusados (nada foi gravado)', valor: estado.falhas),
            _LinhaResumo(label: 'Resultado desconhecido (rede)', valor: estado.desconhecidos),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            SizedBox(
              height: 320,
              child: ListView(
                children: [
                  for (final entrada in estado.itensExecucao.entries)
                    _LinhaItemExecucao(patrimonioId: entrada.key, item: entrada.value),
                ],
              ),
            ),
            if (!estado.executando) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    key: const Key('retificacao-exportar-relatorio'),
                    onPressed: () async {
                      final csv = gerarCsvExecucaoRetificacao(estado.itensExecucao);
                      await FilePicker.saveFile(
                        fileName: 'retificacao_resultado_${DateTime.now().millisecondsSinceEpoch}.csv',
                        bytes: Uint8List.fromList(_utf8ComBom(csv)),
                        mimeType: 'text/csv',
                      );
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Gerar relatório (CSV)'),
                  ),
                  if (!estado.temPendencia)
                    OutlinedButton(
                      key: const Key('retificacao-nova-rodada'),
                      onPressed: controller.reiniciar,
                      child: const Text('Nova retificação'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaItemExecucao extends ConsumerWidget {
  const _LinhaItemExecucao({required this.patrimonioId, required this.item});

  final String patrimonioId;
  final ItemExecucaoRetificacaoEstado item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(retificacaoControllerProvider.notifier);
    final (icone, cor, texto) = switch (item.status) {
      ItemExecucaoRetificacaoStatus.sucesso => (
        Icons.check_circle,
        theme.colorScheme.primary,
        item.resultado?.jaExecutado ?? false ? 'Já executado (retry seguro)' : 'Retificado',
      ),
      ItemExecucaoRetificacaoStatus.falha => (Icons.error, theme.colorScheme.error, item.falha?.message ?? 'Falhou'),
      ItemExecucaoRetificacaoStatus.resultadoDesconhecido => (
        Icons.help_outline,
        theme.colorScheme.tertiary,
        'Resultado desconhecido — nada foi confirmado nem descartado',
      ),
      ItemExecucaoRetificacaoStatus.executando ||
      ItemExecucaoRetificacaoStatus.pendente => (Icons.hourglass_empty, theme.colorScheme.outline, 'Aguardando'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        key: Key('retificacao-execucao-item-$patrimonioId'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patrimônio ${item.item.numeroPatrimonioExibicao ?? item.item.tombamentoEsperado}'),
                Text(texto, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (item.status == ItemExecucaoRetificacaoStatus.resultadoDesconhecido)
            TextButton(
              key: Key('retificacao-execucao-retry-$patrimonioId'),
              onPressed: () => controller.retryItem(patrimonioId),
              child: const Text('Tentar novamente'),
            ),
        ],
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({required this.label, required this.valor});

  final String label;
  final int valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Text('$valor', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// BOM (Byte Order Mark) UTF-8 — sem isso, o Excel abre acentuação de forma
/// incorreta em arquivos CSV UTF-8 puros (mesmo padrão de
/// inventario_rapido_page.dart).
List<int> _utf8ComBom(String texto) => [0xEF, 0xBB, 0xBF, ...utf8.encode(texto)];
