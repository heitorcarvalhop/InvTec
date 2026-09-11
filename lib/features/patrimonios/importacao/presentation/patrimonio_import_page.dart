import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import 'patrimonio_import_controller.dart';
import 'patrimonio_import_state.dart';
import 'widgets/import_defaults_step.dart';
import 'widgets/import_locations_step.dart';
import 'widgets/import_mapping_step.dart';
import 'widgets/import_progress_step.dart';
import 'widgets/import_result_step.dart';
import 'widgets/import_review_step.dart';

/// Assistente de importação de patrimônios via planilha (rota
/// `/patrimonios/importar`). Nunca importa automaticamente — cada passo
/// exige uma ação explícita do usuário antes de avançar (seção 3).
class PatrimonioImportPage extends ConsumerWidget {
  const PatrimonioImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(patrimonioImportControllerProvider);

    return PopScope(
      canPop: state.step != ImportStep.importando,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cabecalho(step: state.step),
              const SizedBox(height: AppSpacing.lg),
              if (state.mensagemErro != null) ...[
                _ErroBanner(mensagem: state.mensagemErro!),
                const SizedBox(height: AppSpacing.md),
              ],
              _Conteudo(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.step});

  final ImportStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Importar planilha de patrimônios', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(_subtituloPorPasso(step), style: theme.textTheme.bodyMedium),
      ],
    );
  }

  String _subtituloPorPasso(ImportStep step) {
    switch (step) {
      case ImportStep.selecionarArquivo:
        return 'Passo 1 de 7 — Selecione o arquivo XLSX ou CSV.';
      case ImportStep.selecionarAba:
        return 'Passo 2 de 7 — Escolha a aba a importar.';
      case ImportStep.selecionarCabecalho:
        return 'Passo 3 de 7 — Confirme qual linha é o cabeçalho.';
      case ImportStep.mapearColunas:
        return 'Passo 4 de 7 — Mapeie as colunas da planilha.';
      case ImportStep.configurarPadroes:
        return 'Passo 5 de 7 — Configure os valores padrão da importação.';
      case ImportStep.resolverLocalizacoes:
        return 'Perfil GETEC — Mapeie as localizações encontradas para setores.';
      case ImportStep.revisar:
        return 'Passo 6 de 7 — Revise os dados antes de importar.';
      case ImportStep.importando:
        return 'Passo 7 de 7 — Importando...';
      case ImportStep.resultado:
        return 'Importação concluída.';
    }
  }
}

class _ErroBanner extends StatelessWidget {
  const _ErroBanner({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(mensagem, style: TextStyle(color: colorScheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conteudo extends ConsumerWidget {
  const _Conteudo({required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (state.step) {
      case ImportStep.selecionarArquivo:
        return _PassoArquivo(carregando: state.carregando);
      case ImportStep.selecionarAba:
        return _PassoAba(state: state);
      case ImportStep.selecionarCabecalho:
        return _PassoCabecalho(state: state);
      case ImportStep.mapearColunas:
        return ImportMappingStep(state: state);
      case ImportStep.configurarPadroes:
        return ImportDefaultsStep(state: state);
      case ImportStep.resolverLocalizacoes:
        return ImportLocationsStep(state: state);
      case ImportStep.revisar:
        return ImportReviewStep(state: state);
      case ImportStep.importando:
        return ImportProgressStep(state: state);
      case ImportStep.resultado:
        return ImportResultStep(state: state);
    }
  }
}

class _PassoArquivo extends ConsumerWidget {
  const _PassoArquivo({required this.carregando});

  final bool carregando;

  Future<void> _selecionarArquivo(WidgetRef ref) async {
    final arquivo = await FilePicker.pickFile(
      dialogTitle: 'Selecionar planilha de patrimônios',
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
    );
    if (arquivo == null) return;

    final bytes = await arquivo.readAsBytes();
    await ref
        .read(patrimonioImportControllerProvider.notifier)
        .carregarArquivo(nomeArquivo: arquivo.name, bytes: bytes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file_outlined, size: 48),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Selecione a planilha (.xlsx ou .csv) com os patrimônios a importar.\n'
              'O arquivo é lido localmente — nada é enviado ao Supabase até você '
              'confirmar a importação no fim do processo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => _selecionarArquivo(ref),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Selecionar arquivo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassoAba extends ConsumerWidget {
  const _PassoAba({required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);

    if (state.abas.isEmpty) {
      return const EmptyState(
        icon: Icons.error_outline,
        message: 'Nenhuma aba com dados foi encontrada nesta planilha.',
      );
    }

    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < state.abas.length; i++)
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(state.abas[i].nome),
              subtitle: Text('${state.abas[i].linhas.length} linha(s)'),
              onTap: () => controller.selecionarAba(i),
            ),
        ],
      ),
    );
  }
}

class _PassoCabecalho extends ConsumerWidget {
  const _PassoCabecalho({required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final aba = state.abaSelecionada;
    if (aba == null) return const SizedBox.shrink();

    final limite = aba.linhas.length < 15 ? aba.linhas.length : 15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Escolha qual linha contém os nomes das colunas (ex.: "Patrimônio", '
          '"Tipo", "Marca"...). Planilhas com título ou data no topo podem ter '
          'o cabeçalho em uma linha diferente da primeira.',
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: limite,
              itemBuilder: (context, index) {
                final linha = aba.linhas[index];
                final texto = linha
                    .map((c) => c?.toString() ?? '')
                    .where((t) => t.isNotEmpty)
                    .join(' | ');
                return RadioListTile<int>(
                  // ignore: deprecated_member_use
                  value: index,
                  // ignore: deprecated_member_use
                  groupValue: state.indiceCabecalho,
                  // ignore: deprecated_member_use
                  onChanged: (valor) => controller.definirIndiceCabecalho(valor!),
                  title: Text(
                    'Linha ${index + 1}: ${texto.isEmpty ? '(vazia)' : texto}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: controller.confirmarCabecalho,
            child: const Text('Continuar'),
          ),
        ),
      ],
    );
  }
}
