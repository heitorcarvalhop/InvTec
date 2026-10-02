import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/routing/back_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/page_header.dart';
import '../../presentation/widgets/confirm_discard_dialog.dart';
import 'patrimonio_import_controller.dart';
import 'patrimonio_import_state.dart';
import 'widgets/import_comparacao_resumo_step.dart';
import 'widgets/import_comparacao_step.dart';
import 'widgets/import_defaults_step.dart';
import 'widgets/import_locations_step.dart';
import 'widgets/import_mapping_step.dart';
import 'widgets/import_progress_step.dart';
import 'widgets/import_result_step.dart';
import 'widgets/import_review_step.dart';
import 'widgets/import_tipos_pendentes_step.dart';

/// Assistente de importação de patrimônios via planilha (rota
/// `/patrimonios/importar`). Nunca importa automaticamente — cada passo
/// exige uma ação explícita do usuário antes de avançar.
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
              _Cabecalho(state: state),
              const SizedBox(height: AppSpacing.md),
              _StepIndicator(step: state.step),
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

/// Progresso "relevante" é tudo além do passo inicial de seleção de
/// arquivo: a partir dali o usuário já tomou decisões (aba, cabeçalho,
/// mapeamento, padrões, localizações, tipos, revisão...) que seriam
/// perdidas ao sair sem confirmar. O passo [ImportStep.resultado] também
/// sai direto — a importação já terminou (com sucesso ou falhas parciais
/// já registradas), não há "alterações" pendentes para descartar.
bool _temProgressoRelevante(PatrimonioImportState state) {
  switch (state.step) {
    case ImportStep.selecionarArquivo:
    case ImportStep.resultado:
      return false;
    default:
      return true;
  }
}

Future<void> _cancelarImportacao(
  BuildContext context,
  WidgetRef ref,
  PatrimonioImportState state,
) async {
  if (_temProgressoRelevante(state)) {
    final descartar = await confirmarDescartarAlteracoes(
      context,
      message: 'O progresso desta importação ainda não foi salvo e será perdido.',
    );
    if (!descartar) return;
  }
  if (!context.mounted) return;
  ref.read(patrimonioImportControllerProvider.notifier).reiniciar();
  backOrGo(context, '/patrimonios');
}

class _Cabecalho extends ConsumerWidget {
  const _Cabecalho({required this.state});

  final PatrimonioImportState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mesma regra do `PopScope` da página (não interromper uma importação
    // em andamento): enquanto `step == importando`, não oferece saída.
    final podeCancelar = state.step != ImportStep.importando;
    return InvTecPageHeader(
      title: 'Importar planilha de patrimônios',
      subtitle: _subtituloPorPasso(state.step),
      backLabel: 'Cancelar importação',
      onBack: podeCancelar ? () => _cancelarImportacao(context, ref, state) : null,
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
        return 'Perfil GETEC — Mapeie as localizações encontradas para as '
            'localizações cadastradas da gerência GETEC.';
      case ImportStep.resolverTipos:
        return 'Tipos pendentes — associe um tipo a cada patrimônio bloqueado.';
      case ImportStep.revisar:
        return 'Passo 6 de 7 — Revise os dados antes de importar.';
      case ImportStep.importando:
        return 'Passo 7 de 7 — Importando...';
      case ImportStep.resultado:
        return 'Importação concluída.';
      case ImportStep.compararRevisao:
        return 'Comparar e Atualizar (ADMIN) — revise as divergências encontradas contra o InvTec.';
      case ImportStep.compararResumo:
        return 'Comparar e Atualizar (ADMIN) — resumo das decisões, só conferência.';
    }
  }
}

