import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/active_filter_chip.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_ordenacao.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_page.dart';
import 'package:invtec/features/patrimonios/presentation/widgets/patrimonio_cards_grid.dart';
import 'package:invtec/features/patrimonios/presentation/widgets/patrimonio_desktop_table.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/fake_auth_repository.dart';
import '../localizacoes/fake_localizacao_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_patrimonio_repository.dart';
import 'fake_tipo_patrimonio_repository.dart';

/// Testes de nível de página para a camada visual de ordenação
/// (cabeçalhos clicáveis + controle "Ordenar por") e de visualização
/// (Lista/Cards + persistência), construídos sobre [FakePatrimonioRepository]
/// — nunca contra o Supabase real. A janela usada (1280x900) é desktop
/// "comum" (ver `Breakpoints`), onde a tabela/grade aparece normalmente.
Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

PatrimonioDetalhe _item(
  String id, {
  required String numero,
  String marca = 'Dell',
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  DateTime? dataCadastro,
  String setorAtualId = 'setor-1',
  String setorNome = 'GETEC',
  String? setorSigla = 'GETEC',
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      marca: marca,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: setorAtualId,
      dataCadastro: dataCadastro ?? DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: setorNome,
    setorSigla: setorSigla,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<PatrimonioDetalhe> itens,
  List<Setor>? setores,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository(itens: itens)),
        tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository()),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
        localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
      ],
      child: const MaterialApp(home: Scaffold(body: PatrimoniosPage())),
    ),
  );
  await tester.pumpAndSettle();
}

