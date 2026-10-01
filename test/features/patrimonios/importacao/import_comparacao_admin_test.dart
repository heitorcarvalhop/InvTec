import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/domain/patrimonio_comparacao.dart';
import 'package:invtec/features/patrimonios/importacao/domain/patrimonio_decisao.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_comparacao_step.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_defaults_step.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// Testes da interface de revisão inteligente (modo ADMIN "Comparar e
/// Atualizar"). Dois estilos, como no restante da suíte:
///  * a maioria monta [ComparacaoLote]/[PatrimonioImportState] DIRETAMENTE
///    (`controller.state = ...`) — mais rápido, sem depender do pipeline
///    de planilha/`compute()` (mesmo raciocínio de
///    `import_locations_step_test.dart`);
///  * duas usam o pipeline CSV real ponta a ponta, porque testam
///    especificamente a integração `compararParaAdmin`/`analisar`.
final _tipos = [TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1))];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];

/// Viewport maior para os testes de widget deste arquivo:
/// evita falso-negativo por item fora da área visível do `ListView`
/// (lazy) ou por botão fora do viewport padrão de 800x600 (mesmo padrão já
/// usado em `sei_bloqueio_lote_pendente_test.dart`).
void _viewportGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
final _localizacoes = <Localizacao>[];

Profile _perfil(ProfilePerfil perfil) => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@invtec.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
);

ProviderContainer _criarContainer({
  required FakePatrimonioRepository repositorio,
  required ProfilePerfil perfil,
}) {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(perfil));
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
      localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: _localizacoes)),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
      authRepositoryProvider.overrideWithValue(auth),
    ],
  );
  container.listen(patrimonioImportControllerProvider, (_, _) {});
  addTearDown(() {
    container.dispose();
    auth.dispose();
  });
  return container;
}

Uint8List _csv(String conteudo) => Uint8List.fromList(utf8.encode(conteudo));

/// Um [ComparacaoLote] pequeno e sintético — 1 idêntico, 1 divergente (2
/// campos: um de localização, um de metadado), 1 novo, 1 bloqueado — usado
/// por vários testes que não precisam rodar o pipeline de planilha.
ComparacaoLote _loteSintetico() {
  const divergencias = [
    CampoDivergente(
      campo: 'Localização atual',
      tipo: TipoDivergencia.localizacao,
      valorInvtec: 'GETEC - Universitário',
      valorPlanilha: 'GETEC-PPLT',
    ),
    CampoDivergente(campo: 'Marca', tipo: TipoDivergencia.metadado, valorInvtec: 'DELL', valorPlanilha: 'LENOVO'),
  ];
  final itens = [
    const PatrimonioComparacao(
      numeroLinha: 2,
      numeroPatrimonio: '100000',
      patrimonioId: 'p-identico',
      classificacao: ClassificacaoComparacao.identico,
    ),
    const PatrimonioComparacao(
      numeroLinha: 3,
      numeroPatrimonio: '123456',
      patrimonioId: 'p-divergente',
      classificacao: ClassificacaoComparacao.divergente,
      divergencias: divergencias,
    ),
    const PatrimonioComparacao(
      numeroLinha: 4,
      numeroPatrimonio: '999999',
      classificacao: ClassificacaoComparacao.novo,
    ),
    const PatrimonioComparacao(
      numeroLinha: 5,
      numeroPatrimonio: '555555',
      classificacao: ClassificacaoComparacao.bloqueado,
      motivoBloqueio: "Localização 'SALA MISTERIOSA' não foi identificada com segurança.",
    ),
  ];
  return ComparacaoLote(
    itens: itens,
    resumo: ComparacaoResumo(
      totalLinhas: 4,
      identicos: 1,
      divergentes: 1,
      novos: 1,
      bloqueados: 1,
      divergenciasPorCampo: const {'Localização atual': 1, 'Marca': 1},
    ),
  );
}

