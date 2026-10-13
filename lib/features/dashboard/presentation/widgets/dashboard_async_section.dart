import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/empty_state.dart';

/// Trata [value] de forma idêntica em toda seção independente do
/// Dashboard (KPIs, distribuição, movimentações recentes, atenção): `null`
/// fica oculto (sem permissão — nunca "vazio" nem "erro"), erro mostra
/// mensagem amigável + "Tentar novamente" só DESTA seção, e carregando
/// mostra um indicador discreto — nunca a tela inteira trava por uma seção
/// só (seção 16 do pedido: "uma falha em movimentações não deve destruir
/// todo o Dashboard").
Widget dashboardAsyncSection<T>({
  required AsyncValue<T?> value,
  required Widget Function(T data) builder,
  required VoidCallback onRetry,
  double minHeight = 140,
}) {
  return value.when(
    data: (data) => data == null ? const SizedBox.shrink() : builder(data),
    loading: () => SizedBox(height: minHeight, child: const Center(child: CircularProgressIndicator())),
    // `minHeight` aqui é um PISO (ConstrainedBox), nunca um teto fixo como
    // no loading acima — o conteúdo do estado de erro (ícone + mensagem +
    // botão "Tentar novamente") pode ser mais alto que `minHeight` e
    // precisa poder crescer livremente, sem estourar um `SizedBox` de
    // altura exata.
    error: (error, stackTrace) => ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Center(
        child: EmptyState(
          icon: Icons.error_outline,
          message: 'Não foi possível carregar estes dados.',
          actionLabel: 'Tentar novamente',
          onAction: onRetry,
        ),
      ),
    ),
  );
}
