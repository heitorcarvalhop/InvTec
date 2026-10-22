import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/compact_icon_button.dart';
import 'package:invtec/features/administracao/data/usuario_admin_repository_supabase.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/dashboard/domain/movimentacao_resumo.dart';
import 'package:invtec/features/dashboard/presentation/dashboard_page.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/notificacoes/data/app_notification_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/presentation/widgets/patrimonio_mobile_list.dart';

import '../administracao/fake_usuario_admin_repository.dart';
import '../auth/fake_auth_repository.dart';
import '../auth/fake_permissions_repository.dart';
import '../notificacoes/fake_app_notification_repository.dart';
import '../patrimonios/fake_patrimonio_repository.dart';
import 'fake_dashboard_repository.dart';

/// Fase 2 — densidade mobile: larguras pedidas no relatório (seção 15),
/// cobrindo só os componentes alterados nesta fase (nunca um smoke test
/// genérico de toda a suíte). `360`/`412` são extremos realistas de celular
/// (Android pequeno/grande); `390` já tinha cobertura em outros arquivos do
/// projeto, repetida aqui só para os componentes do Dashboard.
const _largurasMobile = [360.0, 390.0, 412.0];

/// Largura de referência para confirmar que desktop/tablet NÃO mudou.
const _larguraDesktop = 1280.0;

Profile _profile() => Profile(
  id: 'fake-user-id',
  nome: 'Usuário de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
);

