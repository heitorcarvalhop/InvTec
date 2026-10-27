import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/presentation/inventario_rapido_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../localizacoes/fake_localizacao_repository.dart';
import 'fake_mobile_scanner_platform.dart';
import 'fake_patrimonio_repository.dart';

PatrimonioDetalhe _patrimonio({
  required String id,
  String? numero,
  String? localizacaoAtualId,
  String? localizacaoNome,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-1',
      localizacaoAtualId: localizacaoAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'GETEC',
    localizacaoNome: localizacaoNome,
  );
}

class _Ambiente {
  _Ambiente(this.router, this.fakePlatform);
  final GoRouter router;
  final FakeMobileScannerPlatform fakePlatform;
}

Future<_Ambiente> _pumpInventarioRapidoPage(
  WidgetTester tester, {
  required FakePatrimonioRepository patrimonioRepo,
  List<Localizacao>? localizacoes,
}) async {
  final fakePlatform = FakeMobileScannerPlatform();
  MobileScannerPlatform.instance = fakePlatform;

  final router = GoRouter(
    initialLocation: '/inventario-rapido',
    routes: [
      GoRoute(
        path: '/inventario-rapido',
        builder: (context, state) => const InventarioRapidoPage(),
      ),
      GoRoute(
        path: '/patrimonios',
        builder: (context, state) => const Text('PAGINA_PATRIMONIOS'),
      ),
      GoRoute(
        path: '/patrimonios/:id',
        builder: (context, state) =>
            Text('detalhe:${state.pathParameters['id']}'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
        localizacaoRepositoryProvider.overrideWithValue(
          FakeLocalizacaoRepository(
            localizacoes:
                localizacoes ??
                [
                  Localizacao(
                    id: 'loc-A',
                    setorId: 'setor-1',
                    nome: 'Sala A',
                    ativo: true,
                    criadoEm: DateTime(2026, 1, 1),
                  ),
                ],
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return _Ambiente(router, fakePlatform);
}

Future<void> _iniciarSessao(WidgetTester tester, {String localizacao = 'Sala A'}) async {
  await tester.tap(find.byType(DropdownButtonFormField<Localizacao>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(localizacao).last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Iniciar conferência'));
  await tester.pumpAndSettle();
}

void main() {
  group('seleção de localização', () {
    testWidgets('exige escolher uma localização antes de iniciar', (tester) async {
      await _pumpInventarioRapidoPage(
        tester,
        patrimonioRepo: FakePatrimonioRepository(),
      );

      final botao = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Iniciar conferência'),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('inicia a sessão com a localização escolhida', (tester) async {
      await _pumpInventarioRapidoPage(
        tester,
        patrimonioRepo: FakePatrimonioRepository(),
      );

      await _iniciarSessao(tester);

      expect(find.text('Inventário — Sala A'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3)); // leituras/encontrados/pendências
    });
  });

  group('sessão ativa — leituras', () {
    testWidgets(
      'escanear um patrimônio encontrado conta em "Encontrados", nunca '
      'em "Pendências"',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '3583777')],
        );
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester);

        ambiente.fakePlatform.detectar('03583777');
        await tester.pumpAndSettle();

        expect(find.text('Nº 3583777'), findsOneWidget);
        // Total=1, Encontrados=1, Pendências=0.
        expect(find.text('1'), findsNWidgets(2));
        expect(find.text('0'), findsOneWidget);
      },
    );

    testWidgets(
      'escanear o MESMO patrimônio de novo nunca duplica a linha (zero à '
      'esquerda incluso)',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester);

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();
        ambiente.fakePlatform.detectar('042');
        await tester.pumpAndSettle();

        expect(find.text('Nº 42'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(2)); // Total=1, Encontrados=1
      },
    );

    testWidgets('não encontrado conta como pendência, com ação "tentar de novo"', (
      tester,
    ) async {
      final repo = FakePatrimonioRepository();
      final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
      await _iniciarSessao(tester);

      ambiente.fakePlatform.detectar('555555');
      await tester.pumpAndSettle();

      expect(find.text('555555'), findsOneWidget);
      expect(find.byTooltip('Tentar novamente'), findsOneWidget);
      // Total=1, Pendências=1, Encontrados=0.
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('remover uma leitura tira a linha e atualiza os contadores', (
      tester,
    ) async {
      final repo = FakePatrimonioRepository();
      final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
      await _iniciarSessao(tester);

      ambiente.fakePlatform.detectar('555555');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remover leitura'));
      await tester.pumpAndSettle();

      expect(find.text('555555'), findsNothing);
      expect(find.text('0'), findsNWidgets(3));
    });

    testWidgets(
      '"tentar de novo" corrige uma pendência depois que o patrimônio '
      'passa a ser encontrado',
      (tester) async {
        final repo = _RepositorioComFalhaNaPrimeiraBuscaAtual(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester);

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();
        expect(find.byTooltip('Tentar novamente'), findsOneWidget);

        await tester.tap(find.byTooltip('Tentar novamente'));
        await tester.pumpAndSettle();

        expect(find.text('Nº 42'), findsOneWidget);
        expect(find.byTooltip('Tentar novamente'), findsNothing);
      },
    );

    testWidgets(
      'mostra divergência quando a localização cadastrada é diferente '
      'da conferida',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [
            _patrimonio(
              id: 'abc',
              numero: '42',
              localizacaoAtualId: 'loc-B',
              localizacaoNome: 'Sala B',
            ),
          ],
        );
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester); // sessão em "Sala A"

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Cadastrado em "Sala B"'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tocar numa leitura encontrada abre o detalhe do patrimônio',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester);

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Nº 42'));
        await tester.pumpAndSettle();

        expect(find.text('detalhe:abc'), findsOneWidget);
      },
    );
  });

  group('saída da sessão', () {
    testWidgets(
      'sair sem leituras não pede confirmação',
      (tester) async {
        await _pumpInventarioRapidoPage(tester, patrimonioRepo: FakePatrimonioRepository());
        await _iniciarSessao(tester);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('PAGINA_PATRIMONIOS'), findsOneWidget);
      },
    );

    testWidgets(
      'sair com leituras pede confirmação; "Continuar editando" mantém a sessão',
      (tester) async {
        final repo = FakePatrimonioRepository();
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester);

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('Encerrar sessão de inventário?'), findsOneWidget);
        await tester.tap(find.text('Continuar editando'));
        await tester.pumpAndSettle();

        expect(find.text('Inventário — Sala A'), findsOneWidget);
      },
    );

    testWidgets(
      'confirmar "Descartar" encerra a sessão e volta para Patrimônios',
      (tester) async {
        final repo = FakePatrimonioRepository();
        final ambiente = await _pumpInventarioRapidoPage(tester, patrimonioRepo: repo);
        await _iniciarSessao(tester);

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Descartar'));
        await tester.pumpAndSettle();

        expect(find.text('PAGINA_PATRIMONIOS'), findsOneWidget);
      },
    );
  });
}

class _RepositorioComFalhaNaPrimeiraBuscaAtual extends FakePatrimonioRepository {
  _RepositorioComFalhaNaPrimeiraBuscaAtual({super.itens});
  bool _primeiraChamada = true;

  @override
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(
    String codigo,
  ) async {
    if (_primeiraChamada) {
      _primeiraChamada = false;
      throw const AppException('Falha simulada de rede.');
    }
    return super.buscarPorTombamentoAtualExato(codigo);
  }
}
