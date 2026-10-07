import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../auth/domain/profile.dart';
import 'admin_usuario_detalhe_controller.dart';
import 'widgets/admin_usuario_formatters.dart';
import 'widgets/admin_usuario_status_chip.dart';
import 'widgets/alterar_perfil_dialog.dart';
import 'widgets/aprovar_usuario_dialog.dart';
import 'widgets/desbloquear_usuario_dialog.dart';
import 'widgets/editar_identidade_dialog.dart';
import 'widgets/motivo_action_dialog.dart';
import 'widgets/permissoes_panel.dart';
import 'widgets/resetar_permissoes_dialog.dart';

/// Tela "Administração > Usuários > Detalhe" (seções 28-43 do pedido) —
/// identidade, acesso, ações condicionais por `access_status` e o painel de
/// permissões granulares. Toda a lógica de negócio (o que é permitido,
/// quando) já vive em [AdminUsuarioDetalheController] — esta página só
/// monta a UI e trata erro com a mesma convenção do resto do app
/// (`AppException.message` amigável, genérico para qualquer outro erro).
class AdminUsuarioDetalhePage extends ConsumerStatefulWidget {
  const AdminUsuarioDetalhePage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AdminUsuarioDetalhePage> createState() => _AdminUsuarioDetalhePageState();
}