/// Texto dentro do cabeçalho da tabela — nunca ambíguo com o rótulo do campo
/// já selecionado no controle "Ordenar por" (que também pode mostrar o MESMO
/// texto, ex.: "Patrimônio", quando esse campo está escolhido).
Finder _headerText(String texto) =>
    find.descendant(of: find.byType(PatrimonioDesktopTable), matching: find.text(texto));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ordenação por cabeçalho', () {
    testWidgets('clicar em "Patrimônio" ordena ASC (seta correta e reordena), de novo DESC, terceiro clique volta ao padrão', (
      tester,
    ) async {
      await _pump(
        tester,
        itens: [
          _item('b', numero: 'B200', dataCadastro: DateTime(2026, 1, 5)),
          _item('a', numero: 'A100', dataCadastro: DateTime(2026, 1, 1)),
        ],
      );

      // Estado inicial: nenhuma ordenação ativa (padrão = cadastro recente).
      expect(find.byTooltip('Ordenar por Patrimônio'), findsOneWidget);

      await tester.tap(_headerText('Patrimônio'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Patrimônio, ordem crescente'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('A100')).dy,
        lessThan(tester.getTopLeft(find.text('B200')).dy),
        reason: 'ASC por número de patrimônio (texto): A100 antes de B200',
      );

      await tester.tap(_headerText('Patrimônio'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Patrimônio, ordem decrescente'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('B200')).dy,
        lessThan(tester.getTopLeft(find.text('A100')).dy),
        reason: 'DESC por número de patrimônio (texto): B200 antes de A100',
      );

      await tester.tap(_headerText('Patrimônio'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Ordenar por Patrimônio'), findsOneWidget);
      expect(find.text('Padrão'), findsOneWidget, reason: 'controle "Ordenar por" volta ao hint padrão');
    });
  });

  group('"Ordenar por" (controle da toolbar)', () {
    testWidgets('funciona para um campo sem coluna visível (Marca), com direção alternável', (tester) async {
      await _pump(
        tester,
        itens: [
          _item('z', numero: '200', marca: 'Zebra'),
          _item('a', numero: '100', marca: 'Acme'),
        ],
      );

      await tester.tap(find.byType(DropdownButton<PatrimonioOrdenacaoCampo?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marca').last);
      await tester.pumpAndSettle();

      final dropdown = tester.widget<DropdownButton<PatrimonioOrdenacaoCampo?>>(
        find.byType(DropdownButton<PatrimonioOrdenacaoCampo?>),
      );
      expect(dropdown.value, PatrimonioOrdenacaoCampo.marca);
      expect(find.byTooltip('Ordem crescente — clique para inverter'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('100')).dy,
        lessThan(tester.getTopLeft(find.text('200')).dy),
        reason: 'ASC por marca: Acme (100) antes de Zebra (200)',
      );

      await tester.tap(find.byTooltip('Ordem crescente — clique para inverter'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Ordem decrescente — clique para inverter'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('200')).dy,
        lessThan(tester.getTopLeft(find.text('100')).dy),
        reason: 'DESC por marca: Zebra (200) antes de Acme (100)',
      );
    });
  });

  group('trocar de Lista para Cards', () {
    testWidgets('preserva a ordenação escolhida (mesmo estado do controller)', (tester) async {
      await _pump(
        tester,
        itens: [
          _item('b', numero: 'B200', dataCadastro: DateTime(2026, 1, 5)),
          _item('a', numero: 'A100', dataCadastro: DateTime(2026, 1, 1)),
        ],
      );

      await tester.tap(_headerText('Patrimônio'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButton<PatrimonioOrdenacaoCampo?>>(
              find.byType(DropdownButton<PatrimonioOrdenacaoCampo?>),
            )
            .value,
        PatrimonioOrdenacaoCampo.numeroPatrimonio,
      );

      await tester.tap(find.byTooltip('Cards'));
      await tester.pumpAndSettle();

      expect(find.byType(PatrimonioCardsGrid), findsOneWidget);
      expect(find.byType(PatrimonioDesktopTable), findsNothing);
      expect(
        tester
            .widget<DropdownButton<PatrimonioOrdenacaoCampo?>>(
              find.byType(DropdownButton<PatrimonioOrdenacaoCampo?>),
            )
            .value,
        PatrimonioOrdenacaoCampo.numeroPatrimonio,
        reason: 'trocar para Cards não reseta a ordenação do controller',
      );
    });
  });

  group('view mode (Lista/Cards)', () {
    testWidgets('padrão é Lista', (tester) async {
      await _pump(tester, itens: [_item('1', numero: '100')]);

      expect(find.byType(PatrimonioDesktopTable), findsOneWidget);
      expect(find.byType(PatrimonioCardsGrid), findsNothing);
    });

    testWidgets('trocar para Cards funciona e a preferência persiste entre "aberturas" (SharedPreferences compartilhado)', (
      tester,
    ) async {
      await _pump(tester, itens: [_item('1', numero: '100')]);

      await tester.tap(find.byTooltip('Cards'));
      await tester.pumpAndSettle();

      expect(find.byType(PatrimonioCardsGrid), findsOneWidget);
      expect(find.byType(PatrimonioDesktopTable), findsNothing);

      // "Fecha e reabre o InvTec": novo ProviderScope — mas o mesmo
      // SharedPreferences mock compartilhado (setUp só roda uma vez por
      // teste).
      await _pump(tester, itens: [_item('1', numero: '100')]);

      expect(find.byType(PatrimonioCardsGrid), findsOneWidget);
      expect(find.byType(PatrimonioDesktopTable), findsNothing);
    });
  });

  group('chips de filtro ativo', () {
    testWidgets('nenhum chip aparece quando não há filtro ativo', (tester) async {
      await _pump(tester, itens: [_item('1', numero: '100'), _item('2', numero: '200')]);

      expect(find.byType(ActiveFilterChip), findsNothing);
    });

    testWidgets('cada chip remove só o seu filtro (Status e Setor são independentes)', (tester) async {
      await _pump(
        tester,
        itens: [
          _item('1', numero: '100', status: PatrimonioStatus.emUso, setorAtualId: 'setor-1', setorSigla: 'GE1'),
          _item('2', numero: '200', status: PatrimonioStatus.baixado, setorAtualId: 'setor-2', setorSigla: 'GE2'),
        ],
        setores: [
          Setor(id: 'setor-1', nome: 'Gerência Um', sigla: 'GE1', ativo: true, criadoEm: DateTime(2026, 1, 1)),
          Setor(id: 'setor-2', nome: 'Gerência Dois', sigla: 'GE2', ativo: true, criadoEm: DateTime(2026, 1, 1)),
        ],
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Filtros'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<PatrimonioStatus?>, 'Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Em uso').last);
      await tester.pumpAndSettle();

      final setorDropdown = find.widgetWithText(DropdownButtonFormField<String?>, 'Setor atual');
      await tester.ensureVisible(setorDropdown);
      await tester.tap(setorDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GE1').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActiveFilterChip, 'Status: Em uso'), findsOneWidget);
      expect(find.widgetWithText(ActiveFilterChip, 'Setor: GE1'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('200'), findsNothing);

      // Remove só o chip de Status — usa o tooltip padrão ("Delete") do
      // botão de remoção do `InputChip` em vez do ícone (que varia conforme
      // a versão do Material).
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Status: Em uso'),
          matching: find.byTooltip('Delete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ActiveFilterChip, 'Status: Em uso'), findsNothing);
      expect(
        find.widgetWithText(ActiveFilterChip, 'Setor: GE1'),
        findsOneWidget,
        reason: 'remover um chip nunca remove os outros filtros ativos',
      );
    });
  });
}
