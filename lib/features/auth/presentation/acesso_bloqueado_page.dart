import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/status_chip.dart';
import 'auth_controller.dart';
import 'widgets/acesso_status_scaffold.dart';
import 'widgets/cpf_mask.dart';

/// Tela "fora do shell" mostrada enquanto a conta está em `BLOCKED` — ver
/// `_redirectFor` em `app_router.dart`. Diferente da tela REJECTED, não há
/// self-service: só um ADMIN pode desbloquear a conta.
class AcessoBloqueadoPage extends ConsumerStatefulWidget {
  const AcessoBloqueadoPage({super.key});

  @override
  ConsumerState<AcessoBloqueadoPage> createState() => _AcessoBloqueadoPageState();
}

class _AcessoBloqueadoPageState extends ConsumerState<AcessoBloqueadoPage> {
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
    final motivo = profile?.blockedReason;
    final porRejeicoesConsecutivas = (profile?.rejectionCount ?? 0) >= 3;

    final explicacao = porRejeicoesConsecutivas
        ? 'Seu acesso foi bloqueado após rejeições consecutivas. '
            'Entre em contato com um administrador do InvTec.'
        : 'Entre em contato com um administrador do InvTec.';

    return AcessoStatusScaffold(
      icon: Icons.lock_outline,
      statusLabel: 'Bloqueado',
      statusKind: AppStatusKind.error,
      title: 'Acesso bloqueado',
      message: explicacao,
      infoRows: [
        InfoRowData('Nome', profile?.nome ?? 'Não informado'),
        InfoRowData('E-mail', profile?.email ?? 'Não informado'),
        InfoRowData('CPF', maskCpfParaExibicao(profile?.cpf)),
        if (motivo != null && motivo.isNotEmpty) InfoRowData('Motivo', motivo),
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
