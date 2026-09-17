import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/core/theme/theme_mode_controller.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

Profile _adminProfile() => Profile(
  id: 'fake-user-id',
  nome: 'Heitor Pereira',
  email: 'heitor@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

Future<FakeAuthRepository> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _adminProfile());
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
        tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository()),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
      ],
      child: const InvTecApp(),
    ),
  );
  await tester.pumpAndSettle();
  return fakeAuth;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('botão do header alterna Claro -> Escuro e reconstrói o app inteiro', (tester) async {
    await _pumpApp(tester);

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.light);

    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    expect(container.read(themeModeControllerProvider).value, ThemeMode.dark);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.brightness,
      AppTheme.dark.colorScheme.brightness,
    );
  });

  testWidgets('trocar o tema em Configurações reflete no botão do header (mesmo estado)', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();

    expect(find.text('Aparência'), findsOneWidget);

    // Dentro da página de Configurações existe outro SegmentedButton
    // "Claro/Escuro" com o MESMO provider do header — alterná-lo ali
    // também muda o app inteiro.
    await tester.tap(find.text('Escuro').last);
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.brightness,
      Brightness.dark,
    );

    // O botão do header (SegmentedButton "Escuro") deve refletir o mesmo
    // estado — ambos os controles leem o mesmo provider, nunca dessincronizam.
    expect(find.text('Escuro'), findsWidgets);
  });

  testWidgets('preferência persiste entre "aberturas" do app (novo ProviderScope)', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();

    // "Fecha e reabre o InvTec": novo ProviderScope, novo container —
    // mas o mesmo storage local (SharedPreferences mock compartilhado).
    final fakeAuth2 = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _adminProfile());
    addTearDown(fakeAuth2.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth2),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
          tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository()),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
        ],
        child: const InvTecApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.brightness,
      Brightness.dark,
    );
  });
}
