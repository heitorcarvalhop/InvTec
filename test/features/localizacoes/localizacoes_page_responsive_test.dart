import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/localizacoes/presentation/localizacoes_page.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_localizacao_repository.dart';

/// Smoke test de responsividade (Etapa 2 do design system): garante que a
/// lista de Localizações e o estado vazio continuam sem overflow e sem
/// exceções nas larguras representativas do app — desktop grande, desktop
/// padrão, janela estreita e um tamanho "mobile". Não é golden test: só
/// verifica que a árvore de widgets constrói e assenta normalmente.
Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _setorGetec = Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1));

const _larguras = [1440.0, 1024.0, 800.0, 390.0];

Future<void> _pumpEm(WidgetTester tester, double largura, {required List<Localizacao> localizacoes}) async {
  tester.view.physicalSize = Size(largura, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: localizacoes)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: LocalizacoesPage(setor: _setorGetec)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final largura in _larguras) {
    testWidgets('${largura.toInt()}px: listagem com localizações sem overflow/exceções', (tester) async {
      await _pumpEm(
        tester,
        largura,
        localizacoes: [
          Localizacao(id: 'l1', setorId: 'setor-getec', nome: 'Home Office', sigla: 'HO', ativo: true, criadoEm: DateTime(2026, 1, 1)),
          Localizacao(id: 'l2', setorId: 'setor-getec', nome: 'Datacenter', ativo: false, criadoEm: DateTime(2026, 1, 1)),
        ],
      );

      expect(find.text('Home Office'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${largura.toInt()}px: estado vazio sem overflow/exceções', (tester) async {
      await _pumpEm(tester, largura, localizacoes: const []);

      expect(find.textContaining('não possui localizações'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
