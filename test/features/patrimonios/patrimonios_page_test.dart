import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_page.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';

import '../auth/fake_auth_repository.dart';
import '../localizacoes/fake_localizacao_repository.dart';
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
  String? numeroSerie,
  String? marca,
  String? localizacaoId,
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  DateTime? dataCadastro,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      numeroSerie: numeroSerie,
      marca: marca,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: 'setor-1',
      localizacaoAtualId: localizacaoId,
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
  FakeLocalizacaoRepository? localizacaoRepo,
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
        localizacaoRepositoryProvider.overrideWithValue(
          localizacaoRepo ?? FakeLocalizacaoRepository(),
        ),
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
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.text('Nenhum patrimônio encontrado para "inexistente".'),
        findsOneWidget,
      );
    });

    testWidgets(
      'PROMPT 9.1.1 — BUG REAL: Tudo + "2703522" nunca mostra 2703532 como resultado principal; '
      'aviso separado identifica a correspondência por número de série, com ação para ver',
      (tester) async {
        await _pumpPatrimoniosPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: FakePatrimonioRepository(
            itens: [_item('1', numero: '2703532', numeroSerie: '2703522', marca: 'MICROSOFT')],
          ),
        );

        await tester.enterText(find.byType(TextField), '2703522');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // nunca aparece como se fosse o patrimônio pesquisado.
        expect(find.text('2703532'), findsNothing);
        expect(find.text('Nenhum patrimônio nº "2703522" encontrado.'), findsOneWidget);
        expect(find.text('1 equipamento possui "2703522" como número de série.'), findsOneWidget);

        final botaoVerResultado = find.widgetWithText(TextButton, 'Ver resultado');
        await tester.ensureVisible(botaoVerResultado);
        await tester.pumpAndSettle();
        await tester.tap(botaoVerResultado);
        await tester.pumpAndSettle();

        // ao pedir explicitamente para ver, o modo muda para "Número de
        // série" e o patrimônio aparece — agora sem ambiguidade nenhuma.
        expect(find.text('Número de série'), findsWidgets);
        expect(find.text('2703532'), findsOneWidget);
      },
    );

    testWidgets(
      'PROMPT 9.1.1 — campo Patrimônio + "2703522" continua mostrando só a mensagem genérica, '
      'sem o aviso de correspondência por série',
      (tester) async {
        await _pumpPatrimoniosPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: FakePatrimonioRepository(
            itens: [_item('1', numero: '2703532', numeroSerie: '2703522')],
          ),
        );

        await tester.tap(find.text('Tudo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Patrimônio').last);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '2703522');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.text('Nenhum patrimônio encontrado para "2703522".'), findsOneWidget);
        expect(find.textContaining('como número de série'), findsNothing);
      },
    );

    testWidgets('seletor de campo de busca aparece com "Tudo" como padrão', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(),
      );

      expect(find.text('Buscar em'), findsOneWidget);
      expect(find.text('Tudo'), findsOneWidget);

      await tester.tap(find.text('Tudo'));
      await tester.pumpAndSettle();

      for (final opcao in [
        'Patrimônio',
        'Número de série',
        'Equipamento / Descrição',
        'Marca / Modelo',
        'Responsável',
      ]) {
        expect(find.text(opcao), findsOneWidget, reason: 'opção "$opcao" deveria existir no seletor');
      }
      // "Localização" aparece duas vezes na tela nesse momento: a opção do
      // seletor de campo de busca (PROMPT 9.1) e o rótulo do filtro
      // "Localização" (PROMPT 9.2) — ambos legítimos, por isso `findsWidgets`
      // em vez de `findsOneWidget` só para esta opção.
      expect(
        find.text('Localização'),
        findsWidgets,
        reason: 'opção "Localização" deveria existir no seletor',
      );
    });

    testWidgets('trocar o seletor para Marca / Modelo restringe a busca a marca/modelo', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [
            _item('1', numero: '100', marca: 'DELL'),
            _item('2', numero: '200', marca: 'LENOVO'),
          ],
        ),
      );

      await tester.tap(find.text('Tudo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marca / Modelo').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'dell');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('100'), findsOneWidget);
      expect(find.text('200'), findsNothing);
    });

    testWidgets('Limpar filtros limpa o texto digitado e volta o seletor para Tudo', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [_item('1', numero: '100', marca: 'DELL')],
        ),
      );

      await tester.tap(find.text('Tudo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marca / Modelo').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'dell');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Limpar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Tudo'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'dell'), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
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
      // dataCadastro decrescente por índice: a listagem ordena do mais
      // recente para o mais antigo, então P0 (mais recente) cai na página 1
      // e P29 (mais antigo) na página 2 — determinístico, sem depender da
      // resolução do relógio do sistema.
      final itens = List.generate(
        30,
        (i) => _item(
          '$i',
          numero: 'P$i',
          dataCadastro: DateTime(2026, 1, 1).subtract(Duration(days: i)),
        ),
      );
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(itens: itens),
      );

      expect(find.text('P0'), findsOneWidget);
      expect(find.text('P29'), findsNothing);

      final botaoPagina2 = find.byKey(const ValueKey('pagination-page-2'));
      await tester.ensureVisible(botaoPagina2);
      await tester.pumpAndSettle();
      await tester.tap(botaoPagina2);
      await tester.pumpAndSettle();

      expect(find.text('P29'), findsOneWidget);
      expect(find.text('P0'), findsNothing);
    });

    testWidgets('PROMPT 9.2 — filtro Localização restringe a listagem por localizacao_atual_id', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [
            _item('1', numero: '100', localizacaoId: 'loc-a'),
            _item('2', numero: '200', localizacaoId: 'loc-b'),
          ],
        ),
        localizacaoRepo: FakeLocalizacaoRepository(
          localizacoes: [
            Localizacao(
              id: 'loc-a',
              setorId: 'setor-1',
              nome: 'GETEC - UNIVERSITÁRIO',
              ativo: true,
              criadoEm: DateTime(2026, 1, 1),
            ),
            Localizacao(
              id: 'loc-b',
              setorId: 'setor-1',
              nome: 'DATACENTER - UNIVERSITÁRIO',
              ativo: true,
              criadoEm: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );

      final campoLocalizacao = find.widgetWithText(DropdownButtonFormField<String>, 'Localização');
      expect(campoLocalizacao, findsOneWidget);
      await tester.ensureVisible(campoLocalizacao);
      await tester.tap(campoLocalizacao);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GETEC - UNIVERSITÁRIO').last);
      await tester.pumpAndSettle();

      expect(find.text('100'), findsOneWidget);
      expect(find.text('200'), findsNothing);
    });

    testWidgets('PROMPT 9.2 — "Sem localização" mostra só quem tem localizacao_atual_id nulo', (
      tester,
    ) async {
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(
          itens: [
            _item('1', numero: '100', localizacaoId: 'loc-a'),
            _item('2', numero: '200'),
          ],
        ),
        localizacaoRepo: FakeLocalizacaoRepository(
          localizacoes: [
            Localizacao(
              id: 'loc-a',
              setorId: 'setor-1',
              nome: 'GETEC - UNIVERSITÁRIO',
              ativo: true,
              criadoEm: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );

      final campoLocalizacao = find.widgetWithText(DropdownButtonFormField<String>, 'Localização');
      await tester.ensureVisible(campoLocalizacao);
      await tester.tap(campoLocalizacao);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem localização').last);
      await tester.pumpAndSettle();

      expect(find.text('200'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('PROMPT 9.2 — resumo "1–N de total" e seletor de itens por página', (
      tester,
    ) async {
      final itens = List.generate(30, (i) => _item('$i', numero: 'P$i'));
      await _pumpPatrimoniosPage(
        tester,
        perfil: ProfilePerfil.admin,
        patrimonioRepo: FakePatrimonioRepository(itens: itens),
      );

      expect(find.text('Mostrando 1–25 de 30 registros'), findsOneWidget);

      final seletorTamanho = find.byType(DropdownButton<int>);
      expect(seletorTamanho, findsOneWidget);
      await tester.ensureVisible(seletorTamanho);
      await tester.tap(seletorTamanho);
      await tester.pumpAndSettle();
      await tester.tap(find.text('50').last);
      await tester.pumpAndSettle();

      expect(find.text('Mostrando 1–30 de 30 registros'), findsOneWidget);
      expect(find.byKey(const ValueKey('pagination-page-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pagination-page-2')), findsNothing);
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
