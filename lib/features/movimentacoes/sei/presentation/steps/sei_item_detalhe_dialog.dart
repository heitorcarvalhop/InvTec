import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/status_chip.dart';
import '../../../../localizacoes/presentation/localizacoes_providers.dart';
import '../../../../patrimonios/domain/patrimonio.dart';
import '../../domain/sei_decisao_campo.dart';
import '../../domain/sei_item_execucao_estado.dart';
import '../../domain/sei_item_extraido.dart';
import '../../domain/sei_validacao_item.dart';
import '../sei_import_controller.dart';
import '../sei_status_visual.dart';

/// Detalhe de uma linha da revisão (PROMPT 11.1, seção 24) — três blocos:
/// dados do documento, estado atual no InvTec, validação (checks/avisos/
/// bloqueios). Somente leitura: nenhuma ação de escrita aqui — a única
/// interação é a confirmação da seção 7 (PROMPT 11.2), que só altera estado
/// de preparação local, nunca o InvTec.
Future<void> showSeiItemDetalheDialog(BuildContext context, SeiValidacaoItem item) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SeiItemDetalheDialog(item: item),
  );
}

class _SeiItemDetalheDialog extends ConsumerWidget {
  const _SeiItemDetalheDialog({required this.item});

  final SeiValidacaoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, kind, label) = visualDoStatusSei(item.status);
    final patrimonio = item.patrimonioEncontrado?.patrimonio;
    final estado = ref.watch(seiImportControllerProvider).execucao[item.item.linha];

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.item.numeroPatrimonio ?? 'Patrimônio não identificado',
                        style: AppTypography.pageSubtitle(context),
                      ),
                    ),
                    StatusChip(label: label, kind: kind, icon: icon),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Secao(
                  titulo: 'DADOS DO DOCUMENTO',
                  children: [
                    _Campo('Patrimônio', item.item.numeroPatrimonio),
                    _Campo('Equipamento', item.item.equipamento),
                    _Campo('Origem', item.item.unidadeOrigemTexto),
                    _Campo('Destino', item.item.unidadeDestinoTexto),
                    _Campo('Chamado', item.item.numeroChamado),
                    _Campo('Página', 'pg. ${item.item.paginaOrigem}'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Secao(
                  titulo: 'ESTADO ATUAL NO INVTEC',
                  children: patrimonio == null
                      ? [const _Campo('Patrimônio', 'Não encontrado no InvTec')]
                      : [
                          _Campo('Status', patrimonio.status.label),
                          _Campo(
                            'Setor',
                            item.patrimonioEncontrado!.setorExibidoCompacto,
                            tooltip:
                                item.patrimonioEncontrado!.setorExibidoCompacto == item.patrimonioEncontrado!.setorNome
                                ? null
                                : item.patrimonioEncontrado!.setorNome,
                          ),
                          _Campo('Localização', item.patrimonioEncontrado!.localizacaoNome ?? 'Não informada'),
                          _Campo('Responsável', patrimonio.responsavelAtual ?? 'Nenhum'),
                        ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Secao(
                  titulo: 'VALIDAÇÃO',
                  children: [
                    for (final check in item.checks) _ItemLista(icon: Icons.check, texto: check, cor: Colors.green),
                    for (final aviso in item.avisos)
                      _ItemLista(
                        icon: Icons.warning_amber_outlined,
                        texto: aviso,
                        cor: Theme.of(context).statusColors.warningForeground,
                      ),
                    for (final bloqueio in item.bloqueios)
                      _ItemLista(icon: Icons.block, texto: bloqueio, cor: Theme.of(context).colorScheme.error),
                  ],
                ),
                // PROMPT 11.2, seção 7: os itens de confiança MÉDIA (número
                // reconstruído a partir de texto intercalado no PDF — ex.:
                // os estabilizadores) exigem confirmação explícita, linha a
                // linha, antes de poderem entrar em qualquer seleção futura.
                // Nunca promovido automaticamente a confiança alta.
                if (item.item.confiancaPatrimonio == SeiConfianca.media) ...[
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    color: Theme.of(context).statusColors.warningBackground,
                    child: CheckboxListTile(
                      value: estado?.avisoConfirmado ?? false,
                      onChanged: (v) =>
                          ref.read(seiImportControllerProvider.notifier).confirmarAviso(item.item.linha, v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text('Conferi o número deste patrimônio no documento original.'),
                      subtitle: const Text(
                        'Uma linha não conferida não pode ser selecionada para uma futura execução em lote.',
                      ),
                    ),
                  ),
                ],
                // PROMPT 11.2.1, seção 4: decisão EXPLÍCITA para os dois
                // campos que o PDF nunca informa — nunca resolvidos
                // silenciosamente, mesmo com o documento inteiro
                // "autorizado" (seção 5).
                if (patrimonio != null && item.destino.entidadeEncontrada != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _DecisaoDestinoSecao(
                    linha: item.item.linha,
                    destinoSetorId: item.destino.entidadeEncontrada!.id,
                    responsavelAtual: patrimonio.responsavelAtual,
                    estado: estado,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// PROMPT 11.2.1, seção 4: decisão humana explícita para localização e
/// responsável de destino — o PDF nunca traz nenhum dos dois, e a RPC real
/// de TRANSFERENCIA grava exatamente o que for enviado (não preserva o
/// valor atual quando omitido). Localização só oferece opções REAIS e
/// ativas do setor de destino (nunca inventadas); responsável aceita texto
/// livre ou confirmação explícita de ausência.
class _DecisaoDestinoSecao extends ConsumerStatefulWidget {
  const _DecisaoDestinoSecao({
    required this.linha,
    required this.destinoSetorId,
    required this.responsavelAtual,
    required this.estado,
  });

  final int linha;
  final String destinoSetorId;
  final String? responsavelAtual;
  final SeiItemExecucaoEstado? estado;

  @override
  ConsumerState<_DecisaoDestinoSecao> createState() => _DecisaoDestinoSecaoState();
}

class _DecisaoDestinoSecaoState extends ConsumerState<_DecisaoDestinoSecao> {
  late final _responsavelController = TextEditingController(text: widget.estado?.responsavelDestino ?? '');

  @override
  void dispose() {
    _responsavelController.dispose();
    super.dispose();
  }

  String _rotuloDecisao(SeiDecisaoCampo decisao) => switch (decisao) {
    SeiDecisaoCampo.pendente => 'Pendente — decisão necessária',
    SeiDecisaoCampo.definido => 'Definida',
    SeiDecisaoCampo.confirmadoSemInformacao => 'Confirmado sem informação',
  };

  @override
  Widget build(BuildContext context) {
    final decisaoLocalizacao = widget.estado?.decisaoLocalizacao ?? SeiDecisaoCampo.pendente;
    final decisaoResponsavel = widget.estado?.decisaoResponsavel ?? SeiDecisaoCampo.pendente;
    final localizacoesAsync = ref.watch(localizacoesAtivasPorSetorProvider(widget.destinoSetorId));
    final notifier = ref.read(seiImportControllerProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DECISÃO PARA EXECUÇÃO (o documento não informa nenhum dos dois)',
              style: AppTypography.label(context)?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Localização de destino — ${_rotuloDecisao(decisaoLocalizacao)}', style: AppTypography.body(context)),
            const SizedBox(height: AppSpacing.xs),
            localizacoesAsync.when(
              data: (localizacoes) => Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final localizacao in localizacoes)
                    ChoiceChip(
                      label: Text(localizacao.nome),
                      selected: widget.estado?.localizacaoDestinoId == localizacao.id,
                      onSelected: (_) => notifier.definirLocalizacaoDestino(
                        widget.linha,
                        localizacaoId: localizacao.id,
                        localizacaoNome: localizacao.nome,
                      ),
                    ),
                  ActionChip(
                    label: const Text('Não informar localização'),
                    onPressed: () => notifier.confirmarSemLocalizacao(widget.linha),
                  ),
                ],
              ),
              loading: () =>
                  const SizedBox(height: 24, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (_, _) => Text(
                'Não foi possível carregar as localizações do setor de destino.',
                style: AppTypography.auxiliary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Responsável de destino — ${_rotuloDecisao(decisaoResponsavel)}', style: AppTypography.body(context)),
            if (widget.responsavelAtual != null && widget.responsavelAtual!.trim().isNotEmpty)
              Text(
                'Responsável atual: ${widget.responsavelAtual} — deixar sem informação vai apagá-lo.',
                style: AppTypography.auxiliary(context)?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _responsavelController,
              decoration: const InputDecoration(hintText: 'Nome do responsável'),
            ),
            const SizedBox(height: AppSpacing.sm),
            // PROMPT 11.3.5.5: Wrap (não Row) para os botões — o texto de
            // "Confirmar sem responsável" não cabe ao lado do campo em
            // 520px de largura, especialmente com escala de texto
            // aumentada; mesmo padrão já usado acima para os chips de
            // localização, em vez de truncar/ocultar qualquer opção.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => notifier.definirResponsavelDestino(widget.linha, _responsavelController.text),
                  child: const Text('Definir'),
                ),
                TextButton(
                  onPressed: () {
                    _responsavelController.clear();
                    notifier.confirmarSemResponsavel(widget.linha);
                  },
                  child: const Text('Confirmar sem responsável'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.children});

  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: AppTypography.label(context)?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: AppSpacing.xs),
        ...children,
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo(this.rotulo, this.valor, {this.tooltip});

  final String rotulo;
  final String? valor;

  /// PROMPT 11.3.5.4 — nome completo de um setor exibido pela sigla.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (valor == null || valor!.trim().isEmpty) return const SizedBox.shrink();
    final valorText = Text(valor!, style: AppTypography.body(context));
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(rotulo, style: AppTypography.auxiliary(context))),
          Expanded(
            child: tooltip == null ? valorText : Tooltip(message: tooltip, child: valorText),
          ),
        ],
      ),
    );
  }
}

class _ItemLista extends StatelessWidget {
  const _ItemLista({required this.icon, required this.texto, required this.cor});

  final IconData icon;
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(texto, style: AppTypography.body(context))),
        ],
      ),
    );
  }
}
