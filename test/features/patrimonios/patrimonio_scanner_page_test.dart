import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_scanner_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../auth/fake_auth_repository.dart';
import '../auth/fake_permissions_repository.dart';
import 'fake_mobile_scanner_platform.dart';
import 'fake_patrimonio_repository.dart';

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

PatrimonioDetalhe _patrimonio({required String id, String? numero}) {
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
    tipoNome: 'Notebook',
    setorNome: 'GETEC',
  );
}

/// Mesmo truque de `_RepositorioComPortoesListar` em
/// `patrimonios_controller_test.dart`: estende o fake de verdade (em vez
/// de reimplementar toda a interface) só para represar a chamada a
/// [buscarPorTombamentoAtualExato] — usado para provar o debounce ("uma
/// leitura repetida nunca dispara uma segunda consulta").
class _RepositorioComPortaNaBuscaAtual extends FakePatrimonioRepository {
  _RepositorioComPortaNaBuscaAtual({super.itens});

  Completer<void>? liberarProximaChamada;

  /// Incrementado ANTES do portão (ao contrário do
  /// `buscarPorTombamentoAtualExatoCallCount` da classe-base, que só
  /// soma depois que a chamada represada é liberada) — é o que prova que
  /// uma segunda leitura da mesma etiqueta NUNCA chega a iniciar uma nova
  /// chamada enquanto a primeira ainda está represada.
  int chamadasIniciadas = 0;

  @override
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(
    String codigo,
  ) async {
    chamadasIniciadas++;
    final porta = liberarProximaChamada;
    if (porta != null) await porta.future;
    return super.buscarPorTombamentoAtualExato(codigo);
  }
}

/// A PRIMEIRA chamada a [buscarPorTombamentoAtualExato] lança (simula uma
/// falha de rede passageira); as demais funcionam normalmente — usado
/// para provar que "Tentar novamente" (ver
/// [ScannerResultadoTipo.falhaConsulta]) realmente permite reler a mesma
/// etiqueta com sucesso depois.
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

class _Ambiente {
  _Ambiente(this.router, this.fakePlatform);
  final GoRouter router;
  final FakeMobileScannerPlatform fakePlatform;
}

