import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/core/widgets/list_view_mode.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_detail_page.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_form_page.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_page.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonios_view_mode_controller.dart';
import 'package:invtec/features/patrimonios/presentation/widgets/patrimonio_cards_grid.dart';
import 'package:invtec/features/patrimonios/presentation/widgets/patrimonio_mobile_list.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import '../dashboard/fake_dashboard_repository.dart';
import '../localizacoes/fake_localizacao_repository.dart';
import '../movimentacoes/fake_movimentacao_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_patrimonio_repository.dart';
import 'fake_tipo_patrimonio_repository.dart';

/// Larguras representativas: desktop largo, breakpoint desktop/tablet,
/// tablet e mobile — ver `lib/core/responsive/breakpoints.dart`
/// (`mobileMax = 600`, `tabletMax = 1024`).
const _larguras = [1440.0, 1024.0, 800.0, 390.0];

Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _tipos = [
  TipoPatrimonio(id: 'tipo-1', nome: 'Notebook', ativo: true, criadoEm: DateTime.now()),
];

final _setores = [
  Setor(
    id: 'setor-1',
    nome: 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
    sigla: 'GEASI',
    ativo: true,
    criadoEm: DateTime.now(),
  ),
];

PatrimonioDetalhe _item(String id) => PatrimonioDetalhe(
  patrimonio: Patrimonio(
    id: id,
    numeroPatrimonio: '00045872',
    numeroSerie: 'SERIE-XYZ-987',
    tipoId: 'tipo-1',
    marca: 'Fabricante com nome bastante comprido',
    modelo: 'Modelo ' * 6,
    descricao:
        'Notebook corporativo com 32 GB de memória, SSD de 1 TB, docking '
        'station e garantia estendida até 2028, adquirido para a equipe de '
        'suporte técnico da gerência.',
    observacao: 'Observação de teste também bem longa para validar quebra de texto em telas estreitas.',
    status: PatrimonioStatus.emUso,
    setorAtualId: 'setor-1',
    responsavelAtual: 'João da Silva Pereira',
    dataAquisicao: DateTime.utc(2025, 3, 1),
    dataCadastro: DateTime.utc(2026, 1, 10),
    atualizadoEm: DateTime.utc(2026, 1, 10),
  ),
  tipoNome: 'Notebook',
  setorNome: 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
  setorSigla: 'GEASI',
  localizacaoNome: 'Sala 12 - Almoxarifado',
  criadoPorNome: 'Heitor Pereira',
);

void _definirTamanho(WidgetTester tester, double largura) {
  tester.view.physicalSize = Size(largura, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Roda [build] sob [largura], falhando o teste se o `FlutterError` global
/// reportar overflow ou qualquer outra exceção durante a renderização —
/// smoke test de responsividade, não golden test (não valida pixel).
Future<void> _semOverflow(
  WidgetTester tester,
  double largura,
  Widget Function() build,
) async {
  _definirTamanho(tester, largura);
  final erros = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (details) => erros.add(details.toString());

  await tester.pumpWidget(build());
  await tester.pumpAndSettle();

  FlutterError.onError = anterior;

  expect(
    erros.where((e) => e.toLowerCase().contains('overflow')),
    isEmpty,
    reason: 'overflow em ${largura}px: ${erros.join('\n')}',
  );
  expect(tester.takeException(), isNull, reason: 'exceção em ${largura}px');
}

void main() {
  for (final largura in _larguras) {
    testWidgets('Patrimônios (lista/filtros/tabela) sem overflow em ${largura}px', (tester) async {
      final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
      addTearDown(fakeAuth.dispose);

      await _semOverflow(
        tester,
        largura,
        () => ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            patrimonioRepositoryProvider.overrideWithValue(
              FakePatrimonioRepository(itens: [_item('1'), _item('2')]),
            ),
            tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
            localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
          ],
          child: const MaterialApp(home: Scaffold(body: PatrimoniosPage())),
        ),
      );
    });

    testWidgets('Novo patrimônio (formulário) sem overflow em ${largura}px', (tester) async {
      final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
      addTearDown(fakeAuth.dispose);

      await _semOverflow(
        tester,
        largura,
        () => ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
            tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
            dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
            localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
          ],
          child: const MaterialApp(home: Scaffold(body: PatrimonioFormPage())),
        ),
      );
    });

    testWidgets('Detalhe do patrimônio sem overflow em ${largura}px', (tester) async {
      final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
      addTearDown(fakeAuth.dispose);
      final detalhe = _item('1');

      await _semOverflow(
        tester,
        largura,
        () => ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository(itens: [detalhe])),
            tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
            movimentacaoRepositoryProvider.overrideWithValue(FakeMovimentacaoRepository()),
          ],
          child: MaterialApp(home: Scaffold(body: PatrimonioDetailPage(id: detalhe.patrimonio.id))),
        ),
      );
    });

    testWidgets('Patrimônios em modo Cards sem overflow em ${largura}px', (tester) async {
      final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile());
      addTearDown(fakeAuth.dispose);

      await _semOverflow(
        tester,
        largura,
        () => ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            patrimonioRepositoryProvider.overrideWithValue(
              FakePatrimonioRepository(itens: [_item('1'), _item('2'), _item('3')]),
            ),
            tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
            localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
            // Força o modo Cards direto (sem depender de SharedPreferences
            // nem de um clique prévio) — em mobile a página ignora esta
            // preferência e usa a lista de 1 coluna de qualquer forma (ver
            // PatrimoniosPage).
            patrimoniosViewModeControllerProvider.overrideWith(_ViewModeFixoCards.new),
          ],
          child: const MaterialApp(home: Scaffold(body: PatrimoniosPage())),
        ),
      );

      // Em larguras não-mobile, a grade de cards realmente apareceu (prova
      // que o teste está de fato exercitando o modo Cards, não caindo de
      // volta para a tabela por engano) — e nenhum card ficou espremido
      // demais.
      if (largura >= 600) {
        expect(find.byType(PatrimonioCardsGrid), findsOneWidget);
        final cartoes = find.byType(PatrimonioCard);
        expect(cartoes, findsWidgets);
        for (final elemento in cartoes.evaluate()) {
          final larguraCard = tester.getSize(find.byWidget(elemento.widget)).width;
          expect(larguraCard, greaterThanOrEqualTo(150), reason: 'card estreito demais em ${largura}px');
        }
      }
    });
  }
}

/// Resolve [ListViewMode.cards] imediatamente, sem depender de
/// `SharedPreferences` — só para os smoke tests de responsividade
/// exercitarem o layout de Cards em todas as larguras sem precisar simular
/// o clique no alternador Lista/Cards em cada uma.
class _ViewModeFixoCards extends PatrimoniosViewModeController {
  @override
  Future<ListViewMode> build() async => ListViewMode.cards;
}
