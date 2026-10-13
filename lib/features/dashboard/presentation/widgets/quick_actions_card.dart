import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../auth/presentation/current_permissions_controller.dart';
import 'consultar_patrimonio_dialog.dart';
import 'dashboard_section_header.dart';

/// "Ações rápidas": só os atalhos que a permissão efetiva do usuário atual
/// realmente libera (seção 9 do pedido — "sem permissão: não mostrar
/// botão inútil/desabilitado", nunca baseado em perfil direto). Cada ação
/// navega para uma página que JÁ existe com esse fluxo — nenhuma rota nova
/// criada só para o Dashboard.
class QuickActionsCard extends ConsumerWidget {
  const QuickActionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final podeCriarPatrimonio = ref.hasPermission('patrimonio.create');
    final podeImportar =
        ref.hasPermission('patrimonio.create') ||
        ref.hasPermission('patrimonio.edit');
    final podeVerPatrimonio = ref.hasPermission('patrimonio.view');
    final podeRegistrarMovimentacao = ref.hasPermission('movimentacao.create');
    final podeGerenciarSei = ref.hasPermission('sei.manage');

    final acoes = <Widget>[
      if (podeCriarPatrimonio)
        _QuickAction(
          icon: Icons.add_circle_outline,
          label: 'Novo patrimônio',
          onPressed: () => context.push('/patrimonios/novo'),
        ),
      if (podeRegistrarMovimentacao)
        _QuickAction(
          icon: Icons.swap_horiz_outlined,
          label: 'Registrar movimentação',
          // `?acao=nova`: a MESMA `MovimentacoesPage` abre
          // `NovaMovimentacaoDialog` já existente automaticamente — ver
          // `MovimentacoesPage._tratarAcaoInicial`. Nenhum dialog novo.
          onPressed: () => context.go('/movimentacoes?acao=nova'),
        ),
      if (podeImportar)
        _QuickAction(
          icon: Icons.upload_file_outlined,
          label: 'Importar patrimônios',
          onPressed: () => context.push('/patrimonios/importar'),
        ),
      if (podeVerPatrimonio)
        _QuickAction(
          icon: Icons.search,
          label: 'Consultar patrimônio',
          // Abre o diálogo de busca rápida por prefixo — nunca uma segunda
          // busca/listagem de Patrimônios embutida no Dashboard (ver
          // ConsultarPatrimonioDialog).
          onPressed: () => showConsultarPatrimonioDialog(context),
        ),
      if (podeGerenciarSei)
        _QuickAction(
          icon: Icons.description_outlined,
          label: 'Documento SEI',
          // `?acao=importar-sei`: a MESMA `MovimentacoesPage` troca para a
          // aba Pendências e abre `showImportarSeiDialog` já existente —
          // nenhum formulário de importação duplicado no Dashboard.
          onPressed: () => context.go('/movimentacoes?acao=importar-sei'),
        ),
    ];

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: Theme.of(context).surfaceColors.border),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardSectionHeader(title: 'Ações rápidas'),
        const SizedBox(height: AppSpacing.sm),
        Card(
          shape: shape,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: acoes.isEmpty
                ? const EmptyState(
                    icon: Icons.bolt_outlined,
                    message: 'Nenhuma ação disponível para o seu perfil.',
                  )
                : Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: acoes,
                  ),
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Compacto de propósito (seção 3 do pedido de refinamento: "não tornar
    // os botões gigantes") — para as 5 ações caberem preferencialmente numa
    // única linha no desktop; o `Wrap` do card continua sendo quem decide
    // quebrar linha quando o espaço realmente não é suficiente.
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smd,
          vertical: AppSpacing.sm,
        ),
      ),
    );
  }
}
