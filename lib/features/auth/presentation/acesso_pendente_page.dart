import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/status_chip.dart';
import 'auth_controller.dart';
import 'widgets/acesso_status_scaffold.dart';
import 'widgets/cpf_mask.dart';

/// Tela "fora do shell" mostrada enquanto a conta está em `PENDING` —
/// ver `_redirectFor` em `app_router.dart`. Sem sidebar/AppBar de negócio:
/// o usuário autenticado ainda não pode operar o sistema.
class AcessoPendentePage extends ConsumerStatefulWidget {
  const AcessoPendentePage({super.key});

  @override
  ConsumerState<AcessoPendentePage> createState() => _AcessoPendentePageState();
}

class _AcessoPendentePageState extends ConsumerState<AcessoPendentePage> {
  bool _atualizando = false;

  Future<void> _atualizarStatus() async {
    if (_atualizando) return;
    setState(() => _atualizando = true);
    try {
      await ref.read(authControllerProvider.notifier).atualizarStatus();
    } catch (_) {
      _showMessage('Não foi possível atualizar o status agora. Tente novamente.');
    } finally {
      if (mounted) setState(() => _atualizando = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).value?.profile;

    return AcessoStatusScaffold(
      icon: Icons.hourglass_top_outlined,
      statusLabel: 'Pendente',
      statusKind: AppStatusKind.warning,
      title: 'Solicitação enviada',
      message:
          'Seu cadastro está aguardando aprovação de um administrador. '
          'Você receberá acesso após a análise.',
      infoRows: [
        InfoRowData('Nome', profile?.nome ?? 'Não informado'),
        InfoRowData('E-mail', profile?.email ?? 'Não informado'),
        InfoRowData('CPF', maskCpfParaExibicao(profile?.cpf)),
      ],
      actions: [
        FilledButton(
          onPressed: _atualizando ? null : _atualizarStatus,
          child: _atualizando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Atualizar status'),
        ),
        OutlinedButton(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          child: const Text('Sair'),
        ),
      ],
    );
  }
}