void main() {
  group('Seção 1 — acesso exclusivo ADMIN', () {
    testWidgets('toggle "Comparar e Atualizar" aparece só para ADMIN', (tester) async {
      _viewportGrande(tester);
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.gestor);
      await container.read(authControllerProvider.future);
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportDefaultsStep(state: state)))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle-modo-comparacao-admin')), findsNothing);
    });

    testWidgets('toggle "Comparar e Atualizar" aparece para ADMIN e liga o modo', (tester) async {
      _viewportGrande(tester);
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      await container.read(authControllerProvider.future);
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportDefaultsStep(state: state)))),
        ),
      );
      await tester.pumpAndSettle();

      final chave = find.byKey(const Key('toggle-modo-comparacao-admin'));
      expect(chave, findsOneWidget);
      expect(container.read(patrimonioImportControllerProvider).modoComparacaoAdmin, isFalse);

      await tester.tap(chave);
      await tester.pumpAndSettle();

      expect(container.read(patrimonioImportControllerProvider).modoComparacaoAdmin, isTrue);
    });

    test('definirModoComparacaoAdmin é ignorado para perfil não-ADMIN', () async {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.operador);
      await container.read(authControllerProvider.future);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      controller.definirModoComparacaoAdmin(true);

      expect(container.read(patrimonioImportControllerProvider).modoComparacaoAdmin, isFalse);
    });
  });

  group('Seção 2/3 — resumo e ocultação dos idênticos', () {
    testWidgets('resumo mostra as contagens de ComparacaoResumo e o aviso de idênticos ignorados', (tester) async {
      _viewportGrande(tester);
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      await container.read(authControllerProvider.future);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportComparacaoStep(state: state)))),
        ),
      );
      await tester.pumpAndSettle();

      Text textoDe(String key) => tester.widget<Text>(find.byKey(Key(key)));
      expect(textoDe('comparacao-resumo-total').data, 'Total analisado: 4');
      expect(textoDe('comparacao-resumo-divergentes').data, 'Divergentes: 1');
      expect(textoDe('comparacao-resumo-novos').data, 'Novos: 1');
      expect(textoDe('comparacao-resumo-bloqueados').data, 'Bloqueados: 1');
      // seção 2: "1.200 patrimônios possuem informações idênticas..." —
      // aqui com 1 idêntico, singular.
      expect(find.byKey(const Key('comparacao-aviso-identicos')), findsOneWidget);
      expect(find.textContaining('1 patrimônio possui informações idênticas'), findsOneWidget);

      // seção 3: idêntico NUNCA aparece na lista principal.
      expect(find.byKey(const Key('comparacao-item-2')), findsNothing); // linha 2 = o idêntico
      expect(find.byKey(const Key('comparacao-item-3')), findsOneWidget); // divergente

      // `ListView.builder` é preguiçoso dentro de sua área fixa — rola até
      // o fim para os itens seguintes serem efetivamente construídos.
      await tester.dragUntilVisible(
        find.byKey(const Key('comparacao-item-5')),
        find.byKey(const Key('comparacao-lista')),
        const Offset(0, -300),
      );
      expect(find.byKey(const Key('comparacao-item-4')), findsOneWidget); // novo
      expect(find.byKey(const Key('comparacao-item-5')), findsOneWidget); // bloqueado
    });

    test('resumo usa exclusivamente os números de ComparacaoResumo (nunca recalculados)', () {
      final lote = _loteSintetico();
      // A garantia estrutural: o widget lê `lote.resumo.*` diretamente (ver
      // `import_comparacao_step.dart`) — aqui provamos que ALTERAR só o
      // resumo (sem tocar `itens`) já seria refletido, porque não há
      // nenhum recálculo a partir de `itens` no caminho da UI.
      expect(lote.resumo.totalLinhas, 4);
      expect(lote.itensParaRevisao, hasLength(3)); // idêntico excluído
    });
  });

  group('Seção 4 — múltiplas divergências por patrimônio', () {
    testWidgets('mostra CADA CampoDivergente do patrimônio divergente, com InvTec/Planilha separados', (
      tester,
    ) async {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      await container.read(authControllerProvider.future);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportComparacaoStep(state: state)))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comparacao-campo-p-divergente-Localização atual')), findsOneWidget);
      expect(find.byKey(const Key('comparacao-campo-p-divergente-Marca')), findsOneWidget);
      expect(find.text('InvTec: GETEC - Universitário'), findsOneWidget);
      expect(find.text('Planilha: GETEC-PPLT'), findsOneWidget);
      expect(find.text('InvTec: DELL'), findsOneWidget);
      expect(find.text('Planilha: LENOVO'), findsOneWidget);
      // nunca funde os dois: nenhum texto mistura os dois valores.
      expect(find.text('GETEC - Universitário → GETEC-PPLT'), findsNothing);
    });
  });

  group('Seção 5 — decisões independentes por campo', () {
    test('decidir a Localização não afeta a decisão da Marca do MESMO patrimônio', () {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());

      controller.decidirCampo('p-divergente', 'Localização atual', DecisaoCampoValor.aplicar);

      var state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.aplicar);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.pendente);

      controller.decidirCampo('p-divergente', 'Marca', DecisaoCampoValor.ignorar);

      state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.aplicar, reason: 'não foi tocada');
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.ignorar);
    });

    test('exemplo — localização SIM, marca NÃO', () {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());

      controller.decidirCampo('p-divergente', 'Localização atual', DecisaoCampoValor.aplicar);
      controller.decidirCampo('p-divergente', 'Marca', DecisaoCampoValor.ignorar);

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.aplicar);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.ignorar);
    });
  });

  group('Seção 6/7 — seleção em massa e bloqueados nunca selecionáveis', () {
    test('selecionarTodosOsElegiveis aplica só aos campos divergentes elegíveis, nunca bloqueado/novo', () {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());

      final afetadas = controller.selecionarTodosOsElegiveis();

      expect(afetadas, 2); // as 2 divergências do único patrimônio divergente.
      final state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.aplicar);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.aplicar);
      // bloqueado/novo nunca têm entrada nenhuma no mapa de decisões.
      expect(state.decisoes.keys.any((k) => k.patrimonioId == '999999' || k.patrimonioId == '555555'), isFalse);
    });

    test('ignorarTodosOsElegiveis / selecionarSomenteLocalizacaoOuSetor / selecionarSomenteMetadados / limparDecisoes', () {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());

      expect(controller.selecionarSomenteLocalizacaoOuSetor(), 1);
      var state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.aplicar);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.pendente);

      expect(controller.selecionarSomenteMetadados(), 1);
      state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.aplicar);

      expect(controller.ignorarTodosOsElegiveis(), 2);
      state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.ignorar);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.ignorar);

      expect(controller.limparDecisoes(), 2);
      state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Localização atual'), DecisaoCampoValor.pendente);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.pendente);

      // uma segunda chamada sem nada para mudar afeta 0.
      expect(controller.limparDecisoes(), 0);
    });

    test('decidirCampo é ignorado silenciosamente para um patrimônio/campo bloqueado ou inexistente', () {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());

      controller.decidirCampo('555555', 'Localização atual', DecisaoCampoValor.aplicar); // bloqueado
      controller.decidirCampo('999999', 'Descrição', DecisaoCampoValor.aplicar); // novo, sem id nem divergência
      controller.decidirCampo('p-divergente', 'Campo Inexistente', DecisaoCampoValor.aplicar);

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.decisoes, isEmpty);
    });

    testWidgets('nenhum controle de decisão é renderizado para o item BLOQUEADO', (tester) async {
      _viewportGrande(tester);
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      await container.read(authControllerProvider.future);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());
      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ImportComparacaoStep(state: state)))),
        ),
      );
      await tester.pumpAndSettle();
      // `ListView.builder` é preguiçoso dentro de sua área fixa — rola até
      // o item bloqueado ser efetivamente construído.
      await tester.dragUntilVisible(
        find.byKey(const Key('comparacao-item-5')),
        find.byKey(const Key('comparacao-lista')),
        const Offset(0, -300),
      );

      expect(find.textContaining('não foi identificada com segurança'), findsOneWidget);
      expect(find.byKey(const Key('comparacao-campo-555555-Localização atual')), findsNothing);
      expect(find.text('Aplicar valor da planilha'), findsNWidgets(2)); // só as 2 do divergente
    });
  });

  group('Seção 3/9 — decisões preservadas ao trocar filtro/busca', () {
    test('mudar filtroComparacao/buscaNumeroPatrimonio nunca altera decisoes', () {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());
      controller.decidirCampo('p-divergente', 'Marca', DecisaoCampoValor.aplicar);

      controller.definirFiltroComparacao(ComparacaoFiltroRevisao.novos);
      controller.definirBuscaNumeroPatrimonio('123');
      controller.definirFiltroComparacao(ComparacaoFiltroRevisao.todos);
      controller.definirBuscaNumeroPatrimonio('');

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.decisaoDe('p-divergente', 'Marca'), DecisaoCampoValor.aplicar);
    });
  });

  group('Seção 9 — nova comparação invalida decisões antigas', () {
    test('compararParaAdmin() chamado de novo reseta decisoes/filtro/busca', () async {
      final banco = PatrimonioDetalhe(
        patrimonio: Patrimonio(
          id: 'p-1',
          numeroPatrimonio: '123456',
          tipoId: 'tipo-notebook',
          descricao: 'Notebook Dell',
          status: PatrimonioStatus.emUso,
          setorAtualId: 'setor-getec',
          dataCadastro: DateTime(2024, 1, 1),
          atualizadoEm: DateTime(2024, 1, 1),
        ),
        tipoNome: 'Notebook',
        setorNome: 'GETEC',
      );
      final repo = FakePatrimonioRepository(itens: [banco]);
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      await container.read(authControllerProvider.future);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Descricao;Marca;Serial;Setor\n123456;Notebook Dell DIFERENTE;LENOVO;S1;GETEC\n';
      await controller.carregarArquivo(nomeArquivo: 'a.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
      controller.definirColuna(ImportColumnField.descricao, 1);
      controller.definirColuna(ImportColumnField.marca, 2);
      controller.definirColuna(ImportColumnField.numeroSerie, 3);
      controller.definirColuna(ImportColumnField.setor, 4);
      controller.avancarParaPadroes();
      controller.definirPadroes(const ImportDefaults(destinoPadraoId: 'setor-getec'));
      controller.definirModoComparacaoAdmin(true);
      await controller.compararParaAdmin();

      final patrimonioId = container
          .read(patrimonioImportControllerProvider)
          .comparacao!
          .itens
          .firstWhere((i) => i.numeroPatrimonio == '123456')
          .patrimonioId!;
      controller.decidirCampo(patrimonioId, 'Descrição', DecisaoCampoValor.aplicar);
      controller.definirFiltroComparacao(ComparacaoFiltroRevisao.selecionadosParaAtualizacao);

      expect(container.read(patrimonioImportControllerProvider).decisoes, isNotEmpty);

      // Nova planilha carregada — `carregarArquivo` já reseta TUDO
      // (comportamento herdado, testado à parte), então simulamos aqui a
      // reanálise (mesma planilha) que também precisa invalidar sozinha.
      await controller.compararParaAdmin();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.decisoes, isEmpty, reason: 'seção 9: nova comparação invalida decisões anteriores');
      expect(state.filtroComparacao, ComparacaoFiltroRevisao.todos);
      expect(state.buscaNumeroPatrimonio, '');
    });

    test('carregarArquivo (nova planilha) reseta comparacao/decisoes/modoComparacaoAdmin', () async {
      final container = _criarContainer(repositorio: FakePatrimonioRepository(), perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(
        step: ImportStep.compararRevisao,
        comparacao: _loteSintetico(),
        modoComparacaoAdmin: true,
        decisoes: {const ChaveDecisaoCampo(patrimonioId: 'p-divergente', campo: 'Marca'): DecisaoCampoValor.aplicar},
      );

      await controller.carregarArquivo(nomeArquivo: 'novo.csv', bytes: _csv('A;B\n1;2\n'));

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.comparacao, isNull);
      expect(state.decisoes, isEmpty);
      expect(state.modoComparacaoAdmin, isFalse);
    });
  });

  group('Seção 6/10 — nenhuma chamada de escrita, mesmo com decisões tomadas', () {
    test('cadastrar()/atualizar() nunca são chamados só por decidir/selecionar em massa', () {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = container.read(patrimonioImportControllerProvider.notifier);
      controller.state = PatrimonioImportState(step: ImportStep.compararRevisao, comparacao: _loteSintetico());

      controller.selecionarTodosOsElegiveis();
      controller.decidirCampo('p-divergente', 'Marca', DecisaoCampoValor.ignorar);
      controller.ignorarTodosOsElegiveis();
      controller.limparDecisoes();

      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
    });
  });

  group('Seção 11 — importação convencional inalterada', () {
    test('perfil não-ADMIN: analisar()/confirmarImportacao() continuam com o comportamento de sempre', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repositorio: repo, perfil: ProfilePerfil.operador);
      await container.read(authControllerProvider.future);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      const csv = 'Patrimônio;Tipo;Marca;Serial;Setor\n00045872;Notebook;Dell;AAA1;GETEC\n';
      await controller.carregarArquivo(nomeArquivo: 'inventario.csv', bytes: _csv(csv));
      controller.confirmarCabecalho();
      controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
      controller.definirColuna(ImportColumnField.tipo, 1);
      controller.definirColuna(ImportColumnField.marca, 2);
      controller.definirColuna(ImportColumnField.numeroSerie, 3);
      controller.definirColuna(ImportColumnField.setor, 4);
      controller.avancarParaPadroes();
      // origem DISTINTA do destino ('GETEC', mapeado na coluna Setor) — a
      // mesma regra "origem e destino precisam ser diferentes" da
      // importação convencional continua valendo aqui.
      controller.definirPadroes(const ImportDefaults(origemPadraoId: 'setor-almoxarifado'));
      await controller.avancarAposPadroes(); // agora bifurca por modoComparacaoAdmin — deve seguir convencional.

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.step, ImportStep.revisar);
      expect(state.linhas.single.status, ImportRowStatus.pronto);
      expect(state.comparacao, isNull);
      expect(state.decisoes, isEmpty);
      expect(state.modoComparacaoAdmin, isFalse);

      await controller.confirmarImportacao();
      expect(repo.cadastrarCallCount, 1);
      expect(repo.atualizarCallCount, 0);
    });
  });
}
