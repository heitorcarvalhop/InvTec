import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_historico_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_repository.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacoes_resultado.dart';
import 'package:invtec/features/movimentacoes/presentation/movimentacoes_page.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacoes_desktop_table.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../auth/fake_auth_repository.dart';
import '../setores/fake_setor_repository.dart';
import 'fake_movimentacao_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

/// Nunca resolve `listar()` — usado para capturar o estado de loading de
/// forma determinística (o [FakeMovimentacaoRepository] normal resolve
/// rápido demais, sem nenhum atraso real, para isso).
class _RepositorioTravado implements MovimentacaoRepository {
  @override
  Future<MovimentacoesResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    MovimentacaoTipo? tipo,
    String? setorId,
    DateTime? periodoDe,
    DateTime? periodoAte,
  }) {
    return Completer<MovimentacoesResultado>().future;
  }

  @override
  Future<List<Movimentacao>> listarPorPatrimonio(String patrimonioId, {int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<List<MovimentacaoHistoricoItem>> listarHistoricoPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<Movimentacao> registrarMovimentacao({
    required String patrimonioId,
    required MovimentacaoTipo tipo,
    String? destinoId,
    String? localizacaoDestinoId,
    bool limparLocalizacao = false,
    String? responsavelDestino,
    String? motivo,
    String? observacao,
    String? numeroDocumento,
    String? numeroChamado,
    DateTime? dataMovimentacao,
  }) {
    throw UnimplementedError();
  }
}

MovimentacaoListagemItem _item(
  String id, {
  MovimentacaoTipo tipo = MovimentacaoTipo.transferencia,
  String? patrimonioNumero,
  String? patrimonioTipoNome,
  String? setorOrigemNome,
  String? setorDestinoNome,
  String? localizacaoOrigemNome,
  String? localizacaoDestinoNome,
  String? responsavelOrigem,
  String? responsavelDestino,
  String? autorNome,
  String? motivo,
  String? observacao,
  String? numeroDocumento,
  String? numeroChamado,
  DateTime? dataMovimentacao,
}) {
  return MovimentacaoListagemItem(
    id: id,
    tipo: tipo,
    patrimonioId: 'patrimonio-$id',
    patrimonioNumero: patrimonioNumero,
    patrimonioTipoNome: patrimonioTipoNome,
    setorOrigemNome: setorOrigemNome,
    setorDestinoNome: setorDestinoNome,
    localizacaoOrigemNome: localizacaoOrigemNome,
    localizacaoDestinoNome: localizacaoDestinoNome,
    responsavelOrigem: responsavelOrigem,
    responsavelDestino: responsavelDestino,
    autorNome: autorNome,
    motivo: motivo,
    observacao: observacao,
    numeroDocumento: numeroDocumento,
    numeroChamado: numeroChamado,
    dataMovimentacao: dataMovimentacao ?? DateTime(2026, 1, 10, 14, 30),
  );
}

Future<void> _pumpMovimentacoesPage(
  WidgetTester tester, {
  required FakeMovimentacaoRepository movimentacaoRepo,
  List<Setor>? setores,
  ThemeData? theme,
  ProfilePerfil perfil = ProfilePerfil.admin,
}) async {
  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile(perfil));
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        movimentacaoRepositoryProvider.overrideWithValue(movimentacaoRepo),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
      ],
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(body: MovimentacoesPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PROMPT 10.1 — listagem geral de movimentações', () {
    testWidgets('cabeçalho da tela', (tester) async {
      await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository());

      expect(find.text('Movimentações'), findsOneWidget);
      expect(find.text('Consulte e acompanhe o histórico de movimentações patrimoniais.'), findsOneWidget);
    });
  });

  group('PROMPT 10.2 — botão Nova movimentação (controle de permissão)', () {
    testWidgets('aparece para ADMIN/GESTOR/OPERADOR', (tester) async {
      for (final perfil in [ProfilePerfil.admin, ProfilePerfil.gestor, ProfilePerfil.operador]) {
        await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository(), perfil: perfil);
        expect(find.text('Nova movimentação'), findsOneWidget, reason: 'perfil: $perfil');
      }
    });

    testWidgets('some para CONSULTA — nunca recebe ação de escrita', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        perfil: ProfilePerfil.consulta,
      );
      expect(find.text('Nova movimentação'), findsNothing);
    });

    testWidgets('clicar em Nova movimentação abre o wizard no passo Patrimônio', (tester) async {
      await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository());

      await tester.tap(find.text('Nova movimentação'));
      await tester.pumpAndSettle();

      expect(find.text('Passo 1 de 4 · Patrimônio'), findsOneWidget);
      expect(find.text('Selecione o patrimônio'), findsOneWidget);
    });
  });

  group('PROMPT 11.1 — botão Importar documento SEI (controle de permissão)', () {
    testWidgets('aparece para ADMIN/GESTOR/OPERADOR', (tester) async {
      for (final perfil in [ProfilePerfil.admin, ProfilePerfil.gestor, ProfilePerfil.operador]) {
        await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository(), perfil: perfil);
        expect(find.text('Importar documento SEI'), findsOneWidget, reason: 'perfil: $perfil');
      }
    });

    testWidgets('some para CONSULTA — nesta versão nenhum perfil registra movimentação pelo importador', (
      tester,
    ) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        perfil: ProfilePerfil.consulta,
      );
      expect(find.text('Importar documento SEI'), findsNothing);
    });

    testWidgets('clicar em Importar documento SEI abre o assistente no passo de seleção de arquivo', (tester) async {
      await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository());

      await tester.tap(find.text('Importar documento SEI'));
      await tester.pumpAndSettle();

      expect(find.text('Selecionar PDF'), findsOneWidget);
      expect(
        find.textContaining('nenhuma movimentação é registrada aqui'),
        findsOneWidget,
        reason: 'seção 1 do prompt: o diálogo precisa deixar claro que esta etapa é só leitura',
      );
      // Nunca "Executar movimentações" (seção 1) — nem em nenhum outro
      // texto do diálogo enquanto ainda não há resultado de análise.
      expect(find.text('Executar movimentações'), findsNothing);
    });
  });

  group('PROMPT 10.1 — listagem geral de movimentações', () {

    testWidgets('listagem mostra as movimentações retornadas', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(
          itens: [
            _item('1', patrimonioNumero: '00045872', tipo: MovimentacaoTipo.entrada),
            _item('2', patrimonioNumero: '00099999', tipo: MovimentacaoTipo.baixa),
          ],
        ),
      );

      expect(find.text('00045872'), findsOneWidget);
      expect(find.text('00099999'), findsOneWidget);
      expect(find.text('Entrada'), findsOneWidget);
      expect(find.text('Baixa'), findsOneWidget);
    });

    testWidgets('estado vazio (sem movimentações cadastradas)', (tester) async {
      await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository());

      expect(find.text('Nenhuma movimentação registrada ainda.'), findsOneWidget);
    });

    testWidgets('busca sem resultado mostra mensagem com o termo pesquisado', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
      );

      await tester.enterText(find.byType(TextField).first, 'inexistente');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma movimentação encontrada para "inexistente".'), findsOneWidget);
    });

    testWidgets('busca filtra a listagem', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(
          itens: [_item('1', patrimonioNumero: '100'), _item('2', patrimonioNumero: '200')],
        ),
      );

      await tester.enterText(find.byType(TextField).first, '200');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // `find.text` também casa com o próprio campo de busca (que agora
      // contém "200") — escopado à tabela para não colidir com ele.
      expect(
        find.descendant(of: find.byType(MovimentacoesDesktopTable), matching: find.text('200')),
        findsOneWidget,
      );
      expect(find.text('100'), findsNothing);
    });

    testWidgets('filtros de Tipo e Setor aparecem na toolbar', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        setores: [Setor(id: 'setor-1', nome: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1))],
      );

      expect(find.widgetWithText(DropdownButtonFormField<MovimentacaoTipo?>, 'Tipo'), findsOneWidget);
      expect(find.widgetWithText(DropdownButtonFormField<String?>, 'Setor'), findsOneWidget);
      expect(find.text('Período'), findsOneWidget);
    });

    testWidgets('filtro por Tipo restringe a listagem', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(
          itens: [
            _item('1', patrimonioNumero: '100', tipo: MovimentacaoTipo.entrada),
            _item('2', patrimonioNumero: '200', tipo: MovimentacaoTipo.baixa),
          ],
        ),
      );

      final campoTipo = find.widgetWithText(DropdownButtonFormField<MovimentacaoTipo?>, 'Tipo');
      await tester.ensureVisible(campoTipo);
      await tester.pumpAndSettle();
      await tester.tap(campoTipo);
      await tester.pumpAndSettle();
      final opcaoBaixa = find.text('Baixa').last;
      await tester.ensureVisible(opcaoBaixa);
      await tester.pumpAndSettle();
      await tester.tap(opcaoBaixa);
      await tester.pumpAndSettle();

      expect(find.text('200'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('paginação: resumo e itens por página aparecem com mais de uma página', (tester) async {
      final itens = List.generate(
        30,
        (i) => _item('$i', patrimonioNumero: 'P$i', dataMovimentacao: DateTime(2026, 1, 1).subtract(Duration(days: i))),
      );
      await _pumpMovimentacoesPage(tester, movimentacaoRepo: FakeMovimentacaoRepository(itens: itens));

      expect(find.textContaining('Mostrando 1–25 de 30'), findsOneWidget);

      final botaoPagina2 = find.byKey(const ValueKey('pagination-page-2'));
      await tester.ensureVisible(botaoPagina2);
      await tester.pumpAndSettle();
      await tester.tap(botaoPagina2);
      await tester.pumpAndSettle();

      expect(find.text('P29'), findsOneWidget);
    });

    testWidgets('estado de carregamento mostra indicador de progresso', (tester) async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'fake-user-id',
        profileResolver: (_) => _profile(ProfilePerfil.admin),
      );
      addTearDown(fakeAuth.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            movimentacaoRepositoryProvider.overrideWithValue(_RepositorioTravado()),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
          ],
          child: const MaterialApp(home: Scaffold(body: MovimentacoesPage())),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('estado de erro mostra mensagem e ação de tentar novamente', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(erro: AppException('Falha ao listar movimentações')),
      );

      expect(find.text('Não foi possível acessar as movimentações. Tente novamente.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Tentar novamente'), findsOneWidget);
    });

    testWidgets('visualizar abre o detalhe somente leitura com os campos existentes', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(
          itens: [
            _item(
              '1',
              patrimonioNumero: '00045872',
              patrimonioTipoNome: 'Notebook',
              tipo: MovimentacaoTipo.entrada,
              setorDestinoNome: 'Gerência de Tecnologia',
              localizacaoDestinoNome: 'GETEC - UNIVERSITÁRIO',
              responsavelDestino: 'João Silva',
              autorNome: 'Heitor Pereira',
              motivo: 'Cadastro inicial',
            ),
          ],
        ),
      );

      final botaoVisualizar = find.byIcon(Icons.visibility_outlined);
      await tester.ensureVisible(botaoVisualizar);
      await tester.pumpAndSettle();
      await tester.tap(botaoVisualizar);
      await tester.pumpAndSettle();

      final dialog = find.byType(Dialog);
      Finder emDialog(String texto) => find.descendant(of: dialog, matching: find.text(texto));

      expect(emDialog('00045872'), findsOneWidget);
      expect(emDialog('Notebook'), findsOneWidget);
      expect(emDialog('Gerência de Tecnologia'), findsOneWidget);
      expect(emDialog('GETEC - UNIVERSITÁRIO'), findsOneWidget);
      expect(emDialog('João Silva'), findsOneWidget);
      expect(emDialog('Heitor Pereira'), findsOneWidget);
      expect(emDialog('Cadastro inicial'), findsOneWidget);
      // Sem número de documento/chamado neste item: o rótulo não aparece.
      expect(emDialog('Documento'), findsNothing);
      expect(emDialog('Chamado'), findsNothing);
      // Somente leitura: sem botão de editar dentro do detalhe.
      expect(find.descendant(of: dialog, matching: find.byIcon(Icons.edit_outlined)), findsNothing);
    });

    testWidgets('detalhe mostra documento e chamado quando existem', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(
          itens: [_item('1', patrimonioNumero: '100', numeroDocumento: 'DOC-1', numeroChamado: 'CHAM-2')],
        ),
      );

      final botaoVisualizar = find.byIcon(Icons.visibility_outlined);
      await tester.ensureVisible(botaoVisualizar);
      await tester.pumpAndSettle();
      await tester.tap(botaoVisualizar);
      await tester.pumpAndSettle();

      expect(find.text('Documento'), findsOneWidget);
      expect(find.text('DOC-1'), findsOneWidget);
      expect(find.text('Chamado'), findsOneWidget);
      expect(find.text('CHAM-2'), findsOneWidget);
    });

    testWidgets('PROMPT 10.1.1 — detalhe mostra observação quando existe', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(
          itens: [_item('1', patrimonioNumero: '100', observacao: 'Equipamento com risco na tela')],
        ),
      );

      final botaoVisualizar = find.byIcon(Icons.visibility_outlined);
      await tester.ensureVisible(botaoVisualizar);
      await tester.pumpAndSettle();
      await tester.tap(botaoVisualizar);
      await tester.pumpAndSettle();

      expect(find.text('Observação'), findsOneWidget);
      expect(find.text('Equipamento com risco na tela'), findsOneWidget);
    });

    testWidgets(
      'PROMPT 10.1.1 — detalhe mostra "Não disponível" para autor oculto pela RLS (nunca "—")',
      (tester) async {
        await _pumpMovimentacoesPage(
          tester,
          // autorNome null simula OPERADOR/CONSULTA vendo a movimentação de
          // outro usuário: profiles_select oculta o nome, mas realizado_por
          // nunca é nulo no banco — não é "sem dado".
          movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
        );

        final botaoVisualizar = find.byIcon(Icons.visibility_outlined);
        await tester.ensureVisible(botaoVisualizar);
        await tester.pumpAndSettle();
        await tester.tap(botaoVisualizar);
        await tester.pumpAndSettle();

        final dialog = find.byType(Dialog);
        expect(find.descendant(of: dialog, matching: find.text('Não disponível')), findsOneWidget);
      },
    );

    testWidgets(
      'PROMPT 10.1.1 — filtro Setor inclui setores inativos (histórico pode referenciar setor desativado)',
      (tester) async {
        await _pumpMovimentacoesPage(
          tester,
          movimentacaoRepo: FakeMovimentacaoRepository(),
          setores: [
            Setor(id: 'setor-1', nome: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
            Setor(id: 'setor-2', nome: 'Almoxarifado Antigo', ativo: false, criadoEm: DateTime(2020, 1, 1)),
          ],
        );

        final campoSetor = find.widgetWithText(DropdownButtonFormField<String?>, 'Setor');
        await tester.ensureVisible(campoSetor);
        await tester.pumpAndSettle();
        await tester.tap(campoSetor);
        await tester.pumpAndSettle();

        expect(find.text('GETEC'), findsWidgets);
        expect(find.text('Almoxarifado Antigo (inativo)'), findsOneWidget);
      },
    );

    testWidgets('renderiza sem exceções no tema claro', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
        theme: AppTheme.light,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Movimentações'), findsOneWidget);
    });

    testWidgets('renderiza sem exceções no tema escuro', (tester) async {
      await _pumpMovimentacoesPage(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(itens: [_item('1', patrimonioNumero: '100')]),
        theme: AppTheme.dark,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Movimentações'), findsOneWidget);
    });
  });
}
