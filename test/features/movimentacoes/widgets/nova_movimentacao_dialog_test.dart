import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_historico_item.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_repository.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacoes_resultado.dart';
import 'package:invtec/features/movimentacoes/presentation/movimentacoes_page.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/nova_movimentacao/nova_movimentacao_rascunho.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../patrimonios/fake_patrimonio_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_movimentacao_repository.dart';

/// Envelopa um [FakeMovimentacaoRepository] e atrasa [registrarMovimentacao]
/// até [liberar] ser chamado — único jeito de testar double-submit de forma
/// determinística (o fake normal resolve rápido demais para um segundo tap
/// acontecer antes da resposta do primeiro).
class _RepositorioLento implements MovimentacaoRepository {
  _RepositorioLento(this._interno);

  final FakeMovimentacaoRepository _interno;
  final _pendentes = <Completer<Movimentacao>>[];

  void liberarTodos() {
    for (final c in _pendentes) {
      if (!c.isCompleted) c.complete(_interno.movimentacaoRegistrada ?? _movimentacaoPadrao());
    }
  }

  Movimentacao _movimentacaoPadrao() => Movimentacao(
    id: 'fake',
    patrimonioId: 'p1',
    tipo: MovimentacaoTipo.transferencia,
    dataMovimentacao: DateTime(2026, 1, 1),
    criadoEm: DateTime(2026, 1, 1),
  );

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
    _interno.registrarMovimentacao(
      patrimonioId: patrimonioId,
      tipo: tipo,
      destinoId: destinoId,
      localizacaoDestinoId: localizacaoDestinoId,
      limparLocalizacao: limparLocalizacao,
      responsavelDestino: responsavelDestino,
      motivo: motivo,
      observacao: observacao,
      numeroDocumento: numeroDocumento,
      numeroChamado: numeroChamado,
      dataMovimentacao: dataMovimentacao,
    );
    final completer = Completer<Movimentacao>();
    _pendentes.add(completer);
    return completer.future;
  }

  int get registrarCallCount => _interno.registrarCallCount;

  @override
  Future<MovimentacoesResultado> listar({
    int limit = 25,
    int offset = 0,
    String? busca,
    MovimentacaoTipo? tipo,
    String? setorId,
    DateTime? periodoDe,
    DateTime? periodoAte,
  }) => _interno.listar(limit: limit, offset: offset, busca: busca, tipo: tipo, setorId: setorId, periodoDe: periodoDe, periodoAte: periodoAte);

  @override
  Future<List<Movimentacao>> listarPorPatrimonio(String patrimonioId, {int limit = 20, int offset = 0}) =>
      _interno.listarPorPatrimonio(patrimonioId, limit: limit, offset: offset);

  @override
  Future<List<MovimentacaoHistoricoItem>> listarHistoricoPorPatrimonio(
    String patrimonioId, {
    int limit = 20,
    int offset = 0,
  }) => _interno.listarHistoricoPorPatrimonio(patrimonioId, limit: limit, offset: offset);
}

Profile _profile(ProfilePerfil perfil) => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

PatrimonioDetalhe _patrimonioDetalhe({
  String id = 'p1',
  String numero = '100',
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  String setorAtualId = 'setor-a',
  String? localizacaoAtualId,
  String? responsavelAtual,
  String setorNome = 'GETEC',
  String? localizacaoNome,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: setorAtualId,
      localizacaoAtualId: localizacaoAtualId,
      responsavelAtual: responsavelAtual,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: setorNome,
    localizacaoNome: localizacaoNome,
  );
}

