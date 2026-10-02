import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_page.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';

import '../../auth/fake_auth_repository.dart';

/// Smoke test de responsividade do assistente de importação (Etapa 2 do
/// design system): garante que o indicador de etapas e os passos do wizard
/// continuam sem overflow e sem exceções nas larguras representativas do
/// app — desktop grande, desktop padrão, janela estreita e um tamanho
/// "mobile" (a plataforma validada é Windows desktop, mas o layout não pode
/// quebrar em larguras menores). Não é golden test: só verifica que a
/// árvore de widgets constrói e assenta normalmente.
class _ControladorComEstadoForcado extends PatrimonioImportController {
  void forcarEstado(PatrimonioImportState estado) {
    state = estado;
  }
}

Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

const _larguras = [1440.0, 1024.0, 800.0, 390.0];

Future<void> _pumpEm(WidgetTester tester, double largura, PatrimonioImportState? estadoForcado) async {
  tester.view.physicalSize = Size(largura, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      patrimonioImportControllerProvider.overrideWith(_ControladorComEstadoForcado.new),
    ],
  );
  addTearDown(container.dispose);
  container.listen(patrimonioImportControllerProvider, (_, _) {});

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: PatrimonioImportPage())),
    ),
  );
  // Primeiro deixa a resolução assíncrona do usuário autenticado (fake)
  // assentar — só depois força o estado, senão o `ref.listen` de
  // `PatrimonioImportController.build()` (que reseta o estado ao resolver
  // o usuário autenticado) sobrescreveria o estado forçado.
  await tester.pumpAndSettle();

  if (estadoForcado != null) {
    final controller =
        container.read(patrimonioImportControllerProvider.notifier) as _ControladorComEstadoForcado;
    controller.forcarEstado(estadoForcado);
    await tester.pumpAndSettle();
  }
}

/// Abaixo de 600px (`Breakpoints.mobileMax`) o `InvTecPageHeader` colapsa o
/// botão de voltar para um ícone com tooltip (sem o texto do label) — ver
/// `_BackButton` em `lib/core/widgets/page_header.dart`. Nas larguras
/// maiores o texto continua visível.
Finder _botaoCancelar(double largura) =>
    largura < 600 ? find.byTooltip('Cancelar importação') : find.text('Cancelar importação');

void main() {
  for (final largura in _larguras) {
    testWidgets('${largura.toInt()}px: passo "Selecionar arquivo" sem overflow/exceções', (tester) async {
      await _pumpEm(tester, largura, null);

      expect(find.text('Selecionar arquivo'), findsOneWidget);
      expect(_botaoCancelar(largura), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${largura.toInt()}px: passo "Resultado" (indicador no último marco) sem overflow/exceções', (
      tester,
    ) async {
      await _pumpEm(tester, largura, PatrimonioImportState(step: ImportStep.resultado));

      expect(find.text('Importação concluída', skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