Future<_Ambiente> _pumpScannerPage(
  WidgetTester tester, {
  required ProfilePerfil perfil,
  required FakePatrimonioRepository patrimonioRepo,
  MobileScannerException? erroAoIniciar,
}) async {
  final fakePlatform = FakeMobileScannerPlatform(erroAoIniciar: erroAoIniciar);
  MobileScannerPlatform.instance = fakePlatform;

  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(perfil),
  );
  addTearDown(fakeAuth.dispose);

  final router = GoRouter(
    initialLocation: '/escanear',
    routes: [
      GoRoute(
        path: '/escanear',
        builder: (context, state) => const PatrimonioScannerPage(),
      ),
      GoRoute(
        path: '/patrimonios/novo',
        builder: (context, state) =>
            Text('cadastro:${state.uri.queryParameters['tombamento']}'),
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
        authRepositoryProvider.overrideWithValue(fakeAuth),
        permissionsRepositoryProvider.overrideWithValue(
          FakePermissionsRepository.paraPerfil(perfil),
        ),
        patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return _Ambiente(router, fakePlatform);
}

void main() {
  group('leitura pela câmera', () {
    testWidgets(
      'detecta o tombamento atual (com zero à esquerda na etiqueta) e '
      'abre o detalhe do patrimônio existente',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '3583777')],
        );
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('03583777');
        await tester.pumpAndSettle();

        expect(find.text('detalhe:abc'), findsOneWidget);
      },
    );

    testWidgets(
      'não encontrado + permissão de cadastro: oferece "Cadastrar '
      'patrimônio" e pré-preenche o tombamento lido no formulário',
      (tester) async {
        final repo = FakePatrimonioRepository();
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('555555');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Nenhum patrimônio encontrado para "555555"'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Cadastrar patrimônio'));
        await tester.pumpAndSettle();

        expect(find.text('cadastro:555555'), findsOneWidget);
      },
    );

    testWidgets(
      'não encontrado SEM permissão de cadastro nunca oferece "Cadastrar '
      'patrimônio"',
      (tester) async {
        final repo = FakePatrimonioRepository();
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.consulta,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('555555');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Nenhum patrimônio encontrado'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Cadastrar patrimônio'),
          findsNothing,
        );
        expect(
          find.textContaining('não tem permissão para cadastrar'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'nunca dispara uma segunda consulta para a MESMA leitura repetida '
      'enquanto a primeira ainda está em voo',
      (tester) async {
        final repo = _RepositorioComPortaNaBuscaAtual(
          itens: [_patrimonio(id: 'abc', numero: '777')],
        )..liberarProximaChamada = Completer<void>();
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('777');
        await tester.pump();
        // mesma etiqueta ainda enquadrada -> onDetect dispara de novo antes
        // da primeira consulta responder.
        ambiente.fakePlatform.detectar('777');
        await tester.pump();

        expect(repo.chamadasIniciadas, 1);

        repo.liberarProximaChamada!.complete();
        await tester.pumpAndSettle();

        expect(find.text('detalhe:abc'), findsOneWidget);
      },
    );

    testWidgets(
      'mais de um patrimônio com o mesmo tombamento (ambíguo) deixa a '
      'escolha para o usuário, nunca abre um sozinho',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [
            _patrimonio(id: 'p1', numero: '42'),
            _patrimonio(id: 'p2', numero: '042'),
          ],
        );
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        expect(find.textContaining('Mais de um patrimônio corresponde'), findsOneWidget);
        expect(find.text('detalhe:p1'), findsNothing);
        expect(find.text('detalhe:p2'), findsNothing);

        await tester.tap(find.text('Nº 42'));
        await tester.pumpAndSettle();

        expect(find.text('detalhe:p1'), findsOneWidget);
      },
    );
  });

  group('acesso insuficiente / falha de consulta nunca oferecem cadastro', () {
    testWidgets(
      'acesso insuficiente mostra aviso próprio e NUNCA o botão '
      '"Cadastrar patrimônio", mesmo com permissão de patrimonio.create',
      (tester) async {
        final repo = FakePatrimonioRepository(
          erroBuscarTombamentoAtualExato: const AcessoInsuficienteException(
            'Você não possui permissão para realizar esta operação.',
          ),
        );
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('não tem permissão para confirmar'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Cadastrar patrimônio'),
          findsNothing,
        );
        expect(
          find.textContaining('Nenhum patrimônio encontrado'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'falha de consulta (rede) mostra aviso próprio, nunca "não '
      'encontrado" nem o botão "Cadastrar patrimônio", e "tentar de novo" '
      'permite reler a MESMA etiqueta',
      (tester) async {
        final repo = _RepositorioComFalhaNaPrimeiraBuscaAtual(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Não foi possível consultar o patrimônio'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Cadastrar patrimônio'),
          findsNothing,
        );
        expect(
          find.textContaining('Nenhum patrimônio encontrado'),
          findsNothing,
        );

        // "Tentar novamente" (ver [ScannerResultadoTipo.falhaConsulta])
        // religa a câmera e limpa o travamento de debounce — a MESMA
        // etiqueta "42" pode ser relida (desta vez sem falha simulada).
        await tester.tap(find.widgetWithText(OutlinedButton, 'Tentar novamente'));
        await tester.pumpAndSettle();

        ambiente.fakePlatform.detectar('42');
        await tester.pumpAndSettle();

        expect(find.text('detalhe:abc'), findsOneWidget);
      },
    );
  });

  group('encerramento/reabertura da câmera (ciclo de vida do app)', () {
    testWidgets(
      'app indo para segundo plano para a câmera; voltar ao primeiro '
      'plano religa, enquanto nenhum resultado está sendo exibido',
      (tester) async {
        final repo = FakePatrimonioRepository();
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        expect(ambiente.fakePlatform.startCallCount, 1);
        expect(ambiente.fakePlatform.stopCallCount, 0);

        // Sequência real do Android ao perder o foco: sempre passa por
        // `inactive` ANTES de `paused` — mesma transição que o próprio
        // `mobile_scanner` usa para decidir quando parar (ver comentário
        // de `didChangeAppLifecycleState`).
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        expect(ambiente.fakePlatform.stopCallCount, 1);

        // E sempre passa de novo por `inactive` ANTES de `resumed` ao
        // voltar — só `resumed` religa.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(ambiente.fakePlatform.startCallCount, 2);
      },
    );

    testWidgets(
      'voltar do segundo plano NUNCA religa a câmera por baixo de um '
      'resultado ainda exibido (aguardando "Escanear novamente" '
      'explícito)',
      (tester) async {
        final repo = FakePatrimonioRepository();
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
        );

        ambiente.fakePlatform.detectar('555555');
        await tester.pumpAndSettle();
        expect(find.textContaining('Nenhum patrimônio encontrado'), findsOneWidget);

        final startsAntesDoBackground = ambiente.fakePlatform.startCallCount;

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();

        // nenhuma chamada extra a start() — a câmera continua parada,
        // exatamente como o resultado exibido exige.
        expect(ambiente.fakePlatform.startCallCount, startsAntesDoBackground);
        expect(find.textContaining('Nenhum patrimônio encontrado'), findsOneWidget);
      },
    );
  });

  group('permissão de câmera negada / entrada manual', () {
    testWidgets(
      'mostra o aviso de permissão negada mas a entrada manual continua '
      'funcionando normalmente',
      (tester) async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final ambiente = await _pumpScannerPage(
          tester,
          perfil: ProfilePerfil.admin,
          patrimonioRepo: repo,
          erroAoIniciar: const MobileScannerException(
            errorCode: MobileScannerErrorCode.permissionDenied,
          ),
        );
        expect(find.textContaining('Permissão de câmera negada'), findsOneWidget);
        expect(ambiente.fakePlatform.startCallCount, 1);

        await tester.enterText(find.byType(TextField), '42');
        await tester.tap(find.widgetWithText(FilledButton, 'Buscar'));
        await tester.pumpAndSettle();

        expect(find.text('detalhe:abc'), findsOneWidget);
      },
    );
  });
}