void _definirTamanho(WidgetTester tester, double largura) {
  tester.view.physicalSize = Size(largura, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _movimentacaoRecente = MovimentacaoResumo(
  id: 'mov-1',
  tipo: MovimentacaoTipo.transferencia,
  patrimonioLabel: '00012345',
  origemNome: 'Gerência de Tecnologia da Informação',
  origemSigla: 'GTI',
  destinoNome: 'Gerência de Licenciamento Ambiental',
  destinoSigla: 'GLA',
  autorNome: 'Heitor Pereira',
  // Local (não `.utc`) de propósito: `_MovementRow._formatarData` chama
  // `.toLocal()`, então um horário UTC literal mudaria de hora/dia
  // dependendo do fuso da máquina — aqui o valor já nasce "local".
  dataMovimentacao: DateTime(2026, 1, 10, 14, 30),
);

/// Roda [DashboardPage] em [largura], falhando o teste se o `FlutterError`
/// global reportar overflow ou qualquer outra exceção durante a
/// renderização — mesmo padrão de smoke test já usado em
/// `patrimonio_responsive_smoke_test.dart`.
Future<void> _pumpDashboardSemOverflow(
  WidgetTester tester,
  double largura,
) async {
  _definirTamanho(tester, largura);

  final fakeAuth = FakeAuthRepository(
    initialUserId: 'fake-user-id',
    profileResolver: (_) => _profile(),
  );
  addTearDown(fakeAuth.dispose);

  final erros = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (details) => erros.add(details.toString());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        permissionsRepositoryProvider.overrideWithValue(
          FakePermissionsRepository.paraPerfil(ProfilePerfil.admin),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(
            totalPatrimonios: 1414,
            totalSetores: 4,
            totalLocalizacoes: 15,
            totalTipos: 16,
            movimentacoesUltimos30Dias: 23,
            movimentacoesRecentes: [_movimentacaoRecente],
          ),
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

  FlutterError.onError = anterior;

  expect(
    erros.where((e) => e.toLowerCase().contains('overflow')),
    isEmpty,
    reason: 'overflow em ${largura}px: ${erros.join('\n')}',
  );
  expect(tester.takeException(), isNull, reason: 'exceção em ${largura}px');
}

void main() {
  group('Dashboard mobile — Ações rápidas sem overflow e sem ação escondida', () {
    for (final largura in _largurasMobile) {
      testWidgets('todas as 5 ações continuam visíveis em ${largura}px', (
        tester,
      ) async {
        await _pumpDashboardSemOverflow(tester, largura);

        // Nenhuma ação foi movida para menu/escondida — as 5 continuam
        // como texto visível na tela (seção 7 do pedido: "não esconder
        // ações importantes arbitrariamente").
        expect(find.text('Novo patrimônio'), findsOneWidget);
        expect(find.text('Registrar movimentação'), findsOneWidget);
        expect(find.text('Importar patrimônios'), findsOneWidget);
        expect(find.text('Consultar patrimônio'), findsOneWidget);
        expect(find.text('Documento SEI'), findsOneWidget);
      });
    }

    testWidgets(
      'em ${_largurasMobile.first}px, as ações formam uma grade de 2 colunas (não 5 linhas)',
      (tester) async {
        await _pumpDashboardSemOverflow(tester, _largurasMobile.first);

        // "Novo patrimônio" e "Registrar movimentação" (1a e 2a ação) ficam
        // lado a lado na mesma linha — prova de que a grade de 2 colunas
        // está em uso, e não 5 botões empilhados verticalmente.
        final topoAcao1 = tester.getTopLeft(find.text('Novo patrimônio')).dy;
        final topoAcao2 = tester
            .getTopLeft(find.text('Registrar movimentação'))
            .dy;
        expect(
          topoAcao1,
          closeTo(topoAcao2, 2),
          reason: '1a e 2a ação deveriam estar na mesma linha (2 colunas)',
        );

        // "Importar patrimônios" (3a ação) cai para a linha seguinte.
        final topoAcao3 = tester
            .getTopLeft(find.text('Importar patrimônios'))
            .dy;
        expect(
          topoAcao3,
          greaterThan(topoAcao1 + 10),
          reason: '3a ação deveria estar numa linha abaixo das 2 primeiras',
        );

        // Dentro do próprio botão, o ícone fica ACIMA do texto (layout
        // vertical compacto da grade mobile), nunca ao lado dele.
        final topoIcone = tester
            .getTopLeft(find.byIcon(Icons.add_circle_outline))
            .dy;
        expect(
          topoIcone,
          lessThan(topoAcao1 - 4),
          reason: 'ícone deveria estar acima do texto no botão mobile',
        );
      },
    );

    testWidgets(
      'em desktop (${_larguraDesktop}px), o botão continua ícone-ao-lado-do-texto (não ícone-acima)',
      (tester) async {
        await _pumpDashboardSemOverflow(tester, _larguraDesktop);

        // Nenhuma regressão no desktop: o ícone fica na mesma linha do
        // texto (layout original em `Row`), nunca empilhado acima dele
        // (isso só acontece na grade mobile da Fase 2).
        final topoIcone = tester
            .getTopLeft(find.byIcon(Icons.add_circle_outline))
            .dy;
        final topoTexto = tester.getTopLeft(find.text('Novo patrimônio')).dy;
        expect(
          topoIcone,
          closeTo(topoTexto, 6),
          reason:
              'ícone deveria estar ao lado do texto (mesma linha) no desktop, não acima dele',
        );
      },
    );
  });

  group('Dashboard mobile — Movimentações recentes sem perder informação', () {
    for (final largura in _largurasMobile) {
      testWidgets(
        'card da movimentação mostra todas as informações em ${largura}px',
        (tester) async {
          await _pumpDashboardSemOverflow(tester, largura);

          expect(find.text('00012345'), findsOneWidget);
          expect(find.text('Transferência'), findsOneWidget);
          expect(find.text('GTI → GLA'), findsOneWidget);
          expect(find.text('por Heitor Pereira'), findsOneWidget);
          expect(find.text('10/01/2026 14:30'), findsOneWidget);
        },
      );
    }
  });

  group(
    'CompactIconButton — touch target seguro no mobile, inalterado no desktop',
    () {
      Future<void> pump(WidgetTester tester, double largura) async {
        _definirTamanho(tester, largura);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: CompactIconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      for (final largura in _largurasMobile) {
        testWidgets('área de toque >= 44x44 em ${largura}px (mobile)', (
          tester,
        ) async {
          await pump(tester, largura);
          final tamanho = tester.getSize(find.byType(IconButton));
          expect(tamanho.width, greaterThanOrEqualTo(44));
          expect(tamanho.height, greaterThanOrEqualTo(44));
        });
      }

      testWidgets(
        'mantém 32x32 no desktop (comportamento original preservado)',
        (tester) async {
          await pump(tester, _larguraDesktop);
          final tamanho = tester.getSize(find.byType(IconButton));
          expect(tamanho.width, 32);
          expect(tamanho.height, 32);
        },
      );
    },
  );

  group('PatrimonioCard — botão Editar com touch target seguro no mobile', () {
    PatrimonioDetalhe item() => PatrimonioDetalhe(
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
      setorNome: 'Setor de Teste',
    );

    Future<void> pump(WidgetTester tester, double largura) async {
      _definirTamanho(tester, largura);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatrimonioCard(
              detalhe: item(),
              canManage: true,
              onTap: () {},
              onEdit: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final largura in _largurasMobile) {
      testWidgets('botão Editar tem área de toque >= 44x44 em ${largura}px', (
        tester,
      ) async {
        await pump(tester, largura);
        final editar = find.byTooltip('Editar');
        final tamanho = tester.getSize(
          find.descendant(of: editar, matching: find.byType(IconButton)).first,
        );
        expect(tamanho.width, greaterThanOrEqualTo(44));
        expect(tamanho.height, greaterThanOrEqualTo(44));
      });
    }

    testWidgets(
      'mantém 36x36 no desktop (mesmo card usado pela grade "Cards")',
      (tester) async {
        await pump(tester, _larguraDesktop);
        final editar = find.byTooltip('Editar');
        final tamanho = tester.getSize(
          find.descendant(of: editar, matching: find.byType(IconButton)).first,
        );
        expect(tamanho.width, 36);
        expect(tamanho.height, 36);
      },
    );
  });
}
