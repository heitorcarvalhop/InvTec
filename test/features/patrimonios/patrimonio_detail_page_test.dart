import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_detail_page.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_patrimonio_repository.dart';
import 'fake_tipo_patrimonio_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _tipos = [
  TipoPatrimonio(id: 'tipo-1', nome: 'Notebook', ativo: true, criadoEm: DateTime.now()),
];
final _setores = [
  Setor(id: 'setor-1', nome: 'GETEC', ativo: true, criadoEm: DateTime.now()),
];

Future<void> _pumpDetailPage(
  WidgetTester tester, {
  required PatrimonioDetalhe detalhe,
  ProfilePerfil perfil = ProfilePerfil.admin,
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
        patrimonioRepositoryProvider.overrideWithValue(
          FakePatrimonioRepository(itens: [detalhe]),
        ),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(tipos: _tipos),
        ),
        setorRepositoryProvider.overrideWithValue(
          FakeSetorRepository(setores: _setores),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: PatrimonioDetailPage(id: detalhe.patrimonio.id)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra os campos do patrimônio', (tester) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '00045872',
        numeroSerie: 'ABC123',
        tipoId: 'tipo-1',
        marca: 'Dell',
        modelo: 'Latitude 5440',
        descricao: 'Notebook corporativo',
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        responsavelAtual: 'João Silva',
        dataCadastro: DateTime.utc(2026, 1, 10),
        atualizadoEm: DateTime.utc(2026, 1, 10),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
      criadoPorNome: 'Heitor Pereira',
    );

    await _pumpDetailPage(tester, detalhe: detalhe);

    // Aparece duas vezes: no título e no campo "Número patrimonial".
    expect(find.text('00045872'), findsNWidgets(2));
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Dell'), findsOneWidget);
    expect(find.text('Latitude 5440'), findsOneWidget);
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.text('GETEC'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Em uso'), findsOneWidget);
    expect(find.text('Heitor Pereira'), findsOneWidget);
    expect(
      find.textContaining('histórico completo de movimentações'),
      findsOneWidget,
    );
  });

  testWidgets('patrimônio baixado é exibido claramente, sem botão de reativar', (
    tester,
  ) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.baixado,
        setorAtualId: 'setor-1',
        dataCadastro: DateTime.now(),
        atualizadoEm: DateTime.now(),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
    );

    await _pumpDetailPage(tester, detalhe: detalhe);

    expect(find.text('Baixado'), findsOneWidget);
    expect(find.textContaining('Reativar'), findsNothing);
  });

  testWidgets('edição não expõe campos de status, setor ou responsável', (
    tester,
  ) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '999',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        responsavelAtual: 'João Silva',
        dataCadastro: DateTime.now(),
        atualizadoEm: DateTime.now(),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
    );

    await _pumpDetailPage(tester, detalhe: detalhe);

    await tester.tap(find.widgetWithText(FilledButton, 'Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Editar patrimônio'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Número patrimonial'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Marca'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Modelo'), findsOneWidget);

    // Nenhum campo de status/setor/responsável dentro do diálogo de edição
    // (a página de detalhe por trás dele mostra "Responsável atual" — por
    // isso a busca é restrita ao Dialog, não à árvore inteira).
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(DropdownButtonFormField<String>, 'Status'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(DropdownButtonFormField<String>, 'Setor atual'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('Responsável'),
      ),
      findsNothing,
    );
  });

  testWidgets('CONSULTA não vê o botão Editar', (tester) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.disponivel,
        setorAtualId: 'setor-1',
        dataCadastro: DateTime.now(),
        atualizadoEm: DateTime.now(),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
    );

    await _pumpDetailPage(tester, detalhe: detalhe, perfil: ProfilePerfil.consulta);

    expect(find.widgetWithText(FilledButton, 'Editar'), findsNothing);
  });
}
