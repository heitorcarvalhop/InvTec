import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/app/app.dart';
import 'package:invtec/core/shell/widgets/navigation_sidebar.dart';
import 'package:invtec/core/widgets/status_chip.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/dashboard/domain/dashboard_stats.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencias_list.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../features/auth/fake_auth_repository.dart';
import '../../features/dashboard/fake_dashboard_repository.dart';
import '../../features/movimentacoes/fake_movimentacao_repository.dart';
import '../../features/movimentacoes/sei/fake_documentos_sei_repository.dart';
import '../../features/patrimonios/fake_patrimonio_repository.dart';
import '../../features/patrimonios/fake_tipo_patrimonio_repository.dart';
import '../../features/setores/fake_setor_repository.dart';

/// PROMPT 11.3.9.2 — política de tamanho da janela do InvTec Windows.
///
/// A restrição REAL (mínimo de 1280x720 de ÁREA CLIENTE, tamanho inicial
/// 1440x810) vive no runner Win32 (`windows/runner/main.cpp` +
/// `WM_GETMINMAXINFO` em `win32_window.cpp`) e NÃO pode ser exercitada por
/// testes de widget — quem a verifica é `tool/verificar_janela_windows.ps1`,
/// que abre o executável de verdade. Estes testes garantem a outra metade do
/// contrato: nas dimensões que essa política PERMITE (mínimo, inicial,
/// maximizado, e o pior caso de um monitor 1080p a 150% de escala, cuja
/// janela maximizada tem só ~1264x641 de área cliente), nenhuma tela
/// principal estoura e a tabela de Pendências continua alcançável até a
/// última coluna.
const _minimo = Size(1280, 720);
const _inicial = Size(1440, 810);
const _maximizado1080p = Size(1920, 1009);
const _maximizado1080pEscala150 = Size(1264, 641);