/// Posição (0-based) de [step] entre os 7 marcos visuais do assistente —
/// indicador de progresso puramente visual, nunca controla navegação. Os
/// passos condicionais (Localizações/Tipos pendentes, hoje
/// só do perfil GETEC) ficam agrupados dentro de "Padrões", já que só
/// existem entre "Padrões" e "Revisão"; "Importando" fica agrupado com
/// "Resultado" (é uma transição rápida, não um marco à parte).
int _posicaoDoPasso(ImportStep step) {
  switch (step) {
    case ImportStep.selecionarArquivo:
      return 0;
    case ImportStep.selecionarAba:
      return 1;
    case ImportStep.selecionarCabecalho:
      return 2;
    case ImportStep.mapearColunas:
      return 3;
    case ImportStep.configurarPadroes:
    case ImportStep.resolverLocalizacoes:
    case ImportStep.resolverTipos:
      return 4;
    case ImportStep.revisar:
    case ImportStep.compararRevisao:
      return 5;
    case ImportStep.importando:
    case ImportStep.resultado:
    case ImportStep.compararResumo:
      return 6;
  }
}

const _rotulosPassos = ['Arquivo', 'Aba', 'Cabeçalho', 'Colunas', 'Padrões', 'Revisão', 'Resultado'];

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final ImportStep step;

  @override
  Widget build(BuildContext context) {
    final atual = _posicaoDoPasso(step);
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColors = Theme.of(context).surfaceColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smd),
      decoration: BoxDecoration(
        color: surfaceColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: surfaceColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < _rotulosPassos.length; i++) ...[
              _StepDot(numero: i + 1, label: _rotulosPassos[i], estado: _estadoDoPasso(i, atual)),
              if (i < _rotulosPassos.length - 1)
                Container(
                  width: AppSpacing.lg,
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: i < atual ? colorScheme.primary : colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  _StepDotEstado _estadoDoPasso(int indice, int atual) {
    if (indice < atual) return _StepDotEstado.concluido;
    if (indice == atual) return _StepDotEstado.atual;
    return _StepDotEstado.pendente;
  }
}

enum _StepDotEstado { concluido, atual, pendente }

class _StepDot extends StatelessWidget {
  const _StepDot({required this.numero, required this.label, required this.estado});

  final int numero;
  final String label;
  final _StepDotEstado estado;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (background, foreground, border, borderWidth) = switch (estado) {
      _StepDotEstado.concluido => (colorScheme.primary, colorScheme.onPrimary, colorScheme.primary, 1.5),
      _StepDotEstado.atual => (colorScheme.primaryContainer, colorScheme.onPrimaryContainer, colorScheme.primary, 2.5),
      _StepDotEstado.pendente => (Colors.transparent, colorScheme.onSurfaceVariant, colorScheme.outlineVariant, 1.5),
    };
    final labelColor = switch (estado) {
      _StepDotEstado.atual => colorScheme.primary,
      _StepDotEstado.concluido => colorScheme.onSurface,
      _StepDotEstado.pendente => colorScheme.onSurfaceVariant,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: borderWidth),
          ),
          child: estado == _StepDotEstado.concluido
              ? Icon(Icons.check, size: 18, color: foreground)
              : Text('$numero', style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.caption(context)?.copyWith(
            color: labelColor,
            fontWeight: estado == _StepDotEstado.atual ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
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
      case ImportStep.resolverTipos:
        return ImportTiposPendentesStep(state: state);
      case ImportStep.revisar:
        return ImportReviewStep(state: state);
      case ImportStep.importando:
        return ImportProgressStep(state: state);
      case ImportStep.resultado:
        return ImportResultStep(state: state);
      case ImportStep.compararRevisao:
        return ImportComparacaoStep(state: state);
      case ImportStep.compararResumo:
        return ImportComparacaoResumoStep(state: state);
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

    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colorScheme.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.upload_file_outlined, size: 32, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Selecione a planilha', style: AppTypography.cardTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Com os patrimônios a importar. O arquivo é lido localmente — nada é '
                  'enviado ao Supabase até você confirmar a importação no fim do processo.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(context)?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  children: const [_FormatoBadge(label: 'XLSX'), _FormatoBadge(label: 'CSV')],
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
        ),
      ),
    );
  }
}

class _FormatoBadge extends StatelessWidget {
  const _FormatoBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final surfaceColors = Theme.of(context).surfaceColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: surfaceColors.tableHeader,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: surfaceColors.border),
      ),
      child: Text(label, style: AppTypography.caption(context)),
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
