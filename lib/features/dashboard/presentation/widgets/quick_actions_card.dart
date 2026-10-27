import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/platform_info.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
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
    // Android apenas (leitor de câmera — InvTec 4.0): mesmo gate de
    // `/patrimonios` (ver `PatrimoniosPage._escanearPatrimonio`), nunca
    // aparece no Windows desktop. `isAndroidProvider` em vez de
    // `Platform.isAndroid` direto só existe para isto ser testável em
    // widget test — ver lib/core/config/platform_info.dart.
    final podeEscanear = ref.watch(isAndroidProvider);

    final acoes = <_AcaoRapida>[
      // Primeiro da lista (prioridade de acesso rápido ao scanner, pedido
      // explícito desta melhoria) — a MESMA rota/página do scanner avulso
      // já usada em `/patrimonios`, nenhuma navegação nova.
      if (podeEscanear)
        _AcaoRapida(
          icon: Icons.qr_code_scanner_outlined,
          label: 'Escanear patrimônio',
          onPressed: () => context.push('/patrimonios/escanear'),
        ),
      if (podeCriarPatrimonio)
        _AcaoRapida(
          icon: Icons.add_circle_outline,
          label: 'Novo patrimônio',
          onPressed: () => context.push('/patrimonios/novo'),
        ),
      if (podeRegistrarMovimentacao)
        _AcaoRapida(
          icon: Icons.swap_horiz_outlined,
          label: 'Registrar movimentação',
          // `?acao=nova`: a MESMA `MovimentacoesPage` abre
          // `NovaMovimentacaoDialog` já existente automaticamente — ver
          // `MovimentacoesPage._tratarAcaoInicial`. Nenhum dialog novo.
          onPressed: () => context.go('/movimentacoes?acao=nova'),
        ),
      if (podeImportar)
        _AcaoRapida(
          icon: Icons.upload_file_outlined,
          label: 'Importar patrimônios',
          onPressed: () => context.push('/patrimonios/importar'),
        ),
      if (podeVerPatrimonio)
        _AcaoRapida(
          icon: Icons.search,
          label: 'Consultar patrimônio',
          // Abre o diálogo de busca rápida por prefixo — nunca uma segunda
          // busca/listagem de Patrimônios embutida no Dashboard (ver
          // ConsultarPatrimonioDialog).
          onPressed: () => showConsultarPatrimonioDialog(context),
        ),
      if (podeGerenciarSei)
        _AcaoRapida(
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

    final mobile = context.screenSize == ScreenSize.mobile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DashboardSectionHeader(title: 'Ações rápidas'),
        const SizedBox(height: AppSpacing.sm),
        Card(
          shape: shape,
          child: Padding(
            padding: EdgeInsets.all(mobile ? AppSpacing.sm : AppSpacing.md),
            child: acoes.isEmpty
                ? const EmptyState(
                    icon: Icons.bolt_outlined,
                    message: 'Nenhuma ação disponível para o seu perfil.',
                  )
                : (mobile
                      ? _AcoesMobileGrid(acoes: acoes)
                      : _AcoesDesktopWrap(acoes: acoes)),
          ),
        ),
      ],
    );
  }
}

/// Dados de uma ação rápida — sem widget próprio: desktop e mobile desenham
/// a mesma ação com visuais bem diferentes (texto ao lado do ícone vs.
/// ícone acima do texto), então o dado fica separado da apresentação.
class _AcaoRapida {
  const _AcaoRapida({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// Desktop/tablet — inalterado desde a implementação original: botões
/// compactos (ícone + texto lado a lado) em `Wrap`, preferencialmente numa
/// única linha.
class _AcoesDesktopWrap extends StatelessWidget {
  const _AcoesDesktopWrap({required this.acoes});

  final List<_AcaoRapida> acoes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [for (final acao in acoes) _QuickAction(acao: acao)],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.acao});

  final _AcaoRapida acao;

  @override
  Widget build(BuildContext context) {
    // Compacto de propósito (seção 3 do pedido de refinamento: "não tornar
    // os botões gigantes") — para as 5 ações caberem preferencialmente numa
    // única linha no desktop; o `Wrap` do card continua sendo quem decide
    // quebrar linha quando o espaço realmente não é suficiente.
    return OutlinedButton.icon(
      onPressed: acao.onPressed,
      icon: Icon(acao.icon, size: 18),
      label: Text(acao.label),
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

/// Mobile (Fase 2 — densidade, seção 7 do pedido): 5 botões "ícone + texto
/// lado a lado" do desktop empilhados verticalmente ocupavam a tela toda
/// ("cara de desktop espremido"). Em vez disso, uma grade de 2 colunas com
/// ícone ACIMA do rótulo (mesmo padrão de atalhos de apps mobile) — nenhuma
/// ação é escondida/movida para um menu "Mais", só o layout muda.
class _AcoesMobileGrid extends StatelessWidget {
  const _AcoesMobileGrid({required this.acoes});

  final List<_AcaoRapida> acoes;

  static const _colunas = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final espacamentoTotal = AppSpacing.sm * (_colunas - 1);
        final largura = (constraints.maxWidth - espacamentoTotal) / _colunas;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final acao in acoes)
              SizedBox(
                width: largura,
                child: _QuickActionMobile(acao: acao),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionMobile extends StatelessWidget {
  const _QuickActionMobile({required this.acao});

  final _AcaoRapida acao;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: acao.onPressed,
      style: OutlinedButton.styleFrom(
        // Altura mínima seguro para toque (44dp) mesmo com conteúdo
        // visualmente compacto — largura já vem fixada pelo `SizedBox` do
        // grid, então só a altura mínima importa aqui.
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        alignment: Alignment.center,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(acao.icon, size: 20),
          const SizedBox(height: AppSpacing.xs),
          Text(
            acao.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              context,
            )?.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