Profile _perfil(String nome) => Profile(
  id: 'u',
  nome: nome,
  email: 'heitor@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _setores = [
  Setor(id: 's1', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(
    id: 's2',
    nome: 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
    sigla: 'GEASI',
    descricao: 'Descrição longa do setor para forçar largura em tabelas e cards de listagem do sistema',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
];

SeiItemPendente _item(int linha, SeiItemPendenciaStatus status) => SeiItemPendente(
  id: 'i$linha',
  documentoId: 'd1',
  linha: linha,
  numeroPatrimonio: SeiValorCorrigivel(original: '41570${90 + linha}'),
  origemTexto: const SeiValorCorrigivel(original: 'GETEC - Gerencia de Tecnologia'),
  destinoTexto: const SeiValorCorrigivel(original: 'Gerência de Licenciamento – GEASI'),
  numeroChamado: const SeiValorCorrigivel(original: '4556'),
  equipamentoTexto: const SeiValorCorrigivel(original: 'Monitor Positivo'),
  status: status,
  motivoCancelamento: status == SeiItemPendenciaStatus.cancelado ? 'motivo' : null,
  movimentacaoId: status == SeiItemPendenciaStatus.concluido ? 'mov' : null,
  criadoEm: DateTime(2026, 1, 1),
);

/// Sobe o app inteiro (shell + rotas reais) com fakes. O viewport de teste é
/// exatamente a ÁREA CLIENTE da janela Win32.
Future<void> _abrirApp(WidgetTester tester, Size tam, {String nome = 'Heitor Pereira'}) async {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fakeAuth = FakeAuthRepository(initialUserId: 'u', profileResolver: (_) => _perfil(nome));
  addTearDown(fakeAuth.dispose);

  final patrimonios = [
    for (var i = 0; i < 4; i++)
      PatrimonioDetalhe(
        patrimonio: Patrimonio(
          id: 'p$i',
          numeroPatrimonio: '415709$i',
          tipoId: 't1',
          status: PatrimonioStatus.disponivel,
          setorAtualId: 's2',
          descricao: 'Monitor Positivo 21 polegadas com descrição bem longa',
          marca: 'Positivo Tecnologia',
          modelo: 'Modelo XPTO-2000',
          responsavelAtual: 'Fulano de Tal da Silva Sauro',
          dataCadastro: DateTime(2026, 1, 1),
          atualizadoEm: DateTime(2026, 1, 1),
        ),
        tipoNome: 'Monitor',
        setorNome: _setores[1].nome,
        setorSigla: 'GEASI',
        localizacaoNome: 'Datacenter - Universitário',
      ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        dashboardRepositoryProvider.overrideWithValue(
          FakeDashboardRepository(
            stats: const DashboardStats(
              total: 1414,
              ativos: 1400,
              disponiveis: 300,
              emUso: 900,
              emprestados: 20,
              emManutencao: 10,
              baixados: 14,
            ),
          ),
        ),
        patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository(itens: patrimonios)),
        tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository()),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
        movimentacaoRepositoryProvider.overrideWithValue(
          FakeMovimentacaoRepository(
            itens: [
              MovimentacaoListagemItem(
                id: 'm1',
                tipo: MovimentacaoTipo.transferencia,
                patrimonioId: 'p1',
                patrimonioNumero: '4157090',
                patrimonioTipoNome: 'Monitor',
                setorOrigemNome: _setores[0].nome,
                setorDestinoNome: _setores[1].nome,
                setorOrigemSigla: 'GETEC',
                setorDestinoSigla: 'GEASI',
                localizacaoDestinoNome: 'Datacenter - Universitário',
                responsavelDestino: 'Fulano de Tal da Silva Sauro',
                autorNome: 'Heitor Pereira da Silva',
                dataMovimentacao: DateTime(2026, 1, 10, 14, 30),
              ),
            ],
          ),
        ),
        documentosSeiRepositoryProvider.overrideWithValue(
          FakeDocumentosSeiRepository(
            documentosIniciais: [
              // 1 concluído + 1 cancelado, nenhum pendente: a maior
              // situação textual da tabela ("Encerrado parcialmente").
              SeiDocumentoPendente.fromItens(
                id: 'd1',
                numeroDocumentoSei: '95955192',
                numeroProcesso: '202600017000011',
                numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
                assunto: 'Transferência de patrimônio com assunto bastante longo para a coluna',
                tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
                nomeArquivo: 'a.pdf',
                hashSha256: 'h',
                versao: 1,
                criadoEm: DateTime(2026, 1, 1),
                criadoPorId: 'u',
                criadoPorNome: 'Fulano',
                itens: [_item(1, SeiItemPendenciaStatus.concluido), _item(2, SeiItemPendenciaStatus.cancelado)],
              ),
            ],
          ),
        ),
      ],
      child: const InvTecApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Executa [acao] coletando os `RenderFlex overflowed` em vez de deixá-los
/// derrubar o teste na hora; a `FlutterError.onError` original é restaurada
/// ANTES de devolver (nunca deixada sobrescrita durante os `expect()`).
Future<List<String>> _coletandoOverflow(Future<void> Function() acao) async {
  final erros = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.toString().contains('overflowed')) {
      final local = RegExp(r'file:///[^\s]*?(lib/[^\s]+\.dart:\d+)').firstMatch(d.toString())?.group(1) ?? '?';
      erros.add('${d.summary} @ $local');
      return;
    }
    original?.call(d);
  };
  try {
    await acao();
  } finally {
    FlutterError.onError = original;
  }
  return erros;
}

