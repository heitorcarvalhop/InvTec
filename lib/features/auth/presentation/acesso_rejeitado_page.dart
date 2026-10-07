import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/auth_repository_supabase.dart';
import 'auth_controller.dart';
import 'widgets/acesso_status_scaffold.dart';
import 'widgets/cpf_mask.dart';

/// Tela "fora do shell" mostrada enquanto a conta está em `REJECTED` — ver
/// `_redirectFor` em `app_router.dart`. Permite reenviar a solicitação para
/// nova análise (self-service, sem envolver um ADMIN) — ver
/// [AuthRepository.reenviarSolicitacao].
class AcessoRejeitadoPage extends ConsumerStatefulWidget {
  const AcessoRejeitadoPage({super.key});

  @override
  ConsumerState<AcessoRejeitadoPage> createState() => _AcessoRejeitadoPageState();
}

class _AcessoRejeitadoPageState extends ConsumerState<AcessoRejeitadoPage> {
  bool _reenviando = false;

  Future<void> _reenviarSolicitacao() async {
    if (_reenviando) return;
    setState(() => _reenviando = true);
    try {
      await ref.read(authRepositoryProvider).reenviarSolicitacao();
      // Sucesso: não navega manualmente — authControllerProvider/router
      // movem o usuário para /acesso/pendente automaticamente quando o
      // Realtime (ou o próximo atualizarStatus()) detectar a mudança de
      // access_status.
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Não foi possível reenviar a solicitação agora. Tente novamente.');
    } finally {
      if (mounted) setState(() => _reenviando = false);
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
    final motivo = profile?.rejectedReason;
    final tentativas = profile?.rejectionCount ?? 0;

    return AcessoStatusScaffold(
      icon: Icons.cancel_outlined,
      statusLabel: 'Rejeitado',
      statusKind: AppStatusKind.error,
      title: 'Solicitação não aprovada',
      message: 'Você pode reenviar sua solicitação para nova análise.',
      infoRows: [
        InfoRowData('Nome', profile?.nome ?? 'Não informado'),
        InfoRowData('E-mail', profile?.email ?? 'Não informado'),
        InfoRowData('CPF', maskCpfParaExibicao(profile?.cpf)),
        InfoRowData('Tentativa', '$tentativas de 3'),
        if (motivo != null && motivo.isNotEmpty) InfoRowData('Motivo', motivo),
      ],
      actions: [
        FilledButton(
          onPressed: _reenviando ? null : _reenviarSolicitacao,
          child: _reenviando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reenviar solicitação'),
        ),
        OutlinedButton(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          child: const Text('Sair'),
        ),
      ],
    );
  }
}