final _setorA = Setor(id: 'setor-a', nome: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorB = Setor(id: 'setor-b', nome: 'GEVEV', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorC = Setor(id: 'setor-c', nome: 'GESIS', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _localizacaoA1 = Localizacao(id: 'loc-a1', setorId: 'setor-a', nome: 'Home Office', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _localizacaoB1 = Localizacao(id: 'loc-b1', setorId: 'setor-b', nome: 'Sala 2', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _localizacaoC1 = Localizacao(id: 'loc-c1', setorId: 'setor-c', nome: 'Sala 5', ativo: true, criadoEm: DateTime(2026, 1, 1));

Future<MovimentacaoRepository> _pumpEAbrirWizard(
  WidgetTester tester, {
  required MovimentacaoRepository movimentacaoRepo,
  List<PatrimonioDetalhe>? patrimonios,
  FakePatrimonioRepository? patrimonioRepositorio,
  List<Setor>? setores,
  List<Localizacao>? localizacoes,
}) async {
  final fakeAuth = FakeAuthRepository(initialUserId: 'fake-user-id', profileResolver: (_) => _profile(ProfilePerfil.admin));
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        movimentacaoRepositoryProvider.overrideWithValue(movimentacaoRepo),
        patrimonioRepositoryProvider.overrideWithValue(
          patrimonioRepositorio ?? FakePatrimonioRepository(itens: patrimonios ?? [_patrimonioDetalhe()]),
        ),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores ?? [_setorA, _setorB])),
        localizacaoRepositoryProvider.overrideWithValue(
          FakeLocalizacaoRepository(localizacoes: localizacoes ?? [_localizacaoA1, _localizacaoB1]),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: MovimentacoesPage())),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Nova movimentação'));
  await tester.pumpAndSettle();
  return movimentacaoRepo;
}

Future<void> _voltar(WidgetTester tester) async {
  await _tocar(tester, find.descendant(of: find.byType(Dialog), matching: find.text('Voltar')));
}

/// O diálogo é um overlay por cima de `MovimentacoesPage`, que também tem um
/// campo de busca — `find.byType(TextField)`/`ListTile` sem escopo colide
/// com widgets da página por baixo, então tudo aqui é escopado ao `Dialog`.
Future<void> _buscarESelecionarPatrimonio(WidgetTester tester, {String termo = '100'}) async {
  final dialog = find.byType(Dialog);
  await tester.enterText(find.descendant(of: dialog, matching: find.byType(TextField)).first, termo);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: dialog, matching: find.byType(ListTile)).first);
  await tester.pumpAndSettle();
}

