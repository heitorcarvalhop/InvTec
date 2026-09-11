import 'package:flutter/material.dart';

import '../../../core/widgets/placeholder_page.dart';

class ConfiguracoesPage extends StatelessWidget {
  const ConfiguracoesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: 'Configurações',
      description: 'Preferências do sistema e da sua conta.',
      icon: Icons.settings_outlined,
    );
  }
}
