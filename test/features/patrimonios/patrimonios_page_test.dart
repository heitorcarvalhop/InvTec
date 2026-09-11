import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_page.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../auth/fake_auth_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_patrimonio_repository.dart';
import 'fake_tipo_patrimonio_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

PatrimonioDetalhe _item(
  String id, {
  String? numero,
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  DateTime? dataCadastro,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: 'setor-1',
      dataCadastro: dataCadastro ?? DateTime.now(),
      atualizadoEm: DateTime.now(),
    ),
    tipoNome: 'Notebook',
    setorNome: 'GETEC',
  );
}

Future<void> _pumpPatrimoniosPage(
  WidgetTester tester, {
  required ProfilePerfil perfil,
  required FakePatrimonioRepository patrimonioRepo,
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(),
        ),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: PatrimoniosPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('estados da lista', () {
    testWidgets('banco vazio mostra mensagem e ação de cadastro para ADMIN', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(),
      );

      expect(
        find.textContaining('Nenhum patrimônio cadastrado.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Cadastrar patrimônio'),
        findsOneWidget,
      );
    });

    testWidgets('listagem mostra os patrimônios retornados', (tester) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [_item('1', numero: '00045872'), _item('2', numero: '123')],
        ),
      );

      expect(find.text('00045872'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
    });

    testWidgets('busca sem resultado mostra mensagem específica', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [_item('1', numero: '00045872')],
        ),
      );

      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum patrimônio encontrado para os critérios informados.'),
        findsOneWidget,
      );
    });

    testWidgets('patrimônio baixado continua visível na listagem', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [
            _item('1', numero: '999', status: PatrimonioStatus.baixado),
          ],
        ),
      );

      expect(find.text('999'), findsOneWidget);
      expect(find.text('Baixado'), findsOneWidget);
    });

    testWidgets('paginação aparece quando há mais de uma página', (
      tester,
    ) async {
      final itens = List.generate(
        30,
        (i) => _item('$i', numero: 'P$i'),
      );
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(itens: itens),
      );

      expect(find.text('Página 1 de 2'), findsOneWidget);

      final botaoProxima = find.widgetWithText(TextButton, 'Próxima');
      await tester.ensureVisible(botaoProxima);
      await tester.pumpAndSettle();
      await tester.tap(botaoProxima);
      await tester.pumpAndSettle();

      expect(find.text('Página 2 de 2'), findsOneWidget);
    });
  });

  group('permissões', () {
    final itens = [_item('1', numero: '00045872')];

    testWidgets('CONSULTA vê a listagem mas não vê Novo patrimônio nem editar', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.consulta,
        patrimonioRepo: FakePatrimonioRepository(itens: itens),
      );

      expect(find.text('00045872'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Novo patrimônio'),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Importar planilha'),
        findsNothing,
      );
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('OPERADOR vê "Novo patrimônio" e "Importar planilha" (RPC permite OPERADOR)', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.operador,
        patrimonioRepo: FakePatrimonioRepository(itens: itens),
      );

      expect(
        find.widgetWithText(FilledButton, 'Novo patrimônio'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Importar planilha'),
        findsOneWidget,
      );
    });

    testWidgets('ADMIN vê "Novo patrimônio" e "Importar planilha"', (tester) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(itens: itens),
      );

      expect(
        find.widgetWithText(FilledButton, 'Novo patrimônio'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Importar planilha'),
        findsOneWidget,
      );
    });
  });
}