Future<void> _escolherTipo(WidgetTester tester, MovimentacaoTipo tipo) async {
  final tile = find.descendant(of: find.byType(Dialog), matching: find.widgetWithText(ListTile, tipo.label));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _avancar(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Avançar')));
  await tester.pumpAndSettle();
}

/// O conteúdo de cada passo vive num `SingleChildScrollView` dentro do
/// diálogo — qualquer campo mais abaixo (localização, responsável,
/// documento/chamado, o checkbox de BAIXA) pode não estar na área visível
/// inicial. `ensureVisible` antes de cada tap evita testes flakeando por
/// hit-test em algo fora da viewport do diálogo.
Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _selecionarSetorDestino(WidgetTester tester, String nomeSetor, {bool obrigatorio = true}) async {
  final campo = find.widgetWithText(
    DropdownButtonFormField<String?>,
    obrigatorio ? 'Setor de destino *' : 'Setor de destino',
  );
  await _tocar(tester, campo);
  await _tocar(tester, find.text(nomeSetor).last);
}

Future<void> _marcarConfirmacaoBaixa(WidgetTester tester) async {
  await _tocar(tester, find.text('Confirmo que desejo dar baixa neste patrimônio.'));
}

void main() {
  group('PROMPT 10.2 — wizard de Nova Movimentação', () {
    testWidgets('busca e seleciona o patrimônio, mostra o resumo e avança para Tipo', (tester) async {
      await _pumpEAbrirWizard(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        patrimonios: [_patrimonioDetalhe(numero: '100', status: PatrimonioStatus.disponivel)],
      );

      await _buscarESelecionarPatrimonio(tester);

      expect(find.text('Passo 2 de 4 · Tipo'), findsOneWidget);
      expect(find.text('Patrimônio: 100'), findsOneWidget);
      expect(find.text('Status atual do patrimônio: Disponível.'), findsOneWidget);
    });

    testWidgets('só oferece tipos compatíveis com o status atual (EMPRESTADO)', (tester) async {
      await _pumpEAbrirWizard(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        patrimonios: [_patrimonioDetalhe(status: PatrimonioStatus.emprestado)],
      );
      await _buscarESelecionarPatrimonio(tester);

      expect(find.widgetWithText(ListTile, 'Devolução'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Ajuste de inventário'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Baixa'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Transferência'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Empréstimo'), findsNothing);
    });

    testWidgets('BAIXA não mostra campos de setor/localização/responsável', (tester) async {
      await _pumpEAbrirWizard(tester, movimentacaoRepo: FakeMovimentacaoRepository());
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.baixa);
      await _avancar(tester);

      expect(find.text('Passo 3 de 4 · Detalhes'), findsOneWidget);
      expect(find.text('Setor de destino'), findsNothing);
      expect(find.text('Setor de destino *'), findsNothing);
      expect(find.text('Responsável'), findsNothing);
      expect(find.text('Motivo'), findsOneWidget);
      // Sem responsável/destino a preencher: já pode avançar.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Avançar')).onPressed, isNotNull);
    });

    testWidgets('EMPRESTIMO exige responsável para avançar', (tester) async {
      await _pumpEAbrirWizard(tester, movimentacaoRepo: FakeMovimentacaoRepository());
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.emprestimo);
      await _avancar(tester);

      expect(find.text('Responsável *'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Avançar')).onPressed, isNull);

      // Preencher só o responsável não basta: EMPRESTIMO também exige
      // destino (seção 6 do prompt — os dois são checados juntos).
      await tester.enterText(find.widgetWithText(TextFormField, 'Responsável *'), 'Maria Souza');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Avançar')).onPressed, isNull);

      await _selecionarSetorDestino(tester, 'GEVEV');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Avançar')).onPressed, isNotNull);
    });

    testWidgets('trocar o setor de destino reseta a localização já escolhida', (tester) async {
      await _pumpEAbrirWizard(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        setores: [_setorA, _setorB, _setorC],
        localizacoes: [_localizacaoA1, _localizacaoB1, _localizacaoC1],
      );
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.manutencao);
      await _avancar(tester);

      await _selecionarSetorDestino(tester, 'GEVEV');

      await _tocar(tester, find.widgetWithText(DropdownButtonFormField<String?>, 'Localização de destino'));
      await _tocar(tester, find.text('Sala 2').last);
      expect(find.text('Sala 2'), findsOneWidget);

      // Trocar para outro setor de destino (MANUTENCAO nunca oferece o setor
      // atual — PROMPT 10.2.2, seção 3) invalida a localização do setor
      // anterior.
      await _selecionarSetorDestino(tester, 'GESIS');

      expect(find.text('Sala 2'), findsNothing);
    });

    testWidgets('AJUSTE_INVENTARIO: manter localização (padrão) não altera nada', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);
      await _avancar(tester); // Detalhes -> Revisão (nada obrigatório)
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.ultimoRegistrar!['localizacaoDestinoId'], isNull);
      expect(repo.ultimoRegistrar!['limparLocalizacao'], isFalse);
    });

    testWidgets('AJUSTE_INVENTARIO: definir nova localização envia o id escolhido', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      await _tocar(tester, find.text('Definir nova'));
      await _tocar(tester, find.widgetWithText(DropdownButtonFormField<String?>, 'Localização de destino *'));
      await _tocar(tester, find.text('Home Office').last);

      await _avancar(tester);
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.ultimoRegistrar!['localizacaoDestinoId'], 'loc-a1');
      expect(repo.ultimoRegistrar!['limparLocalizacao'], isFalse);
    });

    testWidgets('AJUSTE_INVENTARIO: limpar localização envia limparLocalizacao=true e id nulo', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo, patrimonios: [
        _patrimonioDetalhe(localizacaoAtualId: 'loc-a1', localizacaoNome: 'Home Office'),
      ]);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      await _tocar(tester, find.text('Limpar'));
      await _avancar(tester);
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.ultimoRegistrar!['localizacaoDestinoId'], isNull);
      expect(repo.ultimoRegistrar!['limparLocalizacao'], isTrue);
    });

    testWidgets('revisão mostra motivo/documento/chamado só quando preenchidos', (tester) async {
      await _pumpEAbrirWizard(tester, movimentacaoRepo: FakeMovimentacaoRepository());
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.manutencao);
      await _avancar(tester);

      await _selecionarSetorDestino(tester, 'GEVEV');
      await tester.enterText(find.widgetWithText(TextFormField, 'Número do documento'), 'DOC-9');
      await tester.pumpAndSettle();

      await _avancar(tester);

      expect(find.text('Documento'), findsOneWidget);
      expect(find.text('DOC-9'), findsOneWidget);
      expect(find.text('Chamado'), findsNothing);
    });

    testWidgets('cancelar antes da confirmação não chama o repository', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.baixa);

      await _tocar(tester, find.text('Cancelar'));

      expect(repo.registrarCallCount, 0);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('BAIXA exige o checkbox de confirmação reforçada antes de habilitar o envio', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.baixa);
      await _avancar(tester);
      await _avancar(tester);

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar movimentação')).onPressed, isNull);

      await _marcarConfirmacaoBaixa(tester);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar movimentação')).onPressed, isNotNull);

      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.registrarCallCount, 1);
      expect(repo.ultimoRegistrar!['tipo'], MovimentacaoTipo.baixa);
    });

    testWidgets('confirmação chama o repository exatamente uma vez, fecha o diálogo e recarrega a listagem', (
      tester,
    ) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      final chamadasListarAntes = repo.listarCallCount;

      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.manutencao);
      await _avancar(tester);
      await _selecionarSetorDestino(tester, 'GEVEV');
      await _avancar(tester);

      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.registrarCallCount, 1);
      expect(repo.ultimoRegistrar!['patrimonioId'], 'p1');
      expect(repo.ultimoRegistrar!['tipo'], MovimentacaoTipo.manutencao);
      expect(repo.ultimoRegistrar!['destinoId'], 'setor-b');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Movimentação registrada com sucesso.'), findsOneWidget);
      expect(repo.listarCallCount, greaterThan(chamadasListarAntes));
    });

    testWidgets('double-tap em Confirmar não duplica o envio', (tester) async {
      final interno = FakeMovimentacaoRepository();
      final lento = _RepositorioLento(interno);
      await _pumpEAbrirWizard(tester, movimentacaoRepo: lento);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.baixa);
      await _avancar(tester);
      await _avancar(tester);
      await _marcarConfirmacaoBaixa(tester);

      // Achado por key, não por texto: durante o envio o texto vira um
      // spinner (é exatamente isso que este teste quer provar), então um
      // finder por texto perderia o botão no segundo tap.
      final botao = find.byKey(const ValueKey('nova-movimentacao-confirmar'));
      await tester.ensureVisible(botao);
      await tester.pumpAndSettle();
      await tester.tap(botao);
      await tester.pump();
      // Segundo tap enquanto a primeira chamada ainda está em voo — o botão
      // já deveria estar desabilitado (mostrando um spinner no lugar).
      await tester.tap(botao, warnIfMissed: false);
      await tester.pump();

      lento.liberarTodos();
      await tester.pumpAndSettle();

      expect(lento.registrarCallCount, 1);
    });

    testWidgets('erro da RPC é exibido e mantém o formulário preenchido, sem fechar o diálogo', (tester) async {
      final repo = FakeMovimentacaoRepository(erroRegistrar: AppException('O destino selecionado é igual ao setor atual do patrimônio.'));
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.manutencao);
      await _avancar(tester);
      await _selecionarSetorDestino(tester, 'GEVEV');
      await _avancar(tester);

      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(find.text('O destino selecionado é igual ao setor atual do patrimônio.'), findsOneWidget);
      // Diálogo continua aberto, revisão ainda visível — nada foi perdido.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Passo 4 de 4 · Revisão'), findsOneWidget);
      expect(repo.registrarCallCount, 1);
    });

    testWidgets(
      'concorrência: erro de estado desatualizado recarrega o patrimônio e o wizard reflete o novo status',
      (tester) async {
        final movimentacaoRepo = FakeMovimentacaoRepository(
          erroRegistrar: AppException('O patrimônio foi alterado por outra operação. Recarregue e tente novamente.'),
        );
        final patrimonioRepo = FakePatrimonioRepository(
          itens: [_patrimonioDetalhe(status: PatrimonioStatus.disponivel)],
        );

        await _pumpEAbrirWizard(
          tester,
          movimentacaoRepo: movimentacaoRepo,
          patrimonioRepositorio: patrimonioRepo,
        );
        await _buscarESelecionarPatrimonio(tester);
        await _escolherTipo(tester, MovimentacaoTipo.manutencao);
        await _avancar(tester);
        await _selecionarSetorDestino(tester, 'GEVEV');
        await _avancar(tester);

        // Simula outra sessão movendo o mesmo patrimônio para EM_USO entre a
        // abertura do formulário e a confirmação — só depois de já termos
        // lido o estado original, exatamente como aconteceria em produção.
        patrimonioRepo.substituirDetalhe(_patrimonioDetalhe(status: PatrimonioStatus.emUso));

        await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

        expect(
          find.text('O patrimônio foi alterado por outra operação. Recarregue e tente novamente.'),
          findsOneWidget,
        );
        expect(movimentacaoRepo.registrarCallCount, 1);

        // O rascunho/wizard precisa refletir o estado NOVO, não o que estava
        // na tela quando o formulário abriu — nunca basta consultar e
        // descartar o retorno (PROMPT 10.2.1, seção 4).
        await _voltar(tester);
        await _voltar(tester);
        expect(find.text('Status atual do patrimônio: Em uso.'), findsOneWidget);
      },
    );

    testWidgets('AJUSTE_INVENTARIO: trocar de setor NÃO oferece "Manter localização atual"', (tester) async {
      await _pumpEAbrirWizard(tester, movimentacaoRepo: FakeMovimentacaoRepository());
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      // Antes de trocar de setor: os 3 segmentos clássicos, com "Manter".
      expect(find.text('Manter atual'), findsOneWidget);

      await _selecionarSetorDestino(tester, 'GEVEV', obrigatorio: false);

      // Depois de trocar de setor: nunca "Manter" — só as duas opções que
      // deixam claro que a localização atual pertencia ao setor anterior.
      expect(find.text('Manter atual'), findsNothing);
      expect(find.text('Selecionar localização do novo setor'), findsOneWidget);
      expect(find.text('Não informar localização'), findsOneWidget);
    });

    testWidgets('AJUSTE_INVENTARIO: trocar de setor e definir localização envia o id do novo setor', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      await _selecionarSetorDestino(tester, 'GEVEV', obrigatorio: false);
      await _tocar(tester, find.text('Selecionar localização do novo setor'));
      await _tocar(tester, find.widgetWithText(DropdownButtonFormField<String?>, 'Localização de destino *'));
      await _tocar(tester, find.text('Sala 2').last);

      await _avancar(tester);
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.ultimoRegistrar!['destinoId'], 'setor-b');
      expect(repo.ultimoRegistrar!['localizacaoDestinoId'], 'loc-b1');
      expect(repo.ultimoRegistrar!['limparLocalizacao'], isFalse);
    });

    testWidgets('AJUSTE_INVENTARIO: trocar de setor e ficar sem localização — a RPC zera sozinha', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(tester, movimentacaoRepo: repo);
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      await _selecionarSetorDestino(tester, 'GEVEV', obrigatorio: false);
      // Não seleciona nenhuma localização — permanece em "Não informar
      // localização" (o padrão depois de trocar de setor).

      await _avancar(tester);
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.ultimoRegistrar!['destinoId'], 'setor-b');
      expect(repo.ultimoRegistrar!['localizacaoDestinoId'], isNull);
      // Nunca envia limparLocalizacao=true aqui: a RPC real já zera a
      // localização sozinha quando o setor muda sem localização nova (regra
      // "(b)" da função) — não é a mesma coisa que um "Limpar" explícito.
      expect(repo.ultimoRegistrar!['limparLocalizacao'], isFalse);
    });

    testWidgets('AJUSTE_INVENTARIO em patrimônio BAIXADO não oferece alteração de setor', (tester) async {
      await _pumpEAbrirWizard(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        patrimonios: [_patrimonioDetalhe(status: PatrimonioStatus.baixado)],
      );
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      expect(find.text('Setor de destino'), findsNothing);
      expect(find.text('Setor de destino *'), findsNothing);
    });

    testWidgets('AJUSTE_INVENTARIO em patrimônio BAIXADO não oferece alteração de localização', (tester) async {
      await _pumpEAbrirWizard(
        tester,
        movimentacaoRepo: FakeMovimentacaoRepository(),
        patrimonios: [_patrimonioDetalhe(status: PatrimonioStatus.baixado)],
      );
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      expect(find.text('Localização'), findsNothing);
      expect(find.byType(SegmentedButton<LocalizacaoEscolha>), findsNothing);
    });

    testWidgets('AJUSTE_INVENTARIO em patrimônio BAIXADO ainda permite campos informativos', (tester) async {
      final repo = FakeMovimentacaoRepository();
      await _pumpEAbrirWizard(
        tester,
        movimentacaoRepo: repo,
        patrimonios: [_patrimonioDetalhe(status: PatrimonioStatus.baixado)],
      );
      await _buscarESelecionarPatrimonio(tester);
      await _escolherTipo(tester, MovimentacaoTipo.ajusteInventario);
      await _avancar(tester);

      expect(find.widgetWithText(TextFormField, 'Motivo'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Observação'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Número do documento'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Número do chamado'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Motivo'), 'Conferência de inventário anual');
      await tester.pumpAndSettle();

      await _avancar(tester);
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar movimentação'));

      expect(repo.ultimoRegistrar!['destinoId'], isNull);
      expect(repo.ultimoRegistrar!['localizacaoDestinoId'], isNull);
      expect(repo.ultimoRegistrar!['limparLocalizacao'], isFalse);
      expect(repo.ultimoRegistrar!['motivo'], 'Conferência de inventário anual');
    });
  });
}
