import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/config/platform_info.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/core/theme/app_theme.dart';
import 'package:invtec/features/administracao/data/usuario_admin_repository_supabase.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/dashboard/domain/categoria_contagem.dart';
import 'package:invtec/features/dashboard/domain/dashboard_distribuicoes.dart';
import 'package:invtec/features/dashboard/domain/dashboard_repository.dart';
import 'package:invtec/features/dashboard/domain/movimentacao_resumo.dart';
import 'package:invtec/features/dashboard/presentation/dashboard_page.dart';
import 'package:invtec/features/dashboard/presentation/widgets/categoria_barras_card.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/notificacoes/domain/app_notification.dart';
import 'package:invtec/core/domain/ordenacao_direcao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_cadastro_lote.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_ordenacao.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_search_field.dart';
import 'package:invtec/features/patrimonios/domain/patrimonios_resultado.dart';
import 'package:invtec/features/patrimonios/domain/tombamento_historico_item.dart';
import 'package:invtec/features/patrimonios/importacao/domain/comparacao_execucao.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_execucao.dart';
import 'package:go_router/go_router.dart';

import '../administracao/fake_usuario_admin_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../auth/fake_permissions_repository.dart';
import '../notificacoes/fake_app_notification_repository.dart';
import '../patrimonios/fake_patrimonio_repository.dart';
import 'fake_dashboard_repository.dart';

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
);

/// Nunca resolve nenhuma contagem — usado para capturar o estado de
/// loading de forma determinística (o [FakeDashboardRepository] normal
/// resolve rápido demais, sem atraso real, para isso).
class _RepositorioTravado implements DashboardRepository {
  @override
  Future<int> contarPatrimonios() => Completer<int>().future;
  @override
  Future<int> contarSetoresAtivos() => Completer<int>().future;
  @override
  Future<int> contarLocalizacoesAtivas() => Completer<int>().future;
  @override
  Future<int> contarTiposAtivos() => Completer<int>().future;
  @override
  Future<int> contarMovimentacoesDesde(DateTime desde) =>
      Completer<int>().future;
  @override
  Future<DashboardDistribuicoes> carregarDistribuicoes() =>
      Completer<DashboardDistribuicoes>().future;
  @override
  Future<List<MovimentacaoResumo>> listarMovimentacoesRecentes({
    int limit = 8,
  }) => Completer<List<MovimentacaoResumo>>().future;
}

/// Só implementa [buscarPorPrefixoNumeroPatrimonio] de verdade (o único
/// método que o diálogo "Consultar patrimônio" chama) — usado para capturar
/// o estado de loading de forma determinística, já que [FakePatrimonioRepository]
/// normal resolve rápido demais, sem atraso real, para isso.
class _PatrimonioRepositorioTravado implements PatrimonioRepository {
  _PatrimonioRepositorioTravado(this._gate);
  final Completer<List<PatrimonioDetalhe>> _gate;

  @override
  Future<List<PatrimonioDetalhe>> buscarPorPrefixoNumeroPatrimonio(
    String prefixo, {
    int limit = 6,
  }) => _gate.future;

  @override
  Future<Patrimonio?> buscarPorId(String id) => throw UnimplementedError();
  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) =>
      throw UnimplementedError();
  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio) =>
      throw UnimplementedError();
  @override
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(
    String codigo,
  ) => throw UnimplementedError();
  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
    PatrimonioOrdenacaoCampo? ordenarPor,
    OrdenacaoDirecao ordenacaoDirecao = OrdenacaoDirecao.asc,
  }) => throw UnimplementedError();
  @override
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  }) => throw UnimplementedError();
  @override
  Future<ResultadoCadastroLote> cadastrarLote({
    required String tipoId,
    required String destinoId,
    required String operacaoId,
    required String loteId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
    String? origemArquivo,
    int? origemLinha,
  }) => throw UnimplementedError();
  @override
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) => throw UnimplementedError();
  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(
    List<String> numeros,
  ) => throw UnimplementedError();
  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      throw UnimplementedError();
  @override
  Future<ResultadoAplicacaoDecisao> aplicarDecisaoComparacao(
    DecisaoItemParaExecutar decisao,
  ) => throw UnimplementedError();
  @override
  Future<ResultadoAplicacaoDecisao?> buscarExecucaoComparacaoPorOperacaoId(
    String operacaoId,
  ) => throw UnimplementedError();
  @override
  Future<ResultadoRetificacaoUnidade> retificarUnidadePatrimonio(
    ItemRetificacaoParaExecutar item,
  ) => throw UnimplementedError();
  @override
  Future<List<PatrimonioEncontradoPorAnterior>> buscarPorTombamentoAnterior(
    String termo,
  ) => throw UnimplementedError();
  @override
  Future<List<TombamentoHistoricoItem>> buscarHistoricoTombamentosPorId(
    String patrimonioId,
  ) => throw UnimplementedError();
}

/// Delega tudo para [FakePatrimonioRepository], exceto
/// [buscarPorPrefixoNumeroPatrimonio]: a PRIMEIRA chamada lança (simula uma
/// falha de rede), as demais funcionam normalmente — usado para testar o
/// retry do diálogo "Consultar patrimônio".
class _RepositorioComFalhaNaPrimeiraPrefixo implements PatrimonioRepository {
  _RepositorioComFalhaNaPrimeiraPrefixo(PatrimonioDetalhe item)
    : _delegado = FakePatrimonioRepository(itens: [item]);
  final FakePatrimonioRepository _delegado;
  bool _primeiraChamada = true;

