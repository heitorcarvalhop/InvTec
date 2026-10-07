import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../auth/domain/profile.dart';
import 'admin_usuario_formatters.dart';
import 'admin_usuario_status_chip.dart';

class AdminUsuariosMobileList extends StatelessWidget {
  const AdminUsuariosMobileList({
    super.key,
    required this.usuarios,
    required this.onVerDetalhes,
  });

  final List<Profile> usuarios;
  final ValueChanged<Profile> onVerDetalhes;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final usuario in usuarios)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _UsuarioCard(usuario: usuario, onTap: () => onVerDetalhes(usuario)),
          ),
      ],
    );
  }
}

class _UsuarioCard extends StatelessWidget {
  const _UsuarioCard({required this.usuario, required this.onTap});

  final Profile usuario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cpfMascarado = formatarCpfMascarado(usuario.cpf);

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
                        Text(usuario.nome, style: theme.textTheme.titleMedium),
                        if (usuario.email != null)
                          Text(
                            usuario.email!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AdminUsuarioStatusChip(status: usuario.accessStatus),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  _InfoItem(label: 'CPF', valor: cpfMascarado ?? 'Não informado'),
                  _InfoItem(label: 'Perfil', valor: usuario.perfil.label),
                  _InfoItem(label: 'Rejeições', valor: '${usuario.rejectionCount}'),
                  _InfoItem(label: 'Cadastro', valor: formatarDataCurta(usuario.criadoEm)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Ver detalhes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(valor, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
