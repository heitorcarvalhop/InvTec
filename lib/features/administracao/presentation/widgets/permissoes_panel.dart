import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/domain/permissao_efetiva.dart';
import '../../../auth/domain/profile.dart';
import 'permissao_catalogo.dart';

/// Painel de permissões granulares (seções 38-43 do pedido) — a parte mais
/// importante da tela de detalhe. Só deve ser montado quando
/// `accessStatus == active` (decisão do chamador, não deste widget: um
/// usuário PENDING/REJECTED/BLOCKED não tem permissões efetivas úteis para
/// mostrar/editar).
///
/// [somenteLeitura] implementa a proteção de auto-gestão (seção 43): quando
/// `true` (o ADMIN logado vendo a própria tela), TODO tri-state fica
/// desabilitado — nunca oferece um controle que o servidor sempre recusaria.
class PermissoesPanel extends StatelessWidget {
  const PermissoesPanel({
    super.key,
    required this.permissoes,
    required this.perfilUsuario,
    required this.somenteLeitura,
    required this.processando,
    required this.onDefinir,
    required this.onRemoverOverride,
  });

  final List<PermissaoEfetiva> permissoes;
  final ProfilePerfil perfilUsuario;
  final bool somenteLeitura;
  final bool processando;
  final void Function(String permissionKey, bool granted) onDefinir;
  final void Function(String permissionKey) onRemoverOverride;

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<PermissaoEfetiva>>{};
    for (final permissao in permissoes) {
      final modulo = infoPermissao(permissao.permissionKey).modulo;
      (grupos[modulo] ??= []).add(permissao);
    }
    final modulosOrdenados = [
      ...ordemModulosPermissao.where(grupos.containsKey),
      ...grupos.keys.where((modulo) => !ordemModulosPermissao.contains(modulo)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (somenteLeitura) ...[
          const _AvisoAutoGestao(),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final modulo in modulosOrdenados) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(modulo, style: AppTypography.cardTitle(context)),
          ),
          for (final permissao in grupos[modulo]!)
            _PermissaoRow(
              permissao: permissao,
              label: infoPermissao(permissao.permissionKey).label,
              // Caso crítico `patrimonio.compare_update` (seção 41): sempre
              // negado pelo servidor para quem não é ADMIN — nunca oferecer
              // "Permitir" como se funcionasse para esse caso.
              bloqueadaExclusivaAdmin:
                  permissao.permissionKey == 'patrimonio.compare_update' &&
                  perfilUsuario != ProfilePerfil.admin,
              desabilitada: somenteLeitura || processando,
              onChanged: (valor) {
                if (valor == null) {
                  onRemoverOverride(permissao.permissionKey);
                } else {
                  onDefinir(permissao.permissionKey, valor);
                }
              },
            ),
        ],
      ],
    );
  }
}

class _AvisoAutoGestao extends StatelessWidget {
  const _AvisoAutoGestao();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).statusColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smd),
      decoration: BoxDecoration(
        color: colors.infoBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.infoForeground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Suas próprias permissões não podem ser alteradas nesta tela.',
              style: TextStyle(color: colors.infoForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissaoRow extends StatelessWidget {
  const _PermissaoRow({
    required this.permissao,
    required this.label,
    required this.bloqueadaExclusivaAdmin,
    required this.desabilitada,
    required this.onChanged,
  });

  final PermissaoEfetiva permissao;
  final String label;
  final bool bloqueadaExclusivaAdmin;
  final bool desabilitada;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final statusColors = Theme.of(context).statusColors;
    final travada = desabilitada || bloqueadaExclusivaAdmin;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: AppTypography.body(context))),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: permissao.efetiva ? statusColors.successBackground : statusColors.errorBackground,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  permissao.efetiva ? 'Efetiva: Permitida' : 'Efetiva: Negada',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: permissao.efetiva ? statusColors.successForeground : statusColors.errorForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                'Padrão do perfil: ${permissao.defaultDoPerfil ? "Permitido" : "Negado"}',
                style: AppTypography.caption(context),
              ),
              Opacity(
                opacity: travada ? 0.5 : 1,
                child: IgnorePointer(
                  ignoring: travada,
                  child: SegmentedButton<bool?>(
                    key: ValueKey('permissao-tristate-${permissao.permissionKey}'),
                    segments: const [
                      ButtonSegment(value: null, label: Text('Herdar')),
                      ButtonSegment(value: true, label: Text('Permitir')),
                      ButtonSegment(value: false, label: Text('Negar')),
                    ],
                    selected: {permissao.override},
                    showSelectedIcon: false,
                    onSelectionChanged: (selecionados) => onChanged(selecionados.first),
                  ),
                ),
              ),
              if (bloqueadaExclusivaAdmin)
                Text(
                  'Exclusiva de administrador',
                  style: AppTypography.caption(context)?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
