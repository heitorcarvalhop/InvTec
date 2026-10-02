import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/patrimonio_detalhe.dart';
import 'patrimonio_status_chip.dart';

/// Lista em uma única coluna — usada sempre em mobile
/// ([ScreenSize.mobile]), independente do `ListViewMode` escolhido (uma
/// tabela/lista de desktop nunca tenta caber numa tela estreita). Reusa o
/// mesmo [PatrimonioCard] que a visualização "Cards" do desktop usa, para as
/// duas nunca divergirem.
class PatrimonioMobileList extends StatelessWidget {
  const PatrimonioMobileList({
    super.key,
    required this.itens,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
  });

  final List<PatrimonioDetalhe> itens;
  final bool canManage;
  final ValueChanged<PatrimonioDetalhe> onTap;
  final ValueChanged<PatrimonioDetalhe> onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: PatrimonioCard(
              detalhe: item,
              canManage: canManage,
              onTap: () => onTap(item),
              onEdit: () => onEdit(item),
            ),
          ),
      ],
    );
  }
}

/// Card de um patrimônio: NÚMERO em destaque / Equipamento (tipo + marca
/// modelo) / Setor + Localização + Responsável (chips) / [Status] [ações].
/// Usado tanto pela listagem mobile ([PatrimonioMobileList]) quanto pela
/// visualização "Cards" do desktop ([PatrimonioCardsGrid]) — nunca duas
/// versões divergentes do mesmo card. "Editar" só aparece com [canManage],
/// mesma regra de permissão de [PatrimonioDesktopTable].
class PatrimonioCard extends StatelessWidget {
  const PatrimonioCard({
    super.key,
    required this.detalhe,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
  });

  final PatrimonioDetalhe detalhe;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final patrimonio = detalhe.patrimonio;
    final equipamento = [
      patrimonio.marca,
      patrimonio.modelo,
    ].where((v) => v != null && v.isNotEmpty).join(' ');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patrimonio.numeroPatrimonio ?? 'Sem número',
                          style: AppTypography.cardTitle(context),
                        ),
                        if (equipamento.isNotEmpty)
                          Text(equipamento, style: AppTypography.body(context)),
                        Text(detalhe.tipoNome, style: AppTypography.auxiliary(context)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PatrimonioStatusChip(status: patrimonio.status),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  _InfoChip(
                    icon: Icons.apartment_outlined,
                    texto: detalhe.setorExibidoCompacto,
                  ),
                  _InfoChip(
                    icon: Icons.place_outlined,
                    texto: detalhe.localizacaoNome ?? 'Sem localização',
                  ),
                  if (patrimonio.numeroSerie != null && patrimonio.numeroSerie!.isNotEmpty)
                    _InfoChip(icon: Icons.qr_code_2_outlined, texto: 'Série: ${patrimonio.numeroSerie}'),
                  if (patrimonio.responsavelAtual != null)
                    _InfoChip(
                      icon: Icons.person_outline,
                      texto: patrimonio.responsavelAtual!,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canManage)
                    Tooltip(
                      message: 'Editar',
                      child: IconButton(
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        iconSize: 18,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit,
                      ),
                    ),
                  TextButton(
                    onPressed: onTap,
                    child: const Text('Ver detalhes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        // `Flexible` (nunca só `Text` solto) — nos cards estreitos da grade
        // de desktop (`PatrimonioCardsGrid`, 3-4 colunas) um texto longo
        // (ex.: responsável, localização) precisa poder encolher com
        // reticências em vez de estourar a linha do `Wrap`.
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(context),
          ),
        ),
      ],
    );
  }
}