class _AdminUsuarioDetalhePageState extends ConsumerState<AdminUsuarioDetalhePage> {
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _voltar() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/administracao/usuarios');
    }
  }

  Future<void> _aprovar() async {
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => AprovarUsuarioDialog(userId: widget.id),
    );
    if (sucesso == true) _showMessage('Acesso aprovado.');
  }

  Future<void> _rejeitar(Profile usuario) async {
    final tentativa = usuario.rejectionCount + 1;
    final vaiBloquear = tentativa >= 3;
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => MotivoActionDialog(
        title: 'Rejeitar solicitação',
        confirmLabel: 'Rejeitar solicitação',
        aviso: _AvisoRejeicao(tentativa: tentativa, vaiBloquear: vaiBloquear),
        onConfirmar: (ref, motivo) =>
            ref.read(adminUsuarioDetalheControllerProvider(widget.id).notifier).rejeitar(motivo),
      ),
    );
    if (sucesso == true) {
      _showMessage(vaiBloquear ? 'Solicitação rejeitada. Conta bloqueada.' : 'Solicitação rejeitada.');
    }
  }

  Future<void> _bloquear() async {
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => MotivoActionDialog(
        title: 'Bloquear acesso',
        confirmLabel: 'Bloquear acesso',
        onConfirmar: (ref, motivo) =>
            ref.read(adminUsuarioDetalheControllerProvider(widget.id).notifier).bloquear(motivo),
      ),
    );
    if (sucesso == true) _showMessage('Usuário bloqueado.');
  }

  Future<void> _desbloquear(Profile usuario) async {
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => DesbloquearUsuarioDialog(userId: widget.id, jaFoiAprovado: usuario.approvedAt != null),
    );
    if (sucesso == true) _showMessage('Usuário desbloqueado.');
  }

  Future<void> _alterarPerfil(Profile usuario) async {
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => AlterarPerfilDialog(userId: widget.id, perfilAtual: usuario.perfil),
    );
    if (sucesso == true) _showMessage('Perfil atualizado.');
  }

  Future<void> _editarIdentidade(Profile usuario) async {
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => EditarIdentidadeDialog(usuario: usuario),
    );
    if (sucesso == true) _showMessage('Identidade atualizada.');
  }

  Future<void> _restaurarPermissoes(Profile usuario) async {
    final sucesso = await showDialog<bool>(
      context: context,
      builder: (_) => ResetarPermissoesDialog(userId: widget.id, perfil: usuario.perfil),
    );
    if (sucesso == true) _showMessage('Permissões restauradas ao padrão do perfil.');
  }

  Future<void> _definirPermissao(String key, bool granted) async {
    try {
      await ref.read(adminUsuarioDetalheControllerProvider(widget.id).notifier).definirPermissao(key, granted);
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Erro inesperado. Tente novamente.');
    }
  }

  Future<void> _removerOverride(String key) async {
    try {
      await ref.read(adminUsuarioDetalheControllerProvider(widget.id).notifier).removerOverridePermissao(key);
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Erro inesperado. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final estadoAsync = ref.watch(adminUsuarioDetalheControllerProvider(widget.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvTecPageHeader(
              title: estadoAsync.value?.usuario.nome ?? 'Usuário',
              subtitle: 'Gerencie acesso e permissões deste usuário.',
              onBack: _voltar,
            ),
            const SizedBox(height: AppSpacing.md),
            estadoAsync.when(
              data: (estado) => _Corpo(
                estado: estado,
                onAprovar: _aprovar,
                onRejeitar: () => _rejeitar(estado.usuario),
                onBloquear: _bloquear,
                onDesbloquear: () => _desbloquear(estado.usuario),
                onAlterarPerfil: () => _alterarPerfil(estado.usuario),
                onEditarIdentidade: () => _editarIdentidade(estado.usuario),
                onRestaurarPermissoes: () => _restaurarPermissoes(estado.usuario),
                onDefinirPermissao: _definirPermissao,
                onRemoverOverride: _removerOverride,
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: error is AppException
                      ? error.message
                      : 'Não foi possível carregar este usuário. Tente novamente.',
                  actionLabel: 'Tentar de novo',
                  onAction: () => ref.invalidate(adminUsuarioDetalheControllerProvider(widget.id)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvisoRejeicao extends StatelessWidget {
  const _AvisoRejeicao({required this.tentativa, required this.vaiBloquear});

  final int tentativa;
  final bool vaiBloquear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rejeição $tentativa de 3', style: AppTypography.label(context)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          vaiBloquear
              ? 'Esta rejeição bloqueará a conta até intervenção de um administrador.'
              : 'Este usuário ainda poderá reenviar a solicitação.',
          style: TextStyle(color: vaiBloquear ? colorScheme.error : colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo({
    required this.estado,
    required this.onAprovar,
    required this.onRejeitar,
    required this.onBloquear,
    required this.onDesbloquear,
    required this.onAlterarPerfil,
    required this.onEditarIdentidade,
    required this.onRestaurarPermissoes,
    required this.onDefinirPermissao,
    required this.onRemoverOverride,
  });

  final AdminUsuarioDetalheState estado;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;
  final VoidCallback onBloquear;
  final VoidCallback onDesbloquear;
  final VoidCallback onAlterarPerfil;
  final VoidCallback onEditarIdentidade;
  final VoidCallback onRestaurarPermissoes;
  final void Function(String permissionKey, bool granted) onDefinirPermissao;
  final void Function(String permissionKey) onRemoverOverride;

  @override
  Widget build(BuildContext context) {
    final usuario = estado.usuario;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecaoCard(titulo: 'Identidade', child: _Identidade(usuario: usuario)),
        const SizedBox(height: AppSpacing.md),
        _SecaoCard(titulo: 'Acesso', child: _Acesso(usuario: usuario)),
        const SizedBox(height: AppSpacing.md),
        _SecaoCard(
          titulo: 'Ações',
          child: _Acoes(
            usuario: usuario,
            processando: estado.processando,
            onAprovar: onAprovar,
            onRejeitar: onRejeitar,
            onBloquear: onBloquear,
            onDesbloquear: onDesbloquear,
            onAlterarPerfil: onAlterarPerfil,
            onEditarIdentidade: onEditarIdentidade,
          ),
        ),
        // Painel de permissões só faz sentido para quem tem acesso efetivo
        // ao sistema de negócio — decisão de UI documentada no relatório
        // final: pending/rejected/blocked não têm permissões úteis a
        // mostrar/editar nesta etapa, então a seção inteira é omitida (não
        // só desabilitada) para esses três status.
        if (usuario.accessStatus == ProfileAccessStatus.active) ...[
          const SizedBox(height: AppSpacing.md),
          _SecaoCard(
            titulo: 'Permissões',
            trailing: TextButton(
              onPressed: estado.ehProprioUsuarioLogado || estado.processando ? null : onRestaurarPermissoes,
              child: const Text('Restaurar padrão do perfil'),
            ),
            child: PermissoesPanel(
              permissoes: estado.permissoes,
              perfilUsuario: usuario.perfil,
              somenteLeitura: estado.ehProprioUsuarioLogado,
              processando: estado.processando,
              onDefinir: onDefinirPermissao,
              onRemoverOverride: onRemoverOverride,
            ),
          ),
        ],
      ],
    );
  }
}

class _SecaoCard extends StatelessWidget {
  const _SecaoCard({required this.titulo, required this.child, this.trailing});

  final String titulo;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: AppSpacing.sm,
                children: [
                  Text(titulo, style: AppTypography.cardTitle(context)),
                  ?trailing,
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _CampoLeitura extends StatelessWidget {
  const _CampoLeitura({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label(context)),
        const SizedBox(height: 2),
        Text(valor, style: AppTypography.body(context)),
      ],
    );
  }
}

class _CampoWidget extends StatelessWidget {
  const _CampoWidget({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label(context)),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

/// Seção IDENTIDADE (seção 28) — nome/CPF completo (visão ADMIN, nunca
/// mascarado aqui)/e-mail somente leitura, sem nenhum controle clicável
/// perto do e-mail que sugira edição direta.
class _Identidade extends StatelessWidget {
  const _Identidade({required this.usuario});

  final Profile usuario;

  @override
  Widget build(BuildContext context) {
    final cpf = usuario.cpf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CampoLeitura(label: 'Nome', valor: usuario.nome),
        const SizedBox(height: AppSpacing.smd),
        _CampoLeitura(label: 'CPF', valor: cpf == null ? 'Não informado' : formatarCpfCompleto(cpf)),
        const SizedBox(height: AppSpacing.smd),
        _CampoLeitura(label: 'E-mail', valor: usuario.email ?? 'Não informado'),
        const SizedBox(height: AppSpacing.xs),
        Text('Alterações de e-mail serão realizadas por solicitação.', style: AppTypography.caption(context)),
      ],
    );
  }
}

/// Seção ACESSO (seção 28) — `Aprovado por` só mostra "Sim"/omitido: o
/// campo guarda um `id` de outro profile e resolver o nome exigiria uma
/// chamada de rede nova só para um dado secundário, que o pedido pede para
/// NÃO inventar.
class _Acesso extends StatelessWidget {
  const _Acesso({required this.usuario});

  final Profile usuario;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        _CampoWidget(label: 'Status', child: AdminUsuarioStatusChip(status: usuario.accessStatus)),
        _CampoLeitura(label: 'Perfil base', valor: usuario.perfil.label),
        _CampoLeitura(label: 'Rejeições', valor: '${usuario.rejectionCount} de 3'),
        if (usuario.approvedAt != null)
          _CampoLeitura(label: 'Aprovado em', valor: formatarDataCurta(usuario.approvedAt!)),
        if (usuario.approvedBy != null) const _CampoLeitura(label: 'Aprovado por', valor: 'Sim'),
      ],
    );
  }
}

/// Seção AÇÕES (seções 29-34) — um conjunto de botões DIFERENTE por
/// `access_status`, nunca um botão que o servidor certamente recusaria
/// (ex.: nunca "Aprovar" para quem não está PENDING).
class _Acoes extends StatelessWidget {
  const _Acoes({
    required this.usuario,
    required this.processando,
    required this.onAprovar,
    required this.onRejeitar,
    required this.onBloquear,
    required this.onDesbloquear,
    required this.onAlterarPerfil,
    required this.onEditarIdentidade,
  });

  final Profile usuario;
  final bool processando;
  final VoidCallback onAprovar;
  final VoidCallback onRejeitar;
  final VoidCallback onBloquear;
  final VoidCallback onDesbloquear;
  final VoidCallback onAlterarPerfil;
  final VoidCallback onEditarIdentidade;

  @override
  Widget build(BuildContext context) {
    final botoes = switch (usuario.accessStatus) {
      ProfileAccessStatus.pending => [
        FilledButton.icon(
          onPressed: processando ? null : onAprovar,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Aprovar acesso'),
        ),
        OutlinedButton.icon(
          onPressed: processando ? null : onRejeitar,
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Rejeitar'),
        ),
      ],
      // "Editar identidade" fica fora do conjunto de ações de PENDING: a
      // identidade de uma solicitação ainda não revisada é parte do que o
      // ADMIN está decidindo aprovar/rejeitar, não algo a corrigir antes
      // disso (decisão documentada no relatório final).
      ProfileAccessStatus.active => [
        OutlinedButton.icon(
          onPressed: processando ? null : onAlterarPerfil,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Alterar perfil'),
        ),
        OutlinedButton.icon(
          onPressed: processando ? null : onEditarIdentidade,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar identidade'),
        ),
        OutlinedButton.icon(
          onPressed: processando ? null : onBloquear,
          icon: const Icon(Icons.block_outlined),
          label: const Text('Bloquear acesso'),
        ),
      ],
      ProfileAccessStatus.rejected => [
        OutlinedButton.icon(
          onPressed: processando ? null : onEditarIdentidade,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar identidade'),
        ),
        OutlinedButton.icon(
          onPressed: processando ? null : onBloquear,
          icon: const Icon(Icons.block_outlined),
          label: const Text('Bloquear manualmente'),
        ),
      ],
      ProfileAccessStatus.blocked => [
        FilledButton.icon(
          onPressed: processando ? null : onDesbloquear,
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Desbloquear'),
        ),
      ],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._avisos(context),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: botoes),
      ],
    );
  }

  List<Widget> _avisos(BuildContext context) {
    final avisos = <Widget>[];

    if (usuario.accessStatus == ProfileAccessStatus.rejected) {
      if (usuario.rejectedReason != null) {
        avisos.add(_textoAviso(context, 'Motivo da rejeição: ${usuario.rejectedReason}'));
      }
      avisos.add(_textoAviso(context, 'Somente o próprio usuário pode reenviar a solicitação de acesso.'));
    }

    if (usuario.accessStatus == ProfileAccessStatus.blocked && usuario.blockedReason != null) {
      avisos.add(_textoAviso(context, 'Motivo do bloqueio: ${usuario.blockedReason}'));
    }

    if (avisos.isEmpty) return const [];
    return [...avisos, const SizedBox(height: AppSpacing.md)];
  }

  Widget _textoAviso(BuildContext context, String texto) =>
      Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: Text(texto, style: AppTypography.body(context)));
}
