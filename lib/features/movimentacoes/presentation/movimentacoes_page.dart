import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class MovimentacoesPage extends StatelessWidget {
  const MovimentacoesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Movimentações',
      description: 'Consulte o histórico de movimentações dos patrimônios.',
      icon: Icons.swap_horiz_outlined,
    );
  }
}
