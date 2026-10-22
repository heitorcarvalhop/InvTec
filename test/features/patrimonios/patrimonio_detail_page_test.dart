import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/tombamento_historico_item.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_historico_item.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_detail_page.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import '../auth/fake_permissions_repository.dart';
import '../movimentacoes/fake_movimentacao_repository.dart';
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
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
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
  List<MovimentacaoHistoricoItem> historico = const [],
  List<TombamentoHistoricoItem> historicoTombamentos = const [],
  Object? erroHistoricoTombamentos,
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
        permissionsRepositoryProvider.overrideWithValue(FakePermissionsRepository.paraPerfil(perfil)),
        patrimonioRepositoryProvider.overrideWithValue(
          FakePatrimonioRepository(
            itens: [detalhe],
            historicoTombamentosPorId: {detalhe.patrimonio.id: historicoTombamentos},
            erroHistoricoTombamentosPorId: erroHistoricoTombamentos,
          ),
        ),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(tipos: _tipos),
        ),
        setorRepositoryProvider.overrideWithValue(
          FakeSetorRepository(setores: _setores),
        ),
        movimentacaoRepositoryProvider.overrideWithValue(
          FakeMovimentacaoRepository(historico: historico),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: PatrimonioDetailPage(id: detalhe.patrimonio.id)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Monta a página de detalhe dentro de um `GoRouter` de verdade, para
/// testar o botão "Voltar" do cabeçalho — [comPilha] decide se a página é
/// aberta via `context.push` (stack válida, `context.canPop() == true`) ou
/// como `initialLocation` direto (sem stack, o caso de fallback via
/// `context.go`).
Future<void> _pumpDetailPageComRouter(
  WidgetTester tester, {
  required PatrimonioDetalhe detalhe,
  required bool comPilha,
  ProfilePerfil perfil = ProfilePerfil.admin,
  List<MovimentacaoHistoricoItem> historico = const [],
}) async {
  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(fakeAuth.dispose);

  final id = detalhe.patrimonio.id;
  final router = GoRouter(
    initialLocation: comPilha ? '/patrimonios' : '/patrimonios/$id',
    routes: [
      GoRoute(
        path: '/patrimonios',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('PAGINA_PATRIMONIOS'),
                TextButton(
                  onPressed: () => context.push('/patrimonios/$id'),
                  child: const Text('Abrir detalhe'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/patrimonios/:id',
        builder: (context, state) =>
            Scaffold(body: PatrimonioDetailPage(id: state.pathParameters['id']!)),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        permissionsRepositoryProvider.overrideWithValue(FakePermissionsRepository.paraPerfil(perfil)),
        patrimonioRepositoryProvider.overrideWithValue(
          FakePatrimonioRepository(itens: [detalhe]),
        ),
        tipoPatrimonioRepositoryProvider.overrideWithValue(
          FakeTipoPatrimonioRepository(tipos: _tipos),
        ),
        setorRepositoryProvider.overrideWithValue(
          FakeSetorRepository(setores: _setores),
        ),
        movimentacaoRepositoryProvider.overrideWithValue(
          FakeMovimentacaoRepository(historico: historico),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  if (comPilha) {
    await tester.tap(find.text('Abrir detalhe'));
    await tester.pumpAndSettle();
  }
}

PatrimonioDetalhe _detalhePadrao() => PatrimonioDetalhe(
  patrimonio: Patrimonio(
    id: '1',
    numeroPatrimonio: '00045872',
    tipoId: 'tipo-1',
    status: PatrimonioStatus.emUso,
    setorAtualId: 'setor-1',
    dataCadastro: DateTime.utc(2026, 1, 10),
    atualizadoEm: DateTime.utc(2026, 1, 10),
  ),
  tipoNome: 'Notebook',
  setorNome: 'GETEC',
);

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

    // Título combina "Patrimônio" + número; o campo
    // "Número patrimonial" mostra o número sozinho.
    expect(find.text('Patrimônio 00045872'), findsOneWidget);
    expect(find.text('00045872'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Dell'), findsOneWidget);
    expect(find.text('Latitude 5440'), findsOneWidget);
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.text('GETEC'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text('Em uso'), findsOneWidget);
    expect(find.text('Heitor Pereira'), findsOneWidget);
    expect(
      find.text('Nenhuma movimentação registrada para este patrimônio.'),
      findsOneWidget,
    );
    expect(
      find.text('Nenhum tombamento anterior registrado para este patrimônio.'),
      findsOneWidget,
    );
  });

  testWidgets('histórico de movimentações aparece como timeline, sem opção de editar', (
    tester,
  ) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '00045872',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        dataCadastro: DateTime.utc(2026, 1, 10),
        atualizadoEm: DateTime.utc(2026, 1, 10),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
    );

    await _pumpDetailPage(
      tester,
      detalhe: detalhe,
      historico: [
        MovimentacaoHistoricoItem(
          id: 'mov-1',
          tipo: MovimentacaoTipo.entrada,
          setorDestinoNome: 'Gerência de Tecnologia',
          localizacaoDestinoNome: 'GETEC - UNIVERSITÁRIO',
          responsavelDestino: 'João Silva',
          dataMovimentacao: DateTime.utc(2026, 1, 10, 14, 30),
        ),
      ],
    );

    expect(find.text('ENTRADA'), findsOneWidget);
    expect(find.text('— → Gerência de Tecnologia'), findsOneWidget);
    expect(find.text('Localização: GETEC - UNIVERSITÁRIO'), findsOneWidget);
    expect(find.text('Responsável: João Silva'), findsOneWidget);
    expect(find.textContaining('10/01/2026'), findsOneWidget);

    // Histórico é imutável: nenhum ícone de editar/excluir dentro dele.
    expect(
      find.descendant(
        of: find.byType(Card).last,
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets('timeline de histórico mostra a sigla do setor, não o nome completo', (
    tester,
  ) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '00045872',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        dataCadastro: DateTime.utc(2026, 1, 10),
        atualizadoEm: DateTime.utc(2026, 1, 10),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
    );

    await _pumpDetailPage(
      tester,
      detalhe: detalhe,
      historico: [
        MovimentacaoHistoricoItem(
          id: 'mov-1',
          tipo: MovimentacaoTipo.entrada,
          setorOrigemNome: 'Gerencia de Tecnologia',
          setorOrigemSigla: 'GETEC',
          setorDestinoNome: 'Gerência de Posturas',
          setorDestinoSigla: 'GEPOS',
          dataMovimentacao: DateTime.utc(2026, 1, 10, 14, 30),
        ),
      ],
    );

    expect(find.text('GETEC → GEPOS'), findsOneWidget);
    expect(find.text('Gerência de Posturas'), findsNothing);
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

  testWidgets('campo Gerência mostra a sigla, com o nome completo no tooltip', (
    tester,
  ) async {
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '00045872',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        dataCadastro: DateTime.utc(2026, 1, 10),
        atualizadoEm: DateTime.utc(2026, 1, 10),
      ),
      tipoNome: 'Notebook',
      setorNome: 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
      setorSigla: 'GEASI',
    );

    await _pumpDetailPage(tester, detalhe: detalhe);

    expect(find.text('GEASI'), findsOneWidget);
    expect(
      find.text('Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto'),
      findsNothing,
    );

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('GEASI'), matching: find.byType(Tooltip)).first,
    );
    expect(
      tooltip.message,
      'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
    );
  });

  testWidgets('a ficha mostra tudo que saiu da listagem (marca, modelo, série, localização, '
      'responsável, descrição completa e nome completo do setor)', (tester) async {
    const descricaoLonga =
        'Notebook corporativo com 32 GB de memória, SSD de 1 TB, docking station e garantia estendida até 2028';
    final detalhe = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '00045872',
        numeroSerie: 'ABC123',
        tipoId: 'tipo-1',
        marca: 'Dell',
        modelo: 'Latitude 5440',
        descricao: descricaoLonga,
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        responsavelAtual: 'João Silva',
        dataCadastro: DateTime.utc(2026, 1, 10),
        atualizadoEm: DateTime.utc(2026, 1, 10),
      ),
      tipoNome: 'Notebook',
      setorNome: 'Gerência de Tecnologia',
      setorSigla: 'GETEC',
      localizacaoNome: 'Sala 12 - Almoxarifado',
    );

    await _pumpDetailPage(tester, detalhe: detalhe);

    expect(find.text('Dell'), findsOneWidget);
    expect(find.text('Latitude 5440'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('Sala 12 - Almoxarifado'), findsOneWidget);
    expect(find.text('João Silva'), findsOneWidget);
    expect(find.text(descricaoLonga), findsOneWidget);
    expect(find.text('GETEC'), findsOneWidget);
    expect(find.byTooltip('Gerência de Tecnologia'), findsOneWidget, reason: 'nome completo do setor por tooltip');
  });

  group('histórico de tombamentos', () {
    PatrimonioDetalhe detalhe() => PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: '1',
        numeroPatrimonio: '654321',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.emUso,
        setorAtualId: 'setor-1',
        dataCadastro: DateTime.utc(2026, 1, 10),
        atualizadoEm: DateTime.utc(2026, 1, 10),
      ),
      tipoNome: 'Notebook',
      setorNome: 'GETEC',
    );

    testWidgets('sem histórico mostra mensagem adequada', (tester) async {
      await _pumpDetailPage(tester, detalhe: detalhe());

      expect(find.text('Histórico de tombamentos'), findsOneWidget);
      expect(
        find.text('Nenhum tombamento anterior registrado para este patrimônio.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'apresentação COMPACTA: anterior → atual, origem resumida + data curta, '
      'sem o texto de evidência/observação visível por padrão (pedido de simplificação)',
      (tester) async {
        await _pumpDetailPage(
          tester,
          detalhe: detalhe(),
          historicoTombamentos: [
            TombamentoHistoricoItem(
              sequencia: 2,
              numeroAnterior: '0123456',
              numeroNovo: '654321',
              origem: 'ALTERACAO_DIRETA',
              registradoEm: DateTime.utc(2026, 2, 1, 10, 0),
            ),
            TombamentoHistoricoItem(
              sequencia: 1,
              numeroAnterior: '0777386',
              numeroNovo: '0123456',
              origem: 'IMPORTACAO_PLANILHA',
              registradoEm: DateTime.utc(2026, 10, 20, 9, 0),
              observacao:
                  'Patrimônio já está no tombamento atual correto; texto longo de '
                  'evidência documental da Fase 2 que NÃO deve poluir a lista.',
            ),
          ],
        );

        // Zeros à esquerda preservados EXATAMENTE como armazenados — nunca
        // normalizados para exibição.
        expect(find.text('0123456 → 654321'), findsOneWidget);
        expect(find.text('0777386 → 0123456'), findsOneWidget);

        // Origem resumida (vocabulário do pedido) + data CURTA (sem hora),
        // combinadas numa única linha compacta.
        expect(find.textContaining('Alteração direta • 01/02/2026'), findsOneWidget);
        expect(find.textContaining('Planilha oficial • 20/10/2026'), findsOneWidget);

        // Nada de texto técnico/verboso nem rótulos "Registrado em"/"Troca
        // efetiva em" soltos na lista — só dentro de "Ver detalhes".
        expect(find.textContaining('Registrado em:'), findsNothing);
        expect(find.textContaining('Troca efetiva em:'), findsNothing);
        expect(
          find.textContaining('NÃO deve poluir a lista'),
          findsNothing,
          reason: 'observação/evidência não some do Supabase, só não aparece inline por padrão',
        );
        expect(find.text('Ver detalhes'), findsNWidgets(2));
      },
    );

    testWidgets(
      '"Ver detalhes" abre diálogo com origem completa, "Registrado em" '
      '(nunca confundido com a data da troca) e a observação original intacta',
      (tester) async {
        await _pumpDetailPage(
          tester,
          detalhe: detalhe(),
          historicoTombamentos: [
            TombamentoHistoricoItem(
              sequencia: 1,
              numeroAnterior: '111111',
              numeroNovo: '654321',
              origem: 'MANUAL',
              // Horário LOCAL (não `.utc`) de propósito: a exibição usa
              // `.toLocal()`, então um valor UTC faria a asserção de hora
              // abaixo variar com o fuso da máquina que roda o teste.
              registradoEm: DateTime(2026, 3, 1, 8, 0),
              dataEfetivaAlteracao: DateTime(2026, 2, 28, 17, 0),
              observacao: 'Observação original completa, nunca alterada.',
            ),
          ],
        );

        await tester.ensureVisible(find.text('Ver detalhes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ver detalhes'));
        await tester.pumpAndSettle();

        expect(find.text('Detalhes do histórico de tombamento'), findsOneWidget);
        expect(find.text('Alteração manual'), findsOneWidget);
        // "Registrado em" (quando a gravação aconteceu) e "Troca efetiva
        // em" (quando a troca de fato ocorreu, só para MANUAL) aparecem
        // como campos SEPARADOS e claramente rotulados — nunca um
        // confundido com o outro.
        expect(find.textContaining('Registrado em'), findsOneWidget);
        expect(find.textContaining('01/03/2026 às 08:00'), findsOneWidget);
        expect(find.textContaining('Troca efetiva em'), findsOneWidget);
        expect(find.textContaining('28/02/2026 às 17:00'), findsOneWidget);
        expect(find.text('Observação original completa, nunca alterada.'), findsOneWidget);

        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(find.text('Detalhes do histórico de tombamento'), findsNothing);
      },
    );

    testWidgets('respeita a ordem já devolvida pelo repositório (sequência DESC)', (tester) async {
      await _pumpDetailPage(
        tester,
        detalhe: detalhe(),
        historicoTombamentos: [
          TombamentoHistoricoItem(
            sequencia: 2,
            numeroAnterior: '222222',
            numeroNovo: '654321',
            origem: 'MANUAL',
            registradoEm: DateTime.utc(2026, 2, 1),
          ),
          TombamentoHistoricoItem(
            sequencia: 1,
            numeroAnterior: '111111',
            numeroNovo: '222222',
            origem: 'MANUAL',
            registradoEm: DateTime.utc(2026, 1, 1),
          ),
        ],
      );

      final posicaoMaisRecente = tester.getTopLeft(find.text('222222 → 654321')).dy;
      final posicaoMaisAntiga = tester.getTopLeft(find.text('111111 → 222222')).dy;
      expect(posicaoMaisRecente, lessThan(posicaoMaisAntiga));
    });

    testWidgets('falha ao carregar mostra erro com ação de tentar novamente', (tester) async {
      await _pumpDetailPage(
        tester,
        detalhe: detalhe(),
        erroHistoricoTombamentos: Exception('falha de leitura simulada'),
      );

      expect(
        find.text('Não foi possível carregar o histórico de tombamentos. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('busca por tombamento anterior continua funcionando (regressão)', (tester) async {
      // Esta seção nova (detalhe) nunca deve interferir com
      // buscarPorTombamentoAnterior (pesquisa) — campos/métodos
      // independentes do mesmo FakePatrimonioRepository.
      final repo = FakePatrimonioRepository(
        itens: [detalhe()],
        historicoAnterior: {
          '999999': [('1', 'MANUAL')],
        },
      );
      final resultado = await repo.buscarPorTombamentoAnterior('999999');
      expect(resultado, hasLength(1));
      expect(resultado.single.patrimonio.patrimonio.id, '1');
    });
  });

  group('navegação de voltar', () {
    testWidgets('com pilha de navegação válida, Voltar retorna para a listagem', (tester) async {
      await _pumpDetailPageComRouter(
        tester,
        detalhe: _detalhePadrao(),
        comPilha: true,
      );

      expect(find.text('Patrimônio 00045872'), findsOneWidget);

      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();

      expect(find.text('PAGINA_PATRIMONIOS'), findsOneWidget);
      expect(find.byType(PatrimonioDetailPage), findsNothing);
    });

    testWidgets(
      'sem pilha de navegação válida (rota filha aberta direto), Voltar usa o fallback para Patrimônios',
      (tester) async {
        await _pumpDetailPageComRouter(
          tester,
          detalhe: _detalhePadrao(),
          comPilha: false,
        );

        expect(find.text('Patrimônio 00045872'), findsOneWidget);

        await tester.tap(find.text('Voltar'));
        await tester.pumpAndSettle();

        expect(find.text('PAGINA_PATRIMONIOS'), findsOneWidget);
        expect(find.byType(PatrimonioDetailPage), findsNothing);
      },
    );
  });

  testWidgets(
    'dialog de edição não navega para nenhuma rota: Cancelar apenas fecha o diálogo (regressão)',
    (tester) async {
      await _pumpDetailPage(tester, detalhe: _detalhePadrao());

      await tester.tap(find.widgetWithText(FilledButton, 'Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar patrimônio'), findsOneWidget);

      // Sem GoRouter nesta árvore (ver `_pumpDetailPage`): se o diálogo
      // tentasse `context.go`/`context.push`, este teste já falharia aqui.
      final botaoCancelar = find.widgetWithText(TextButton, 'Cancelar');
      await tester.ensureVisible(botaoCancelar);
      await tester.pumpAndSettle();
      await tester.tap(botaoCancelar);
      await tester.pumpAndSettle();

      expect(find.text('Editar patrimônio'), findsNothing);
      expect(find.text('Patrimônio 00045872'), findsOneWidget);
    },
  );
}
