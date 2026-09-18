import 'package:flutter/material.dart';

import '../../../../core/widgets/status_chip.dart';
import '../../domain/movimentacao.dart';

/// Ícone + categoria semântica por tipo de movimentação — usado tanto na
/// lista "Movimentações recentes" do Dashboard quanto na listagem geral de
/// Movimentações (PROMPT 10.1), para as duas telas usarem exatamente a
/// mesma linguagem visual em vez de duas versões parecidas.
(IconData, AppStatusKind) visualDoTipoMovimentacao(MovimentacaoTipo tipo) {
  return switch (tipo) {
    MovimentacaoTipo.entrada => (Icons.login_outlined, AppStatusKind.success),
    MovimentacaoTipo.devolucao => (Icons.assignment_return_outlined, AppStatusKind.success),
    MovimentacaoTipo.retornoManutencao => (Icons.build_circle_outlined, AppStatusKind.success),
    MovimentacaoTipo.saida => (Icons.logout_outlined, AppStatusKind.error),
    MovimentacaoTipo.baixa => (Icons.remove_circle_outline, AppStatusKind.error),
    MovimentacaoTipo.manutencao => (Icons.build_outlined, AppStatusKind.warning),
    MovimentacaoTipo.emprestimo => (Icons.handshake_outlined, AppStatusKind.warning),
    MovimentacaoTipo.transferencia => (Icons.swap_horiz, AppStatusKind.info),
    MovimentacaoTipo.ajusteInventario => (Icons.tune, AppStatusKind.info),
    MovimentacaoTipo.alteracaoResponsavel => (Icons.person_outline, AppStatusKind.info),
  };
}
