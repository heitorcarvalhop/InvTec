import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/movimentacao.dart';
import '../../domain/movimentacao_listagem_item.dart';
import 'movimentacao_tipo_visual.dart';

/// Detalhe somente leitura de uma movimentação (PROMPT 10.1) — nenhum
/// campo é editável aqui; histórico é imutável (ver docs/database.md).
Future<void> showMovimentacaoDetailDialog(BuildContext context, MovimentacaoListagemItem item) {
  return showDialog<void>(
    context: context,
    builder: (context) => MovimentacaoDetailDialog(item: item),
  );
}

class MovimentacaoDetailDialog extends StatelessWidget {
  const MovimentacaoDetailDialog({super.key, required this.item});

  final MovimentacaoListagemItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, kind) = visualDoTipoMovimentacao(item.tipo);
    final localizacao = _resumoLocalizacao(item);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Movimentação', style: AppTypography.pageSubtitle(context)),
                  ),
                  StatusChip(label: item.tipo.label, kind: kind, icon: icon),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Field(label: 'Patrimônio', value: item.patrimonioNumero),
              if (item.patrimonioTipoNome != null) _Field(label: 'Equipamento', value: item.patrimonioTipoNome),
              _Field(label: 'Origem', value: item.setorOrigemNome),
              _Field(label: 'Destino', value: item.setorDestinoNome),
              if (localizacao != null) _Field(label: 'Localização', value: localizacao),
              _Field(label: 'Responsável', value: item.responsavelExibido),
              _Field(label: 'Autor', value: item.autorExibido),
              _Field(label: 'Data/hora', value: _formatarDataHora(item.dataMovimentacao)),
              if (item.motivo != null && item.motivo!.isNotEmpty) _Field(label: 'Motivo', value: item.motivo),
              if (item.observacao != null && item.observacao!.isNotEmpty)
                _Field(label: 'Observação', value: item.observacao),
              if (item.numeroDocumento != null && item.numeroDocumento!.isNotEmpty)
                _Field(label: 'Documento', value: item.numeroDocumento),
              if (item.numeroChamado != null && item.numeroChamado!.isNotEmpty)
                _Field(label: 'Chamado', value: item.numeroChamado),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "origem → destino" quando os dois lados existem; só um dos nomes quando
/// só um existe; `null` (linha ocultada) quando nenhum dos dois existe.
String? _resumoLocalizacao(MovimentacaoListagemItem item) {
  final origem = item.localizacaoOrigemNome;
  final destino = item.localizacaoDestinoNome;
  if (origem != null && destino != null && origem != destino) return '$origem → $destino';
  return destino ?? origem;
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.auxiliary(context)),
          const SizedBox(height: 2),
          Text(value ?? '—', style: AppTypography.body(context)),
        ],
      ),
    );
  }
}

String _formatarDataHora(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} às ${pad(local.hour)}:${pad(local.minute)}';
}
