import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/shell/bottom_nav.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/core/config/platform_info.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/notificacoes/fake_app_notification_repository.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
);

/// Sobe o app autenticado em [largura]. Overflow e outros erros de framework
/// são lidos depois com `tester.takeException()`.
Future<void> _pump(
  WidgetTester tester, {
  required double largura,
  required bool android,
  ProfilePerfil perfil = ProfilePerfil.admin,
}) async {
  tester.view.physicalSize = Size(largura, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(auth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isAndroidProvider.overrideWithValue(android),
        authRepositoryProvider.overrideWithValue(auth),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(),
        ),
        patrimonioRepositoryProvider.overrideWithValue(
          FakePatrimonioRepository(),
        ),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(),
        ),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
        appNotificationRepositoryProvider.overrideWithValue(
          FakeAppNotificationRepository(),
        ),
      ],
      child: const InvTecApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final largura in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets('Android $largura px: barra inferior navega sem overflow', (
      tester,
    ) async {
      await _pump(tester, largura: largura, android: true);

      final barra = find.byType(InvTecBottomNav);
      expect(barra, findsOneWidget);
      expect(
        find.descendant(of: barra, matching: find.text('Escanear')),
        findsOneWidget,
      );

      for (final rotulo in ['Patrimônios', 'Movimentações', 'Início']) {
        await tester.tap(
          find.descendant(of: barra, matching: find.text(rotulo)),
        );
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });
  }

  for (final largura in [320.0, 360.0, 390.0, 412.0]) {
    for (final escala in [1.0, 1.3, 2.0]) {
      testWidgets('layout da barra $largura px, fonte ${escala}x', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = escala;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, largura: largura, android: true);

        final barra = find.byType(InvTecBottomNav);
        expect(barra, findsOneWidget);
        expect(tester.widget<InvTecBottomNav>(barra).items.length, 4);
        final rotulos = ['Início', 'Patrimônios', 'Escanear', 'Movimentações'];
        final centros = <double>[];
        for (final r in rotulos) {
          final t = find.descendant(of: barra, matching: find.text(r));
          expect(t, findsOneWidget, reason: r);
          // Uma única linha: altura de um texto de 11sp.
          expect(tester.getSize(t).height, lessThan(20), reason: r);
          centros.add(tester.getCenter(t).dx);
        }
        final w = largura / 4;
        for (var i = 0; i < 4; i++) {
          expect(centros[i], closeTo(w * i + w / 2, 0.6), reason: rotulos[i]);
        }
        for (final icone
            in find
                .descendant(of: barra, matching: find.byType(Icon))
                .evaluate()) {
          expect((icone.widget as Icon).size, 24);
        }
        expect(tester.getSize(barra).height, InvTecBottomNav.altura);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('barra respeita a área segura do Android', (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await _pump(tester, largura: 360, android: true);
    final barra = find.byType(InvTecBottomNav);
    expect(tester.getSize(barra).height, InvTecBottomNav.altura + 24);
    expect(tester.getBottomLeft(barra).dy, 780);
    // Ícones/legendas acima da faixa do sistema.
    final r = find.descendant(of: barra, matching: find.text('Início'));
    expect(tester.getBottomLeft(r).dy, lessThanOrEqualTo(780 - 24));
    expect(tester.takeException(), isNull);
  });

  // Telas principais em 360 px com fonte do sistema ampliada (acessibilidade)
  // e teclado aberto: nenhuma deve estourar layout.
  for (final rota in [
    '/dashboard',
    '/patrimonios',
    '/patrimonios/novo',
    '/movimentacoes',
    '/setores',
    '/configuracoes',
    '/administracao/usuarios',
  ]) {
    testWidgets('360 px, fonte 1.3x e teclado: $rota sem overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, largura: 360, android: true);

      tester.element(find.byType(InvTecBottomNav)).go(rota);
      await tester.pumpAndSettle();
      final e1 = tester.takeException();
      if (e1 is FlutterError) debugPrint(e1.toStringDeep());
      expect(e1, isNull, reason: 'sem teclado');

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'com teclado');
    });
  }

  for (final largura in [320.0, 360.0, 390.0, 412.0]) {
    for (final rota in ['/login', '/cadastro']) {
      testWidgets('deslogado $largura px, fonte 1.3x e teclado: $rota', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = Size(largura, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = FakeAuthRepository();
        addTearDown(auth.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authRepositoryProvider.overrideWithValue(auth)],
            child: const InvTecApp(),
          ),
        );
        await tester.pumpAndSettle();
        tester.element(find.byType(Scaffold).first).go(rota);
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Teclado aberto: o campo focado precisa continuar rolável até a tela.
        expect(find.byType(Scrollable), findsWidgets);
      });
    }
  }

  testWidgets('sem Android a barra não oferece Escanear nem Setores', (
    tester,
  ) async {
    await _pump(tester, largura: 390, android: false);
    final barra = find.byType(InvTecBottomNav);
    expect(
      find.descendant(of: barra, matching: find.text('Escanear')),
      findsNothing,
    );
    expect(
      find.descendant(of: barra, matching: find.text('Setores')),
      findsNothing,
    );
    expect(
      find.descendant(of: barra, matching: find.text('Movimentações')),
      findsOneWidget,
    );
  });

  testWidgets('barra inferior nunca mostra Administração para não-ADMIN', (
    tester,
  ) async {
    await _pump(
      tester,
      largura: 390,
      android: true,
      perfil: ProfilePerfil.consulta,
    );
    expect(
      find.descendant(
        of: find.byType(InvTecBottomNav),
        matching: find.text('Administração'),
      ),
      findsNothing,
    );
  });

  testWidgets('desktop não monta a barra inferior', (tester) async {
    await _pump(tester, largura: 1280, android: false);
    expect(find.byType(InvTecBottomNav), findsNothing);
  });
}
