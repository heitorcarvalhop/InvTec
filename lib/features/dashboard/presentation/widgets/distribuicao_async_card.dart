import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dashboard_distribuicoes.dart';
import '../dashboard_providers.dart';
import 'dashboard_async_section.dart';

/// As três seções derivadas de [dashboardDistribuicoesProvider]
/// ("Patrimônios por setor", "por tipo" e "Locais com mais patrimônios")
/// aparecem em LINHAS diferentes do grid do Dashboard (ver seção 27/12 do
/// pedido), não juntas — por isso cada uma assiste o MESMO provider de
/// forma independente (o Riverpod reaproveita a mesma `Future` em cache;
/// nunca dispara 3 consultas) e [builder] extrai só o pedaço que aquele
/// card precisa.
class DistribuicaoAsyncCard extends ConsumerWidget {
  const DistribuicaoAsyncCard({super.key, required this.builder});

  final Widget Function(DashboardDistribuicoes data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(dashboardDistribuicoesProvider);
    return dashboardAsyncSection<DashboardDistribuicoes>(
      value: value,
      onRetry: () => ref.invalidate(dashboardDistribuicoesProvider),
      builder: builder,
    );
  }
}
