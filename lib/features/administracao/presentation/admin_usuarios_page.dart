import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_header.dart';
import '../../auth/domain/profile.dart';
import 'admin_usuarios_controller.dart';
import 'widgets/admin_usuarios_desktop_table.dart';
import 'widgets/admin_usuarios_mobile_list.dart';

/// Tela "Administração > Usuários" (seções 25-27, 45 do pedido) — ADMIN-only,
/// a rota já garante isso via `redirect` do GoRouter antes desta página
/// construir. Uma aba por `access_status`, busca textual e o contador fixo
/// de pendentes visível em QUALQUER aba (não só a de Pendentes).
class AdminUsuariosPage extends ConsumerStatefulWidget {
  const AdminUsuariosPage({super.key});

  @override
  ConsumerState<AdminUsuariosPage> createState() => _AdminUsuariosPageState();
}

class _AdminUsuariosPageState extends ConsumerState<AdminUsuariosPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // atualiza o texto do estado vazio (busca x aba vazia)
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(adminUsuariosControllerProvider.notifier).buscar(value);
    });
  }

  void _verDetalhes(Profile usuario) {
    context.push('/administracao/usuarios/${usuario.id}');
  }

  @override
  Widget build(BuildContext context) {
    final estadoAsync = ref.watch(adminUsuariosControllerProvider);
    final termoBusca = _searchController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvTecPageHeader(
              title: 'Usuários',
              subtitle: 'Gerencie solicitações, acessos e permissões do InvTec.',
              compact: context.screenSize == ScreenSize.mobile,
            ),
            const SizedBox(height: AppSpacing.md),
            _AbasStatus(
              statusAtual: estadoAsync.value?.status ?? ProfileAccessStatus.pending,
              pendentesCount: estadoAsync.value?.pendentesCount ?? 0,
              onChanged: (status) =>
                  ref.read(adminUsuariosControllerProvider.notifier).trocarStatus(status),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smd),
                child: _SearchField(controller: _searchController, onChanged: _onSearchChanged),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            estadoAsync.when(
              data: (estado) {
                if (estado.usuarios.isEmpty) {
                  return _EmptyList(status: estado.status, termoBusca: termoBusca);
                }
                return context.screenSize == ScreenSize.mobile
                    ? AdminUsuariosMobileList(usuarios: estado.usuarios, onVerDetalhes: _verDetalhes)
                    : AdminUsuariosDesktopTable(usuarios: estado.usuarios, onVerDetalhes: _verDetalhes);
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => Center(
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: _mensagemErro(error),
                  actionLabel: 'Tentar de novo',
                  onAction: () => ref.read(adminUsuariosControllerProvider.notifier).recarregar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _mensagemErro(Object error) {
    if (error is AppException) return error.message;
    return 'Não foi possível carregar os usuários. Tente novamente.';
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar por nome, e-mail ou CPF',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// `[Pendentes (N)] [Ativos] [Rejeitados] [Bloqueados]` — o contador de
/// pendentes (seção 45) usa `pendentesCount`, SEMPRE visível independente
/// da aba selecionada. Envolto num scroll horizontal: 4 segmentos com texto
/// não cabem lado a lado em 390px sem encolher abaixo do tamanho legível.
class _AbasStatus extends StatelessWidget {
  const _AbasStatus({
    required this.statusAtual,
    required this.pendentesCount,
    required this.onChanged,
  });

  final ProfileAccessStatus statusAtual;
  final int pendentesCount;
  final ValueChanged<ProfileAccessStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<ProfileAccessStatus>(
        segments: [
          ButtonSegment(
            value: ProfileAccessStatus.pending,
            label: Text('Pendentes ($pendentesCount)'),
          ),
          const ButtonSegment(value: ProfileAccessStatus.active, label: Text('Ativos')),
          const ButtonSegment(value: ProfileAccessStatus.rejected, label: Text('Rejeitados')),
          const ButtonSegment(value: ProfileAccessStatus.blocked, label: Text('Bloqueados')),
        ],
        selected: {statusAtual},
        showSelectedIcon: false,
        onSelectionChanged: (selecionados) => onChanged(selecionados.first),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.status, required this.termoBusca});

  final ProfileAccessStatus status;
  final String termoBusca;

  @override
  Widget build(BuildContext context) {
    if (termoBusca.isNotEmpty) {
      return Card(
        child: EmptyState(
          icon: Icons.search_off,
          message: 'Nenhum usuário encontrado para "$termoBusca".',
        ),
      );
    }

    final mensagem = switch (status) {
      ProfileAccessStatus.pending => 'Nenhuma solicitação pendente.',
      ProfileAccessStatus.active => 'Nenhum usuário ativo.',
      ProfileAccessStatus.rejected => 'Nenhum usuário rejeitado.',
      ProfileAccessStatus.blocked => 'Nenhum usuário bloqueado.',
    };

    return Card(
      child: EmptyState(icon: Icons.people_outline, message: mensagem),
    );
  }
}
