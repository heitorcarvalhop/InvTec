import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/domain/profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../movimentacoes/presentation/movimentacao_historico_providers.dart';
import '../domain/patrimonio_detalhe.dart';
import 'patrimonio_detalhe_providers.dart';
import 'widgets/patrimonio_edit_dialog.dart';
import 'widgets/patrimonio_historico_timeline.dart';
import 'widgets/patrimonio_status_chip.dart';

class PatrimonioDetailPage extends ConsumerWidget {
  const PatrimonioDetailPage({super.key, required this.id});

  final String id;

  Future<void> _editar(
    BuildContext context,
    WidgetRef ref,
    PatrimonioDetalhe detalhe,
  ) async {
    final sucesso = await showPatrimonioEditDialog(context, detalhe: detalhe);
    if (sucesso == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Patrimônio atualizado com sucesso.')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalheAsync = ref.watch(patrimonioDetalheProvider(id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: detalheAsync.when(
          data: (detalhe) {
            if (detalhe == null) {
              return const Card(
                child: EmptyState(
                  icon: Icons.search_off,
                  message: 'Patrimônio não encontrado.',
                ),
              );
            }
            return _Detalhe(
              detalhe: detalhe,
              onEditar: () => _editar(context, ref, detalhe),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Center(
            child: EmptyState(
              icon: Icons.error_outline,
              message: 'Não foi possível carregar o patrimônio. Tente novamente.',
              actionLabel: 'Tentar novamente',
              onAction: () => ref.invalidate(patrimonioDetalheProvider(id)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Detalhe extends ConsumerWidget {
  const _Detalhe({required this.detalhe, required this.onEditar});

  final PatrimonioDetalhe detalhe;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patrimonio = detalhe.patrimonio;
    final perfil = ref.watch(authControllerProvider).value?.profile?.perfil;
    final canManage =
        perfil == ProfilePerfil.admin ||
        perfil == ProfilePerfil.gestor ||
        perfil == ProfilePerfil.operador;

    return Column(
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
                    patrimonio.numeroPatrimonio == null
                        ? 'Sem número patrimonial'
                        : 'Patrimônio ${patrimonio.numeroPatrimonio}',
                    style: AppTypography.pageTitle(context),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(detalhe.tipoNome, style: AppTypography.pageSubtitle(context)),
                  const SizedBox(height: AppSpacing.sm),
                  PatrimonioStatusChip(status: patrimonio.status),
                ],
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: onEditar,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            _Section(
              title: 'Identificação',
              icon: Icons.badge_outlined,
              fields: [
                _DetailField(label: 'Número patrimonial', value: patrimonio.numeroPatrimonio ?? '—'),
                _DetailField(label: 'Marca', value: patrimonio.marca ?? '—'),
                _DetailField(label: 'Modelo', value: patrimonio.modelo ?? '—'),
                _DetailField(label: 'Número de série', value: patrimonio.numeroSerie ?? '—'),
              ],
            ),
            _Section(
              title: 'Localização',
              icon: Icons.place_outlined,
              fields: [
                _DetailField(label: 'Gerência', value: detalhe.setorNome),
                _DetailField(label: 'Localização atual', value: detalhe.localizacaoNome ?? 'Sem localização'),
              ],
            ),
            _Section(
              title: 'Responsabilidade',
              icon: Icons.person_outline,
              fields: [
                _DetailField(label: 'Responsável atual', value: patrimonio.responsavelAtual ?? '—'),
                if (detalhe.criadoPorNome != null)
                  _DetailField(label: 'Criado por', value: detalhe.criadoPorNome!),
              ],
            ),
            _Section(
              title: 'Informações patrimoniais',
              icon: Icons.event_outlined,
              fields: [
                _DetailField(
                  label: 'Data de aquisição',
                  value: patrimonio.dataAquisicao == null ? '—' : _formatarData(patrimonio.dataAquisicao!),
                ),
                _DetailField(label: 'Data de cadastro', value: _formatarData(patrimonio.dataCadastro)),
              ],
            ),
            _Section(
              title: 'Observações',
              icon: Icons.notes_outlined,
              fields: [
                _DetailField(label: 'Descrição', value: patrimonio.descricao ?? '—', wide: true),
                _DetailField(label: 'Observação', value: patrimonio.observacao ?? '—', wide: true),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Histórico de movimentações', style: AppTypography.cardTitle(context)),
        const SizedBox(height: AppSpacing.sm),
        _HistoricoCard(patrimonioId: patrimonio.id),
      ],
    );
  }
}

class _HistoricoCard extends ConsumerWidget {
  const _HistoricoCard({required this.patrimonioId});

  final String patrimonioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historicoAsync = ref.watch(patrimonioHistoricoProvider(patrimonioId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: historicoAsync.when(
          data: (itens) {
            if (itens.isEmpty) {
              return const EmptyState(
                icon: Icons.history_outlined,
                message: 'Nenhuma movimentação registrada para este patrimônio.',
              );
            }
            return PatrimonioHistoricoTimeline(itens: itens);
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => EmptyState(
            icon: Icons.error_outline,
            message: 'Não foi possível carregar o histórico. Tente novamente.',
            actionLabel: 'Tentar novamente',
            onAction: () => ref.invalidate(patrimonioHistoricoProvider(patrimonioId)),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.fields});

  final String title;
  final IconData icon;
  final List<_DetailField> fields;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.xs),
                  Text(title, style: AppTypography.cardTitle(context)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.md, children: fields),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value, this.wide = false});

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? double.infinity : 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.auxiliary(context)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body(context)),
        ],
      ),
    );
  }
}

String _formatarData(DateTime data) {
  final local = data.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year}';
}
