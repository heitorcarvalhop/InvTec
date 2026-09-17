import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../setores/domain/setor.dart';
import '../../../presentation/patrimonio_reference_data.dart';
import '../../domain/import_defaults.dart';
import '../../domain/profiles/getec_import_profile.dart';
import '../../domain/profiles/import_profile_id.dart';
import '../patrimonio_import_controller.dart';
import '../patrimonio_import_state.dart';

/// Passo "Configurar padrões" (seção 10/11): valores usados quando a coluna
/// correspondente não existe na planilha ou a célula está vazia — o valor
/// da própria linha sempre tem prioridade sobre o padrão.
class ImportDefaultsStep extends ConsumerStatefulWidget {
  const ImportDefaultsStep({super.key, required this.state});

  final PatrimonioImportState state;

  @override
  ConsumerState<ImportDefaultsStep> createState() => _ImportDefaultsStepState();
}

class _ImportDefaultsStepState extends ConsumerState<ImportDefaultsStep> {
  late final _responsavelController = TextEditingController(
    text: widget.state.padroes.responsavelDestinoPadrao ?? '',
  );
  late final _motivoController = TextEditingController(text: widget.state.padroes.motivoPadrao ?? '');

  @override
  void dispose() {
    _responsavelController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  void _atualizar(PatrimonioImportController controller, ImportDefaults Function(ImportDefaults) update) {
    controller.definirPadroes(update(widget.state.padroes));
  }

  Future<void> _selecionarDataPadrao(PatrimonioImportController controller) async {
    final agora = DateTime.now();
    final atual = widget.state.padroes.dataPadrao ?? agora;
    final data = await showDatePicker(
      context: context,
      initialDate: atual.isAfter(agora) ? agora : atual,
      firstDate: DateTime(2000),
      lastDate: agora,
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(atual));
    if (hora == null) return;

    final combinada = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    _atualizar(
      controller,
      (p) => p.copyWith(dataPadrao: () => combinada.isAfter(agora) ? agora : combinada),
    );
  }

  void _removerDataPadrao(PatrimonioImportController controller) {
    _atualizar(controller, (p) => p.copyWith(dataPadrao: () => null));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(patrimonioImportControllerProvider.notifier);
    final setoresAsync = ref.watch(setoresAtivosParaPatrimonioProvider);
    final padroes = widget.state.padroes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Esses valores só são usados quando a linha da planilha não traz a '
          'informação correspondente (ou a coluna nem foi mapeada).',
        ),
        if (widget.state.perfilAtivo == ImportProfileId.getecLegado) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Defina a data de referência desta carga inicial. Ela será registrada '
            'como a data da movimentação de entrada quando a planilha não possuir '
            'uma data específica.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: setoresAsync.when(
              data: (setores) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PROMPT 8.13.1: para o perfil GETEC, o destino NUNCA é
                  // escolhido pelo usuário aqui — a planilha nem tem coluna
                  // de setor, e todos os bens desta carga pertencem à
                  // gerência GETEC por definição. Mostrar o dropdown
                  // genérico "Destino padrão: Nenhum" seria enganoso (dá a
                  // entender que falta configurar algo que na verdade é
                  // automático). O id real é resolvido em
                  // `avancarAposPadroes` (nunca hardcoded).
                  if (widget.state.perfilAtivo == ImportProfileId.getecLegado)
                    _GerenciaGetecInfo(setores: setores)
                  else
                    DropdownButtonFormField<String?>(
                      initialValue: padroes.destinoPadraoId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Destino padrão',
                        helperText: 'Usado quando a linha não informa o setor',
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Nenhum')),
                        for (final setor in setores)
                          DropdownMenuItem(value: setor.id, child: Text(setor.nome)),
                      ],
                      onChanged: (valor) =>
                          _atualizar(controller, (p) => p.copyWith(destinoPadraoId: () => valor)),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String?>(
                    initialValue: padroes.origemPadraoId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Origem padrão',
                      helperText: 'Opcional — de onde os equipamentos vieram',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Não informar')),
                      for (final setor in setores)
                        DropdownMenuItem(value: setor.id, child: Text(setor.nome)),
                    ],
                    onChanged: (valor) =>
                        _atualizar(controller, (p) => p.copyWith(origemPadraoId: () => valor)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _responsavelController,
                    decoration: const InputDecoration(labelText: 'Responsável destino padrão'),
                    onChanged: (valor) => _atualizar(
                      controller,
                      (p) => p.copyWith(responsavelDestinoPadrao: () => valor),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _motivoController,
                    decoration: const InputDecoration(labelText: 'Motivo padrão'),
                    onChanged: (valor) =>
                        _atualizar(controller, (p) => p.copyWith(motivoPadrao: () => valor)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  InkWell(
                    onTap: () => _selecionarDataPadrao(controller),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Data/hora padrão da entrada',
                        suffixIcon: padroes.dataPadrao == null
                            ? const Icon(Icons.event_outlined)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Remover data padrão',
                                onPressed: () => _removerDataPadrao(controller),
                              ),
                      ),
                      child: Text(
                        padroes.dataPadrao == null
                            ? 'Nenhuma definida'
                            : _formatarDataHora(padroes.dataPadrao!),
                      ),
                    ),
                  ),
                  if (padroes.dataPadrao == null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Sem data padrão: linhas com data de entrada não reconhecida serão '
                      'classificadas como erro e não poderão ser importadas.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Text('Não foi possível carregar os setores.'),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: controller.voltar, child: const Text('Voltar')),
            FilledButton(
              onPressed: controller.avancarAposPadroes,
              child: Text(
                widget.state.perfilAtivo == ImportProfileId.getecLegado ? 'Continuar' : 'Analisar planilha',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} ${pad(local.hour)}:${pad(local.minute)}';
}

/// Painel informativo (PROMPT 8.13.1) que substitui o dropdown genérico
/// "Destino padrão" quando o perfil GETEC está ativo: o destino não é uma
/// escolha do usuário aqui — é sempre a gerência GETEC, encontrada pelo
/// nome/sigla real entre os setores ativos carregados (nunca um UUID
/// hardcoded). Deixa claro, sem ambiguidade, que "Nenhum" não se aplica a
/// este perfil.
class _GerenciaGetecInfo extends StatelessWidget {
  const _GerenciaGetecInfo({required this.setores});

  final List<Setor> setores;

  @override
  Widget build(BuildContext context) {
    final gerencia = GetecImportProfile.encontrarGerenciaGetec(setores);
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Gerência de destino'),
      child: gerencia != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(gerencia.nome),
                Text(
                  'Definida automaticamente pelo perfil GETEC',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : Text(
              "Gerência '${GetecImportProfile.siglaGerencia}' não encontrada (ou ambígua/inativa) "
              'entre os setores ativos do Supabase — não será possível continuar.',
              style: TextStyle(color: colorScheme.error),
            ),
    );
  }
}