  @override
  Future<List<PatrimonioDetalhe>> buscarPorPrefixoNumeroPatrimonio(
    String prefixo, {
    int limit = 6,
  }) async {
    if (_primeiraChamada) {
      _primeiraChamada = false;
      throw const AppException('Falha simulada de rede.');
    }
    return _delegado.buscarPorPrefixoNumeroPatrimonio(prefixo, limit: limit);
  }

  @override
  Future<Patrimonio?> buscarPorId(String id) => _delegado.buscarPorId(id);
  @override
  Future<PatrimonioDetalhe?> buscarDetalhePorId(String id) =>
      _delegado.buscarDetalhePorId(id);
  @override
  Future<Patrimonio?> buscarPorNumeroPatrimonio(String numeroPatrimonio) =>
      _delegado.buscarPorNumeroPatrimonio(numeroPatrimonio);
  @override
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(
    String codigo,
  ) => _delegado.buscarPorTombamentoAtualExato(codigo);
  @override
  Future<PatrimoniosResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    PatrimonioSearchField campoBusca = PatrimonioSearchField.tudo,
    String? tipoId,
    PatrimonioStatus? status,
    String? setorId,
    String? localizacaoId,
    bool semLocalizacao = false,
    String? marca,
    String? modelo,
    String? responsavel,
    DateTime? dataCadastroDe,
    DateTime? dataCadastroAte,
    DateTime? dataAquisicaoDe,
    DateTime? dataAquisicaoAte,
    PatrimonioOrdenacaoCampo? ordenarPor,
    OrdenacaoDirecao ordenacaoDirecao = OrdenacaoDirecao.asc,
  }) => _delegado.listar(
    limit: limit,
    offset: offset,
    busca: busca,
    campoBusca: campoBusca,
    tipoId: tipoId,
    status: status,
    setorId: setorId,
    localizacaoId: localizacaoId,
    semLocalizacao: semLocalizacao,
    marca: marca,
    modelo: modelo,
    responsavel: responsavel,
    dataCadastroDe: dataCadastroDe,
    dataCadastroAte: dataCadastroAte,
    dataAquisicaoDe: dataAquisicaoDe,
    dataAquisicaoAte: dataAquisicaoAte,
    ordenarPor: ordenarPor,
    ordenacaoDirecao: ordenacaoDirecao,
  );
  @override
  Future<Patrimonio> cadastrar({
    required String tipoId,
    required String destinoId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
  }) => throw UnimplementedError();
  @override
  Future<ResultadoCadastroLote> cadastrarLote({
    required String tipoId,
    required String destinoId,
    required String operacaoId,
    required String loteId,
    String? numeroPatrimonio,
    String? numeroSerie,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
    String? origemId,
    String? localizacaoOrigemId,
    String? localizacaoDestinoId,
    String? responsavelOrigem,
    String? responsavelDestino,
    String? motivo,
    String? observacaoMovimentacao,
    DateTime? dataMovimentacao,
    String? origemArquivo,
    int? origemLinha,
  }) => throw UnimplementedError();
  @override
  Future<Patrimonio> atualizar({
    required String id,
    String? numeroPatrimonio,
    String? numeroSerie,
    required String tipoId,
    String? marca,
    String? modelo,
    String? descricao,
    String? observacao,
    DateTime? dataAquisicao,
  }) => throw UnimplementedError();
  @override
  Future<List<PatrimonioDetalhe>> buscarPorNumerosPatrimonio(
    List<String> numeros,
  ) => _delegado.buscarPorNumerosPatrimonio(numeros);
  @override
  Future<Set<String>> buscarNumerosSerieExistentes(List<String> numerosSerie) =>
      _delegado.buscarNumerosSerieExistentes(numerosSerie);
  @override
  Future<ResultadoAplicacaoDecisao> aplicarDecisaoComparacao(
    DecisaoItemParaExecutar decisao,
  ) => _delegado.aplicarDecisaoComparacao(decisao);
  @override
  Future<ResultadoAplicacaoDecisao?> buscarExecucaoComparacaoPorOperacaoId(
    String operacaoId,
  ) => _delegado.buscarExecucaoComparacaoPorOperacaoId(operacaoId);
  @override
  Future<ResultadoRetificacaoUnidade> retificarUnidadePatrimonio(
    ItemRetificacaoParaExecutar item,
  ) => _delegado.retificarUnidadePatrimonio(item);
  @override
  Future<List<PatrimonioEncontradoPorAnterior>> buscarPorTombamentoAnterior(
    String termo,
  ) => _delegado.buscarPorTombamentoAnterior(termo);
  @override
  Future<List<TombamentoHistoricoItem>> buscarHistoricoTombamentosPorId(
    String patrimonioId,
  ) => _delegado.buscarHistoricoTombamentosPorId(patrimonioId);
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  DashboardRepository? dashboardRepo,
  PatrimonioRepository? patrimonioRepo,
  ProfilePerfil perfil = ProfilePerfil.admin,
  ThemeData? theme,
  List<Profile> solicitacoesPendentes = const [],
  List<AppNotification> notificacoes = const [],
  bool isAndroid = false,
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
        permissionsRepositoryProvider.overrideWithValue(
          FakePermissionsRepository.paraPerfil(perfil),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          dashboardRepo ?? FakeDashboardRepository(),
        ),
        // Só é efetivamente LIDO quando o diálogo "Consultar patrimônio" é
        // aberto (nenhum provider do Dashboard em si depende disto) — ver
        // grupo "diálogo Consultar patrimônio".
        patrimonioRepositoryProvider.overrideWithValue(
          patrimonioRepo ?? FakePatrimonioRepository(),
        ),
        usuarioAdminRepositoryProvider.overrideWithValue(
          FakeUsuarioAdminRepository(usuarios: solicitacoesPendentes),
        ),
        appNotificationRepositoryProvider.overrideWithValue(
          FakeAppNotificationRepository(notificacoes: notificacoes),
        ),
        isAndroidProvider.overrideWithValue(isAndroid),
      ],
      child: MaterialApp(
        theme: theme,
        home: const Scaffold(body: DashboardPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppNotification _notificacaoNaoLida(String id) => AppNotification(
  id: id,
  eventId: 'e$id',
  tipo: TipoNotificacao.acessoSolicitado,
  titulo: 'Nova solicitação',
  corpo: 'corpo',
  alvoUsuarioId: 'fake-user-id',
  criadaEm: DateTime(2026, 1, 1),
);

void main() {
  group('KPIs principais', () {
    testWidgets('banco vazio: cards mostram 0', (tester) async {
      await _pumpDashboard(tester);

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Visão geral do patrimônio da GETEC'), findsOneWidget);
      expect(find.text('Patrimônios'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('com dados: cards mostram as contagens corretas', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          totalPatrimonios: 1414,
          totalSetores: 4,
          totalLocalizacoes: 15,
          totalTipos: 16,
          movimentacoesUltimos30Dias: 23,
        ),
      );

      expect(find.text('1414'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
    });

    testWidgets('loading: mostra indicador de progresso, sem travar a tela', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                initialUserId: 'u',
                profileResolver: (_) => _profile(ProfilePerfil.admin),
              ),
            ),
            permissionsRepositoryProvider.overrideWithValue(
              FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
            ),
            dashboardRepositoryProvider.overrideWithValue(
              _RepositorioTravado(),
            ),
            usuarioAdminRepositoryProvider.overrideWithValue(
              FakeUsuarioAdminRepository(),
            ),
            appNotificationRepositoryProvider.overrideWithValue(
              FakeAppNotificationRepository(),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: DashboardPage())),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'erro nas contagens: mensagem amigável + Tentar novamente, só nessa seção',
      (tester) async {
        await _pumpDashboard(
          tester,
          dashboardRepo: FakeDashboardRepository(
            erroContagens: const AppException('Falha ao contar patrimônios'),
            movimentacoesRecentes: [
              MovimentacaoResumo(
                id: '1',
                tipo: MovimentacaoTipo.transferencia,
                patrimonioLabel: '00045872',
                origemNome: 'GETEC',
                destinoNome: 'Almoxarifado',
                dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
              ),
            ],
          ),
        );

        expect(
          find.text('Não foi possível carregar estes dados.'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Tentar novamente'),
          findsOneWidget,
        );
        // A seção de movimentações recentes continua funcionando mesmo com
        // a seção de KPIs em erro (seção 16 do pedido).
        expect(find.textContaining('00045872'), findsOneWidget);
      },
    );
  });

  group('distribuição por setor/tipo e locais', () {
    testWidgets('mostra as barras com nome, quantidade e percentual', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          distribuicoes: const DashboardDistribuicoes(
            porSetor: [
              CategoriaContagem(id: 's1', nome: 'GETEC', quantidade: 520),
              CategoriaContagem(id: 's2', nome: 'GEASI', quantidade: 180),
            ],
            porTipo: [
              CategoriaContagem(id: 't1', nome: 'Notebook', quantidade: 320),
            ],
            topLocalizacoes: [
              CategoriaContagem(id: 'l1', nome: 'Sede GETEC', quantidade: 380),
            ],
            totalConsiderado: 700,
          ),
        ),
      );

      expect(find.text('Patrimônios por setor'), findsOneWidget);
      expect(find.text('Patrimônios por tipo'), findsOneWidget);
      expect(find.text('Locais com mais patrimônios'), findsOneWidget);
      expect(find.text('GETEC'), findsOneWidget);
      expect(find.textContaining('520'), findsOneWidget);
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('Sede GETEC'), findsOneWidget);
    });

    testWidgets('sem patrimônios: estado vazio em vez de barra quebrada', (
      tester,
    ) async {
      await _pumpDashboard(tester);

      expect(find.text('Nenhum patrimônio cadastrado.'), findsWidgets);
      expect(find.text('Nenhuma localização com patrimônio.'), findsOneWidget);
    });

    testWidgets('erro na distribuição não derruba KPIs nem movimentações', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          totalPatrimonios: 10,
          erroDistribuicoes: const AppException(
            'Falha ao carregar a distribuição',
          ),
        ),
      );

      expect(find.text('10'), findsOneWidget);
      expect(find.text('Não foi possível carregar estes dados.'), findsWidgets);
    });
  });

  group('movimentações recentes', () {
    testWidgets('mostra autor, origem/destino e permite ver todas', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          movimentacoesRecentes: [
            MovimentacaoResumo(
              id: '1',
              tipo: MovimentacaoTipo.transferencia,
              patrimonioLabel: '00045872',
              origemNome: 'GETEC',
              destinoNome: 'Almoxarifado',
              autorNome: 'Fulano da Silva',
              dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
            ),
          ],
        ),
      );

      expect(find.textContaining('00045872'), findsOneWidget);
      expect(find.textContaining('GETEC → Almoxarifado'), findsOneWidget);
      expect(find.textContaining('por Fulano da Silva'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Ver todas'), findsOneWidget);
    });

    testWidgets('usa a sigla do setor quando disponível (origem e destino)', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          movimentacoesRecentes: [
            MovimentacaoResumo(
              id: '1',
              tipo: MovimentacaoTipo.transferencia,
              patrimonioLabel: '00045872',
              origemNome: 'Gerência de Tecnologia',
              origemSigla: 'GETEC',
              destinoNome: 'Gerência de Administração e Suporte',
              destinoSigla: 'GEASI',
              dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
            ),
          ],
        ),
      );

      expect(find.textContaining('GETEC → GEASI'), findsOneWidget);
      expect(find.textContaining('Gerência de Tecnologia'), findsNothing);
      expect(
        find.textContaining('Gerência de Administração e Suporte'),
        findsNothing,
      );
    });

    testWidgets('sem sigla cadastrada: cai para o nome completo (fallback)', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          movimentacoesRecentes: [
            MovimentacaoResumo(
              id: '1',
              tipo: MovimentacaoTipo.transferencia,
              patrimonioLabel: '00045872',
              origemNome: 'Almoxarifado Central',
              destinoNome: 'Depósito Regional',
              dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
            ),
          ],
        ),
      );

      expect(
        find.textContaining('Almoxarifado Central → Depósito Regional'),
        findsOneWidget,
      );
    });

    testWidgets('oculta a seção inteira para quem não tem movimentacao.view', (
      tester,
    ) async {
      await _pumpDashboard(
        tester,
        perfil: ProfilePerfil.consulta,
        dashboardRepo: FakeDashboardRepository(
          movimentacoesRecentes: [
            MovimentacaoResumo(
              id: '1',
              tipo: MovimentacaoTipo.transferencia,
              patrimonioLabel: '00045872',
              dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
            ),
          ],
        ),
      );

      // CONSULTA tem `movimentacao.view` no preset padrão — a seção
      // continua visível; o teste abaixo (permissão customizada) é quem
      // comprova a ocultação de fato.
      expect(find.text('Movimentações recentes'), findsOneWidget);
    });
  });

  group('ações rápidas (controle de permissão)', () {
    testWidgets('ADMIN vê todas as ações', (tester) async {
      await _pumpDashboard(tester);

      expect(find.text('Novo patrimônio'), findsOneWidget);
      expect(find.text('Registrar movimentação'), findsOneWidget);
      expect(find.text('Importar patrimônios'), findsOneWidget);
      expect(find.text('Consultar patrimônio'), findsOneWidget);
      expect(find.text('Documento SEI'), findsOneWidget);
    });

    testWidgets(
      'CONSULTA só vê Consultar patrimônio — nenhuma ação de escrita',
      (tester) async {
        await _pumpDashboard(tester, perfil: ProfilePerfil.consulta);

        expect(find.text('Novo patrimônio'), findsNothing);
        expect(find.text('Registrar movimentação'), findsNothing);
        expect(find.text('Importar patrimônios'), findsNothing);
        expect(find.text('Consultar patrimônio'), findsOneWidget);
        // CONSULTA tem sei.view mas não sei.manage.
        expect(find.text('Documento SEI'), findsNothing);
      },
    );

    testWidgets('sem patrimonio.view: botão Consultar patrimônio não aparece', (
      tester,
    ) async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'u',
        profileResolver: (_) => _profile(ProfilePerfil.admin),
      );
      addTearDown(fakeAuth.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            permissionsRepositoryProvider.overrideWithValue(
              FakePermissionsRepository(chaves: const {}),
            ),
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(),
            ),
            patrimonioRepositoryProvider.overrideWithValue(
              FakePatrimonioRepository(),
            ),
            usuarioAdminRepositoryProvider.overrideWithValue(
              FakeUsuarioAdminRepository(),
            ),
            appNotificationRepositoryProvider.overrideWithValue(
              FakeAppNotificationRepository(),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: DashboardPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Consultar patrimônio'), findsNothing);
    });

    testWidgets(
      'Android: "Escanear patrimônio" aparece como a primeira ação',
      (tester) async {
        await _pumpDashboard(tester, isAndroid: true);

        expect(find.text('Escanear patrimônio'), findsOneWidget);
      },
    );

    testWidgets(
      'Windows (não Android): "Escanear patrimônio" nunca aparece',
      (tester) async {
        await _pumpDashboard(tester);

        expect(find.text('Escanear patrimônio'), findsNothing);
      },
    );
  });

  group('ações rápidas — navegação direta', () {
    testWidgets(
      'Android: "Escanear patrimônio" navega para /patrimonios/escanear '
      '(mesma rota/página do scanner avulso)',
      (tester) async {
        final fakeAuth = FakeAuthRepository(
          initialUserId: 'u',
          profileResolver: (_) => _profile(ProfilePerfil.admin),
        );
        addTearDown(fakeAuth.dispose);
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) =>
                  const Scaffold(body: DashboardPage()),
            ),
            GoRoute(
              path: '/patrimonios/escanear',
              builder: (context, state) =>
                  const Scaffold(body: Text('TELA_SCANNER')),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              permissionsRepositoryProvider.overrideWithValue(
                FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
              ),
              dashboardRepositoryProvider.overrideWithValue(
                FakeDashboardRepository(),
              ),
              usuarioAdminRepositoryProvider.overrideWithValue(
                FakeUsuarioAdminRepository(),
              ),
              appNotificationRepositoryProvider.overrideWithValue(
                FakeAppNotificationRepository(),
              ),
              isAndroidProvider.overrideWithValue(true),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Escanear patrimônio'));
        await tester.pumpAndSettle();

        expect(find.text('TELA_SCANNER'), findsOneWidget);
      },
    );

    testWidgets(
      '"Registrar movimentação" navega para /movimentacoes com acao=nova',
      (tester) async {
        Map<String, String>? capturada;
        final fakeAuth = FakeAuthRepository(
          initialUserId: 'u',
          profileResolver: (_) => _profile(ProfilePerfil.admin),
        );
        addTearDown(fakeAuth.dispose);
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) =>
                  const Scaffold(body: DashboardPage()),
            ),
            GoRoute(
              path: '/movimentacoes',
              builder: (context, state) {
                capturada = state.uri.queryParameters;
                return const Scaffold(body: Text('DESTINO'));
              },
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              permissionsRepositoryProvider.overrideWithValue(
                FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
              ),
              dashboardRepositoryProvider.overrideWithValue(
                FakeDashboardRepository(),
              ),
              usuarioAdminRepositoryProvider.overrideWithValue(
                FakeUsuarioAdminRepository(),
              ),
              appNotificationRepositoryProvider.overrideWithValue(
                FakeAppNotificationRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Registrar movimentação'));
        await tester.pumpAndSettle();

        expect(capturada?['acao'], 'nova');
      },
    );

    testWidgets(
      '"Documento SEI" navega para /movimentacoes com acao=importar-sei',
      (tester) async {
        Map<String, String>? capturada;
        final fakeAuth = FakeAuthRepository(
          initialUserId: 'u',
          profileResolver: (_) => _profile(ProfilePerfil.admin),
        );
        addTearDown(fakeAuth.dispose);
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) =>
                  const Scaffold(body: DashboardPage()),
            ),
            GoRoute(
              path: '/movimentacoes',
              builder: (context, state) {
                capturada = state.uri.queryParameters;
                return const Scaffold(body: Text('DESTINO'));
              },
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              permissionsRepositoryProvider.overrideWithValue(
                FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
              ),
              dashboardRepositoryProvider.overrideWithValue(
                FakeDashboardRepository(),
              ),
              usuarioAdminRepositoryProvider.overrideWithValue(
                FakeUsuarioAdminRepository(),
              ),
              appNotificationRepositoryProvider.overrideWithValue(
                FakeAppNotificationRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        final botaoSei = find.text('Documento SEI');
        await tester.ensureVisible(botaoSei);
        await tester.pumpAndSettle();
        await tester.tap(botaoSei);
        await tester.pumpAndSettle();

        expect(capturada?['acao'], 'importar-sei');
      },
    );
  });

  group('diálogo Consultar patrimônio', () {
    PatrimonioDetalhe item({
      required String id,
      required String numero,
      String tipoNome = 'Notebook',
      String setorNome = 'Setor',
      String? setorSigla,
      String? localizacaoNome,
    }) {
      return PatrimonioDetalhe(
        patrimonio: Patrimonio(
          id: id,
          numeroPatrimonio: numero,
          tipoId: 'tipo-1',
          status: PatrimonioStatus.disponivel,
          setorAtualId: 'setor-1',
          dataCadastro: DateTime(2026, 1, 1),
          atualizadoEm: DateTime(2026, 1, 1),
        ),
        tipoNome: tipoNome,
        setorNome: setorNome,
        setorSigla: setorSigla,
        localizacaoNome: localizacaoNome,
      );
    }

    Future<void> abrirDialogo(WidgetTester tester) async {
      final botao = find.text('Consultar patrimônio');
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await tester.pumpAndSettle();
    }

    testWidgets(
      'clique abre o diálogo com foco no campo e NENHUMA consulta antes de digitar',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [item(id: '1', numero: '3636001')],
        );
        await _pumpDashboard(tester, patrimonioRepo: repo);

        await abrirDialogo(tester);

        expect(find.text('Consultar patrimônio'), findsWidgets);
        final campo = tester.widget<TextField>(find.byType(TextField));
        expect(campo.autofocus, isTrue);
        expect(
          find.text('Digite um número patrimonial para pesquisar.'),
          findsOneWidget,
        );
        expect(repo.buscarPorPrefixoNumeroPatrimonioCallCount, 0);
      },
    );

    testWidgets(
      'digitar refina o prefixo: buscas intermediárias são canceladas pelo debounce',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [
            item(id: '1', numero: '3636001'),
            item(id: '2', numero: '3636127'),
            item(id: '3', numero: '1236360'),
          ],
        );
        await _pumpDashboard(tester, patrimonioRepo: repo);
        await abrirDialogo(tester);

        await tester.enterText(find.byType(TextField), '3');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), '36');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // só a busca final ("3636") chegou a executar — "3" e "36" foram
        // canceladas pelo debounce antes de completar 300ms.
        expect(repo.buscarPorPrefixoNumeroPatrimonioCallCount, 1);
        expect(find.text('3636001'), findsOneWidget);
        expect(find.text('3636127'), findsOneWidget);
        // "1236360" contém "3636" no meio, mas não COMEÇA com "3636".
        expect(find.text('1236360'), findsNothing);
      },
    );

    testWidgets(
      'nunca mostra mais de 6 resultados, envia LIMIT 6 ao repositório e mostra a dica de continuar digitando',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [
            for (var i = 0; i < 10; i++)
              item(id: '$i', numero: '36${i.toString().padLeft(2, '0')}'),
          ],
        );
        await _pumpDashboard(tester, patrimonioRepo: repo);
        await abrirDialogo(tester);

        await tester.enterText(find.byType(TextField), '36');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(repo.ultimoLimitPrefixo, 6);
        // 10 correspondências no banco, mas o LIMIT 6 (servidor) + ASC
        // garante que só as 6 primeiras ("3600".."3605") aparecem.
        for (var i = 0; i <= 5; i++) {
          expect(
            find.text('36${i.toString().padLeft(2, '0')}'),
            findsOneWidget,
          );
        }
        for (var i = 6; i <= 9; i++) {
          expect(find.text('36${i.toString().padLeft(2, '0')}'), findsNothing);
        }
        expect(
          find.text('Continue digitando para refinar a pesquisa.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('menos de 6 resultados: sem a dica de continuar digitando', (
      tester,
    ) async {
      final repo = FakePatrimonioRepository(
        itens: [item(id: '1', numero: '3636001')],
      );
      await _pumpDashboard(tester, patrimonioRepo: repo);
      await abrirDialogo(tester);

      await tester.enterText(find.byType(TextField), '3636');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('3636001'), findsOneWidget);
      expect(
        find.text('Continue digitando para refinar a pesquisa.'),
        findsNothing,
      );
    });

    testWidgets(
      'enquanto a consulta está em voo, mostra um indicador discreto',
      (tester) async {
        final gate = Completer<List<PatrimonioDetalhe>>();
        final repo = _PatrimonioRepositorioTravado(gate);
        await _pumpDashboard(tester, patrimonioRepo: repo);
        await abrirDialogo(tester);

        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        gate.complete([item(id: '1', numero: '3636001')]);
        await tester.pumpAndSettle();
        expect(find.text('3636001'), findsOneWidget);
      },
    );

    testWidgets('sem correspondência: mensagem amigável', (tester) async {
      final repo = FakePatrimonioRepository(
        itens: [item(id: '1', numero: '9999999')],
      );
      await _pumpDashboard(tester, patrimonioRepo: repo);
      await abrirDialogo(tester);

      await tester.enterText(find.byType(TextField), '3636');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum patrimônio encontrado.'), findsOneWidget);
    });

    testWidgets(
      'falha ao pesquisar: mensagem + Tentar novamente, e o retry funciona',
      (tester) async {
        final repo = _RepositorioComFalhaNaPrimeiraPrefixo(
          item(id: '1', numero: '3636001'),
        );
        await _pumpDashboard(tester, patrimonioRepo: repo);
        await abrirDialogo(tester);

        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(
          find.text('Não foi possível pesquisar os patrimônios.'),
          findsOneWidget,
        );
        final botaoRetry = find.widgetWithText(
          OutlinedButton,
          'Tentar novamente',
        );
        expect(botaoRetry, findsOneWidget);

        await tester.tap(botaoRetry);
        await tester.pumpAndSettle();

        expect(find.text('3636001'), findsOneWidget);
      },
    );

    testWidgets(
      'clicar num resultado fecha o diálogo e navega para /patrimonios/<id correto>',
      (tester) async {
        final fakeAuth = FakeAuthRepository(
          initialUserId: 'u',
          profileResolver: (_) => _profile(ProfilePerfil.admin),
        );
        addTearDown(fakeAuth.dispose);

        String? idNavegado;
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) =>
                  const Scaffold(body: DashboardPage()),
            ),
            GoRoute(
              path: '/patrimonios/:id',
              builder: (context, state) {
                idNavegado = state.pathParameters['id'];
                return const Scaffold(body: Text('PATRIMONIO_DETALHE'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              permissionsRepositoryProvider.overrideWithValue(
                FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
              ),
              dashboardRepositoryProvider.overrideWithValue(
                FakeDashboardRepository(),
              ),
              patrimonioRepositoryProvider.overrideWithValue(
                FakePatrimonioRepository(
                  itens: [item(id: 'patrimonio-42', numero: '3636001')],
                ),
              ),
              usuarioAdminRepositoryProvider.overrideWithValue(
                FakeUsuarioAdminRepository(),
              ),
              appNotificationRepositoryProvider.overrideWithValue(
                FakeAppNotificationRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await abrirDialogo(tester);
        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        await tester.tap(find.text('3636001'));
        await tester.pumpAndSettle();

        expect(idNavegado, 'patrimonio-42');
        expect(find.text('PATRIMONIO_DETALHE'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
      },
    );

    testWidgets('Enter com UMA única correspondência abre automaticamente', (
      tester,
    ) async {
      final fakeAuth = FakeAuthRepository(
        initialUserId: 'u',
        profileResolver: (_) => _profile(ProfilePerfil.admin),
      );
      addTearDown(fakeAuth.dispose);

      String? idNavegado;
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const Scaffold(body: DashboardPage()),
          ),
          GoRoute(
            path: '/patrimonios/:id',
            builder: (context, state) {
              idNavegado = state.pathParameters['id'];
              return const Scaffold(body: Text('PATRIMONIO_DETALHE'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            permissionsRepositoryProvider.overrideWithValue(
              FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
            ),
            dashboardRepositoryProvider.overrideWithValue(
              FakeDashboardRepository(),
            ),
            patrimonioRepositoryProvider.overrideWithValue(
              FakePatrimonioRepository(
                itens: [item(id: 'patrimonio-42', numero: '3636001')],
              ),
            ),
            usuarioAdminRepositoryProvider.overrideWithValue(
              FakeUsuarioAdminRepository(),
            ),
            appNotificationRepositoryProvider.overrideWithValue(
              FakeAppNotificationRepository(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await abrirDialogo(tester);
      await tester.enterText(find.byType(TextField), '3636001');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(idNavegado, 'patrimonio-42');
    });

    testWidgets(
      'Enter com MAIS de uma correspondência nunca seleciona a primeira arbitrariamente',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [
            item(id: '1', numero: '3636001'),
            item(id: '2', numero: '3636127'),
          ],
        );
        await _pumpDashboard(tester, patrimonioRepo: repo);
        await abrirDialogo(tester);

        await tester.enterText(find.byType(TextField), '3636');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // o diálogo continua aberto, com os dois resultados — Enter não
        // escolheu nenhum deles.
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('3636001'), findsOneWidget);
        expect(find.text('3636127'), findsOneWidget);
      },
    );
  });

  group('seção Atenção (só ADMIN)', () {
    testWidgets('ADMIN com pendências reais: mostra as contagens', (
      tester,
    ) async {
      final pendente = Profile(
        id: 'p1',
        nome: 'Pendente',
        perfil: ProfilePerfil.operador,
        ativo: false,
        criadoEm: DateTime.utc(2026, 1, 1),
        atualizadoEm: DateTime.utc(2026, 1, 1),
        accessStatus: ProfileAccessStatus.pending,
        rejectionCount: 0,
      );

      await _pumpDashboard(
        tester,
        solicitacoesPendentes: [pendente],
        notificacoes: [_notificacaoNaoLida('n1'), _notificacaoNaoLida('n2')],
      );

      expect(find.text('Atenção'), findsOneWidget);
      expect(
        find.textContaining('1 solicitação de acesso aguardando aprovação'),
        findsOneWidget,
      );
      expect(find.textContaining('2 notificações não lidas'), findsOneWidget);
    });

    testWidgets('ADMIN sem nenhuma pendência: estado discreto', (tester) async {
      await _pumpDashboard(tester);

      expect(find.text('Nenhuma pendência no momento.'), findsOneWidget);
    });

    testWidgets('GESTOR não vê a seção Atenção', (tester) async {
      await _pumpDashboard(tester, perfil: ProfilePerfil.gestor);

      expect(find.text('Atenção'), findsNothing);
    });
  });

  group('responsividade (sem overflow)', () {
    Future<void> pumpEm(WidgetTester tester, Size tamanho) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpDashboard(
        tester,
        dashboardRepo: FakeDashboardRepository(
          totalPatrimonios: 1414,
          totalSetores: 4,
          totalLocalizacoes: 15,
          totalTipos: 16,
          movimentacoesUltimos30Dias: 23,
          distribuicoes: const DashboardDistribuicoes(
            porSetor: [
              CategoriaContagem(
                id: 's1',
                nome: 'Gerência de Tecnologia',
                quantidade: 520,
              ),
              CategoriaContagem(id: 's2', nome: 'GEASI', quantidade: 180),
            ],
            porTipo: [
              CategoriaContagem(id: 't1', nome: 'Notebook', quantidade: 320),
            ],
            topLocalizacoes: [
              CategoriaContagem(
                id: 'l1',
                nome: 'Datacenter - Universitário',
                quantidade: 380,
              ),
            ],
            totalConsiderado: 700,
          ),
          movimentacoesRecentes: [
            MovimentacaoResumo(
              id: '1',
              tipo: MovimentacaoTipo.transferencia,
              patrimonioLabel: '00045872',
              origemNome: 'GETEC',
              destinoNome: 'Almoxarifado',
              autorNome: 'Fulano de Tal da Silva Sauro',
              dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
            ),
          ],
        ),
      );
    }

    for (final tamanho in [
      const Size(1920, 1009),
      const Size(1280, 720),
      const Size(1024, 768),
    ]) {
      testWidgets(
        '${tamanho.width.toInt()}x${tamanho.height.toInt()}: sem overflow',
        (tester) async {
          await pumpEm(tester, tamanho);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'mobile (390x844): KPIs em grade de 2 colunas, sem overflow',
      (tester) async {
        await pumpEm(tester, const Size(390, 844));
        expect(tester.takeException(), isNull);

        // "Patrimônios" e "Setores" (1o e 2o KPI) ficam lado a lado na
        // mesma linha — grade de 2 colunas, nunca os 5 KPIs empilhados em
        // 5 linhas (melhoria de interface Android: seção "Visão Geral"
        // compacta).
        final topoPatrimonios = tester
            .getTopLeft(find.text('Patrimônios'))
            .dy;
        final topoSetores = tester.getTopLeft(find.text('Setores')).dy;
        expect(
          topoPatrimonios,
          closeTo(topoSetores, 2),
          reason: '1o e 2o KPI deveriam estar na mesma linha (2 colunas)',
        );

        // "Localizações" (3o KPI) cai para a linha seguinte.
        final topoLocalizacoes = tester
            .getTopLeft(find.text('Localizações'))
            .dy;
        expect(
          topoLocalizacoes,
          greaterThan(topoPatrimonios + 10),
          reason: '3o KPI deveria estar numa linha abaixo dos 2 primeiros',
        );
      },
    );
  });

  group('dark/light', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      testWidgets(
        'renderiza sem erro no tema ${theme == AppTheme.light ? "claro" : "escuro"}',
        (tester) async {
          await _pumpDashboard(
            tester,
            theme: theme,
            dashboardRepo: FakeDashboardRepository(totalPatrimonios: 10),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Dashboard'), findsOneWidget);
        },
      );
    }
  });

  group('refinamento visual — hierarquia', () {
    testWidgets(
      'Ações rápidas aparece logo abaixo dos KPIs, antes da área operacional',
      (tester) async {
        await _pumpDashboard(tester);

        final yKpis = tester.getTopLeft(find.text('Patrimônios')).dy;
        final yAcoes = tester.getTopLeft(find.text('Ações rápidas')).dy;
        final yMovimentacoes = tester
            .getTopLeft(find.text('Movimentações recentes'))
            .dy;

        expect(yKpis, lessThan(yAcoes));
        expect(yAcoes, lessThan(yMovimentacoes));
      },
    );

    testWidgets(
      'seção Atenção aparece logo depois das Ações rápidas, antes da área operacional',
      (tester) async {
        final pendente = Profile(
          id: 'p1',
          nome: 'Pendente',
          perfil: ProfilePerfil.operador,
          ativo: false,
          criadoEm: DateTime.utc(2026, 1, 1),
          atualizadoEm: DateTime.utc(2026, 1, 1),
          accessStatus: ProfileAccessStatus.pending,
          rejectionCount: 0,
        );

        await _pumpDashboard(tester, solicitacoesPendentes: [pendente]);

        final yAcoes = tester.getTopLeft(find.text('Ações rápidas')).dy;
        final yAtencao = tester.getTopLeft(find.text('Atenção')).dy;
        final yMovimentacoes = tester
            .getTopLeft(find.text('Movimentações recentes'))
            .dy;

        expect(yAtencao, greaterThan(yAcoes));
        expect(yAtencao, lessThan(yMovimentacoes));
      },
    );

    testWidgets(
      'painel de setor com 1 item não é forçado à mesma altura do painel de tipo com mais itens',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpDashboard(
          tester,
          dashboardRepo: FakeDashboardRepository(
            distribuicoes: const DashboardDistribuicoes(
              porSetor: [
                CategoriaContagem(id: 's1', nome: 'GETEC', quantidade: 1000),
              ],
              porTipo: [
                CategoriaContagem(id: 't1', nome: 'Notebook', quantidade: 100),
                CategoriaContagem(id: 't2', nome: 'Monitor', quantidade: 90),
                CategoriaContagem(id: 't3', nome: 'Impressora', quantidade: 80),
                CategoriaContagem(id: 't4', nome: 'Teclado', quantidade: 70),
                CategoriaContagem(id: 't5', nome: 'Mouse', quantidade: 60),
                CategoriaContagem(id: 't6', nome: 'Switch', quantidade: 50),
                CategoriaContagem(id: 't7', nome: 'Roteador', quantidade: 40),
                CategoriaContagem(id: 't8', nome: 'Nobreak', quantidade: 30),
              ],
              topLocalizacoes: [],
              totalConsiderado: 1000,
            ),
          ),
        );

        final cards = find.byType(CategoriaBarrasCard);
        expect(cards, findsNWidgets(2));
        final alturaSetor = tester.getSize(cards.at(0)).height;
        final alturaTipo = tester.getSize(cards.at(1)).height;

        // Antes do refinamento, as duas ficavam pareadas lado a lado na
        // mesma `Row` e a mais baixa era forçada a ocupar a altura da mais
        // alta — por isso a comparação estrita (nunca `lessThanOrEqualTo`)
        // é o que de fato comprova que o pareamento rígido foi removido.
        expect(alturaSetor, lessThan(alturaTipo));
      },
    );
  });

  group('movimentações recentes — linha clicável', () {
    testWidgets(
      'clicar na linha abre o resumo com os dados já carregados (sem nova consulta)',
      (tester) async {
        await _pumpDashboard(
          tester,
          dashboardRepo: FakeDashboardRepository(
            movimentacoesRecentes: [
              MovimentacaoResumo(
                id: 'mov-1',
                tipo: MovimentacaoTipo.transferencia,
                patrimonioLabel: '00045872',
                origemNome: 'GETEC',
                destinoNome: 'Almoxarifado',
                autorNome: 'Fulano da Silva',
                dataMovimentacao: DateTime.utc(2026, 1, 10, 12),
              ),
            ],
          ),
        );

        final linha = find.textContaining('00045872');
        await tester.ensureVisible(linha);
        await tester.pumpAndSettle();
        await tester.tap(linha);
        await tester.pumpAndSettle();

        expect(find.text('Movimentação'), findsOneWidget);
        expect(find.text('00045872'), findsWidgets);
        expect(find.text('GETEC'), findsWidgets);
        expect(find.text('Almoxarifado'), findsWidgets);
        expect(find.text('Fulano da Silva'), findsWidgets);
        expect(
          find.widgetWithText(FilledButton, 'Ver movimentação completa'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(TextButton, 'Fechar'));
        await tester.pumpAndSettle();
        expect(find.text('Ver movimentação completa'), findsNothing);
      },
    );

    testWidgets(
      '"Ver movimentação completa" navega para /movimentacoes/<id da movimentação clicada>',
      (tester) async {
        final fakeAuth = FakeAuthRepository(
          initialUserId: 'u',
          profileResolver: (_) => _profile(ProfilePerfil.admin),
        );
        addTearDown(fakeAuth.dispose);

        String? idNavegado;
        final router = GoRouter(
          initialLocation: '/dashboard',
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) =>
                  const Scaffold(body: DashboardPage()),
            ),
            GoRoute(
              path: '/movimentacoes/:id',
              builder: (context, state) {
                idNavegado = state.pathParameters['id'];
                return const Scaffold(body: Text('MOVIMENTACAO_DETALHE'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              permissionsRepositoryProvider.overrideWithValue(
                FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
              ),
              dashboardRepositoryProvider.overrideWithValue(
                FakeDashboardRepository(
                  movimentacoesRecentes: [
                    MovimentacaoResumo(
                      id: 'mov-42',
                      tipo: MovimentacaoTipo.entrada,
                      patrimonioLabel: '123',
                      dataMovimentacao: DateTime.utc(2026, 1, 1),
                    ),
                  ],
                ),
              ),
              usuarioAdminRepositoryProvider.overrideWithValue(
                FakeUsuarioAdminRepository(),
              ),
              appNotificationRepositoryProvider.overrideWithValue(
                FakeAppNotificationRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        final linha = find.textContaining('123');
        await tester.ensureVisible(linha);
        await tester.pumpAndSettle();
        await tester.tap(linha);
        await tester.pumpAndSettle();

        final botaoVerCompleta = find.widgetWithText(
          FilledButton,
          'Ver movimentação completa',
        );
        await tester.ensureVisible(botaoVerCompleta);
        await tester.pumpAndSettle();
        await tester.tap(botaoVerCompleta);
        await tester.pumpAndSettle();

        expect(idNavegado, 'mov-42');
        expect(find.text('MOVIMENTACAO_DETALHE'), findsOneWidget);
      },
    );
  });
}
