import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';
import 'package:invtec/features/setores/presentation/setores_page.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_setor_repository.dart';

/// Smoke test de responsividade (Etapa 2 do design system): garante que a
/// tabela/lista de Setores e o estado vazio continuam sem overflow e sem
/// exceções nas larguras representativas do app — desktop grande, desktop
/// padrão, janela estreita e um tamanho "mobile" (a plataforma validada é
/// Windows desktop, mas o layout não pode quebrar em larguras menores). Não
/// é golden test: só verifica que a árvore de widgets constrói e assenta
/// normalmente.
Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

const _larguras = [1440.0, 1024.0, 800.0, 390.0];

Future<void> _pumpEm(WidgetTester tester, double largura, {required List<Setor> setores}) async {
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
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const Scaffold(body: SetoresPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final largura in _larguras) {
    testWidgets('${largura.toInt()}px: listagem com setores sem overflow/exceções', (tester) async {
      await _pumpEm(
        tester,
        largura,
        setores: [
          Setor(
            id: '1',
            nome: 'Almoxarifado',
            sigla: 'ALM',
            descricao: 'Controle de materiais',
            ativo: true,
            criadoEm: DateTime.now(),
          ),
          Setor(id: '2', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime.now()),
        ],
      );

      expect(find.text('Almoxarifado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${largura.toInt()}px: estado vazio sem overflow/exceções', (tester) async {
      await _pumpEm(tester, largura, setores: const []);

      expect(find.textContaining('Nenhum setor cadastrado.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