Future<void> _irPara(WidgetTester tester, String rota, {bool pendencias = false}) async {
  if (rota != 'Dashboard') {
    await tester.tap(find.text(rota).first);
    await tester.pumpAndSettle();
  }
  if (pendencias) {
    await tester.tap(find.text('Pendências / Documentos SEI'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('PROMPT 11.3.9.2 — telas principais nas dimensões permitidas pela janela', () {
    for (final tam in [_minimo, _inicial, _maximizado1080p, _maximizado1080pEscala150]) {
      testWidgets('${tam.width.toInt()}x${tam.height.toInt()}: nenhuma tela principal estoura', (tester) async {
        final erros = await _coletandoOverflow(() async {
          await _abrirApp(tester, tam);
          for (final rota in ['Dashboard', 'Patrimônios', 'Movimentações', 'Setores', 'Configurações']) {
            await _irPara(tester, rota);
          }
          await _irPara(tester, 'Movimentações', pendencias: true);
        });
        expect(erros, isEmpty, reason: 'overflow em ${tam.width}x${tam.height}: $erros');
      });
    }

    testWidgets('nome de usuário muito longo no tamanho mínimo não estoura a topbar', (tester) async {
      final erros = await _coletandoOverflow(() async {
        await _abrirApp(
          tester,
          _minimo,
          nome: 'Heitor Pereira da Silva Sauro de Albuquerque Cavalcanti Nogueira Barros Filho Neto',
        );
      });
      expect(erros, isEmpty, reason: 'topbar: $erros');
    });
  });

  group('PROMPT 11.3.10 — tabela de Pendências simplificada cabe em todos os tamanhos da janela', () {
    for (final tam in [_minimo, _inicial, _maximizado1080p, _maximizado1080pEscala150]) {
      testWidgets(
        '${tam.width.toInt()}x${tam.height.toInt()}: Situação e o botão de abrir ficam dentro do Card, sem rolagem horizontal',
        (tester) async {
          await _abrirApp(tester, tam);
          await _irPara(tester, 'Movimentações', pendencias: true);

          final lista = find.byType(SeiPendenciasList);
          final card = tester.getRect(find.descendant(of: lista, matching: find.byType(Card)));
          final chip = tester.getRect(find.descendant(of: lista, matching: find.byType(StatusChip)));
          final cabecalho = tester.getRect(find.descendant(of: lista, matching: find.text('Situação')));
          final abrir = tester.getRect(find.descendant(of: lista, matching: find.byTooltip('Abrir documento')).first);

          expect(find.descendant(of: lista, matching: find.byType(Scrollbar)), findsNothing,
              reason: 'com poucas colunas a tabela não depende de rolagem horizontal');
          for (final rect in [chip, cabecalho, abrir]) {
            expect(rect.left, greaterThanOrEqualTo(card.left));
            expect(rect.right, lessThanOrEqualTo(card.right), reason: 'coluna cortada pela direita');
          }
          expect(card.right - abrir.right, greaterThan(0));

          // PROMPT 11.3.10.2 — as colunas de texto ficam separadas por pelo
          // menos 16px de folga (cabeçalhos em ordem e nunca sobrepostos).
          final cabecalhos = [
            for (final titulo in ['Documento SEI', 'Assunto', 'Progresso', 'Situação'])
              tester.getRect(find.descendant(of: lista, matching: find.text(titulo))),
          ];
          for (var i = 0; i < cabecalhos.length - 1; i++) {
            expect(cabecalhos[i + 1].left - cabecalhos[i].right, greaterThanOrEqualTo(16));
          }
        },
      );
    }
  });

  group('PROMPT 11.3.9.2 — transição maximizado → restaurado', () {
    testWidgets('restaurar para o mínimo mantém a aba, sem overflow, e a última coluna continua alcançável', (
      tester,
    ) async {
      final erros = await _coletandoOverflow(() async {
        await _abrirApp(tester, _maximizado1080p);
        await _irPara(tester, 'Movimentações', pendencias: true);

        // Restaurar: o viewport encolhe do maximizado para o mínimo (mesma
        // árvore de widgets, sem reconstruir o app).
        tester.view.physicalSize = _minimo;
        await tester.pumpAndSettle();
        // ... e maximizar de novo.
        tester.view.physicalSize = _maximizado1080p;
        await tester.pumpAndSettle();
        tester.view.physicalSize = _minimo;
        await tester.pumpAndSettle();
      });
      expect(erros, isEmpty, reason: 'overflow na transição: $erros');
      expect(find.byType(SeiPendenciasList), findsOneWidget, reason: 'a aba Pendências foi mantida');

      final card = tester.getRect(find.descendant(of: find.byType(SeiPendenciasList), matching: find.byType(Card)));
      final chip = tester.getRect(find.descendant(of: find.byType(SeiPendenciasList), matching: find.byType(StatusChip)));
      expect(chip.right, lessThanOrEqualTo(card.right));
    });
  });

  group('PROMPT 11.3.9.2 — sidebar na altura mínima', () {
    for (final tam in [_minimo, _maximizado1080pEscala150]) {
      testWidgets('${tam.width.toInt()}x${tam.height.toInt()}: todos os itens (incl. "Sair") cabem sem rolar', (
        tester,
      ) async {
        await _abrirApp(tester, tam);

        for (final rotulo in ['Dashboard', 'Patrimônios', 'Movimentações', 'Setores', 'Configurações', 'Sair']) {
          final rect = tester.getRect(find.text(rotulo).first);
          expect(rect.bottom, lessThanOrEqualTo(tam.height), reason: '"$rotulo" cortado na altura ${tam.height}');
        }
        final sidebarScroll = tester.state<ScrollableState>(
          find.descendant(of: find.byType(NavigationSidebar), matching: find.byType(Scrollable)).first,
        );
        expect(sidebarScroll.position.maxScrollExtent, 0, reason: 'nesta altura a sidebar não precisa nem rolar');
      });
    }
  });
}
