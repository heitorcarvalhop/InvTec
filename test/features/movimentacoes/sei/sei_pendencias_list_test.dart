import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/status_chip.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencias_list.dart';

/// PROMPT 11.3.5.3 — reproduz o bug relatado NA TELA: a tabela principal da
/// aba Pendências mostrava todos os contadores zerados para o Despacho
/// 577/2026/SEMAD/GETEC-12014 (documento SEI 95955192), mesmo com a view
/// `documentos_sei_com_situacao` já retornando 33/33/0/0 corretamente. Usa
/// `SeiDocumentoPendente.fromJson` com um JSON no formato EXATO que essa
/// view devolve (mesmo helper de `sei_documento_pendente_test.dart`), para
/// que o teste passe pelo MESMO caminho de parsing que a UI real usa.
Map<String, dynamic> _linhaDaViewSemItens({
  required int totalItens,
  required int totalPendentes,
  required int totalConcluidos,
  required int totalCancelados,
  required String situacao,
  String? assunto,
}) {
  return {
    'id': '4006bdf4-6927-444e-912b-0e4d42653500',
    'numero_documento_sei': '95955192',
    'numero_processo': '202600017000011',
    'numero_documento_formatado': '577/2026/SEMAD/GETEC-12014',
    'assunto': assunto,
    'tipo_operacao_pretendida': 'TRANSFERENCIA',
    'nome_arquivo': 'despacho.pdf',
    'hash_sha256': 'hash',
    'versao': 1,
    'criado_em': '2026-09-22T10:00:00Z',
    'criado_por': 'user-1',
    'atualizado_em': null,
    'total_itens': totalItens,
    'total_pendentes': totalPendentes,
    'total_concluidos': totalConcluidos,
    'total_cancelados': totalCancelados,
    'situacao': situacao,
    'autor': {'nome': 'Fulano'},
  };
}

SeiDocumentoPendente _doc({
  int totalItens = 33,
  int totalPendentes = 33,
  int totalConcluidos = 0,
  int totalCancelados = 0,
  String situacao = 'PENDENTE',
  String? assunto,
}) {
  return SeiDocumentoPendente.fromJson(
    _linhaDaViewSemItens(
      totalItens: totalItens,
      totalPendentes: totalPendentes,
      totalConcluidos: totalConcluidos,
      totalCancelados: totalCancelados,
      situacao: situacao,
      assunto: assunto,
    ),
  );
}

void _definirTamanho(WidgetTester tester, Size tamanho) {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  List<SeiDocumentoPendente> itens, {
  ValueChanged<SeiDocumentoPendente>? onAbrir,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SeiPendenciasList(itens: itens, onAbrir: onAbrir ?? (_) {}),
        ),
      ),
    ),
  );
}

/// Bombeia coletando os overflows em vez de deixar o framework só imprimi-los
/// — e restaura o handler ANTES de qualquer `expect` (um `onError` deixado
/// sobrescrito faz o teste "não completar").
Future<List<String>> _pumpColetandoOverflow(WidgetTester tester, List<SeiDocumentoPendente> itens) async {
  final erros = <String>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) => erros.add(d.toString());
  await _pump(tester, itens);
  FlutterError.onError = anterior;
  return erros.where((e) => e.toLowerCase().contains('overflow')).toList();
}

void main() {
  group('PROMPT 11.3.5.3 — SeiPendenciasList mostra os contadores reais da view', () {
    testWidgets('Despacho 577 — 33 itens pendentes exibe "33 pendentes · 0 concluídos" e Pendente', (tester) async {
      _definirTamanho(tester, const Size(1280, 720));
      await _pump(tester, [_doc()]);

      expect(find.text('577/2026/SEMAD/GETEC-12014'), findsOneWidget);
      // Vem dos totais da view — nunca de `itens`, que é [] na listagem.
      expect(find.text('33 pendentes · 0 concluídos'), findsOneWidget);
      expect(find.text('Pendente'), findsOneWidget);
    });

    testWidgets('parcialmente concluído/cancelado exibe pendentes, concluídos e cancelados', (tester) async {
      _definirTamanho(tester, const Size(1280, 720));
      await _pump(tester, [
        _doc(
          totalItens: 10,
          totalPendentes: 4,
          totalConcluidos: 3,
          totalCancelados: 3,
          situacao: 'PARCIALMENTE_CONCLUIDO',
        ),
      ]);

      expect(find.text('4 pendentes · 3 concluídos · 3 cancelados'), findsOneWidget);
      expect(find.text('Parcialmente concluído'), findsOneWidget);
    });

    testWidgets('singular, e sem "cancelados" quando não há nenhum', (tester) async {
      _definirTamanho(tester, const Size(1280, 720));
      await _pump(tester, [
        _doc(
          totalItens: 2,
          totalPendentes: 1,
          totalConcluidos: 1,
          totalCancelados: 0,
          situacao: 'PARCIALMENTE_CONCLUIDO',
        ),
      ]);

      expect(find.text('1 pendente · 1 concluído'), findsOneWidget);
    });
  });

  group('PROMPT 11.3.10 — colunas simplificadas e abertura do detalhe', () {
    testWidgets('cabeçalho: só Documento SEI, Assunto, Progresso e Situação', (tester) async {
      _definirTamanho(tester, const Size(1280, 720));
      await _pump(tester, [_doc(assunto: 'Transferência de equipamentos')]);

      for (final coluna in ['Documento SEI', 'Assunto', 'Progresso', 'Situação']) {
        expect(find.text(coluna), findsOneWidget, reason: coluna);
      }
      for (final removida in ['Tipo', 'Processo', 'Cadastrado em', 'Itens', 'Pendentes', 'Concluídos', 'Cancelados']) {
        expect(find.text(removida), findsNothing, reason: '$removida saiu da listagem');
      }
      expect(find.text('Transferência de equipamentos'), findsOneWidget);
      // Processo e data de cadastro ficam no detalhe, não na linha.
      expect(find.text('202600017000011'), findsNothing);
    });

    testWidgets('clicar na linha e clicar no botão abrem o MESMO documento, uma vez cada', (tester) async {
      _definirTamanho(tester, const Size(1280, 720));
      final abertos = <String>[];
      await _pump(tester, [_doc()], onAbrir: (d) => abertos.add(d.id));

      await tester.tap(find.text('577/2026/SEMAD/GETEC-12014'));
      await tester.pump();
      expect(abertos, ['4006bdf4-6927-444e-912b-0e4d42653500']);

      await tester.tap(find.byTooltip('Abrir documento'));
      await tester.pump();
      expect(abertos, hasLength(2), reason: 'o botão não dispara também o clique da linha');
    });

    testWidgets('na janela do Windows (1280x720) cabe sem rolagem horizontal, com a Situação dentro do Card', (
      tester,
    ) async {
      _definirTamanho(tester, const Size(1280, 720));
      final overflows = await _pumpColetandoOverflow(tester, [
        _doc(situacao: 'PARCIALMENTE_CONCLUIDO', totalPendentes: 1, totalConcluidos: 32),
      ]);

      expect(overflows, isEmpty);
      expect(find.byType(Scrollbar), findsNothing, reason: 'poucas colunas: não depende de rolagem horizontal');
      final card = tester.getRect(find.byType(Card));
      final chip = tester.getRect(find.byType(StatusChip));
      expect(chip.left, greaterThanOrEqualTo(card.left));
      expect(chip.right, lessThanOrEqualTo(card.right));
    });

    testWidgets('abaixo da largura da tabela (800) mantém a barra horizontal visível e a Situação alcançável', (
      tester,
    ) async {
      _definirTamanho(tester, const Size(800, 600));
      await _pump(tester, [_doc()]);

      final barra = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(barra.thumbVisibility, isTrue);
      expect(barra.controller, isNotNull);

      final scrollable = find.descendant(of: find.byType(SeiPendenciasList), matching: find.byType(Scrollable));
      final state = tester.state<ScrollableState>(scrollable.first);
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(find.byType(StatusChip)).dx, lessThanOrEqualTo(800));
    });

    testWidgets('mobile (360x640): card compacto com número, assunto, progresso e situação, sem overflow', (
      tester,
    ) async {
      _definirTamanho(tester, const Size(360, 640));
      final abertos = <String>[];
      final erros = <String>[];
      final anterior = FlutterError.onError;
      FlutterError.onError = (d) => erros.add(d.toString());
      await _pump(tester, [
        _doc(assunto: 'Transferência de equipamentos', situacao: 'PARCIALMENTE_CONCLUIDO'),
      ], onAbrir: (d) => abertos.add(d.id));
      FlutterError.onError = anterior;

      expect(erros.where((e) => e.toLowerCase().contains('overflow')), isEmpty);
      expect(find.text('577/2026/SEMAD/GETEC-12014'), findsOneWidget);
      expect(find.text('Transferência de equipamentos'), findsOneWidget);
      expect(find.text('33 pendentes · 0 concluídos'), findsOneWidget);
      await tester.tap(find.text('Abrir documento'));
      expect(abertos, hasLength(1));
    });
  });

  group('PROMPT 11.3.10.2 — colunas com respiro (nada "colado" ao vizinho)', () {
    const numeroFicticio = '999999/2026/TESTE-PROMPT1137';
    const assuntoFicticio = 'TESTE AUTOMATIZADO — EDIÇÃO CONFIRMADA';

    SeiDocumentoPendente ficticio({String numero = numeroFicticio, String assunto = assuntoFicticio}) {
      final json = _linhaDaViewSemItens(
        totalItens: 2,
        totalPendentes: 2,
        totalConcluidos: 0,
        totalCancelados: 0,
        situacao: 'PENDENTE',
        assunto: assunto,
      );
      json['id'] = 'doc-ficticio';
      json['numero_documento_formatado'] = numero;
      return SeiDocumentoPendente.fromJson(json);
    }

    /// Largura real da área da tabela no Windows: janela 1280 - sidebar 240 - paddings da página.
    Future<void> pumpNoMinimo(WidgetTester tester, List<SeiDocumentoPendente> docs, {double largura = 992}) async {
      _definirTamanho(tester, const Size(1280, 720));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: largura,
                child: SingleChildScrollView(
                  child: SeiPendenciasList(itens: docs, onAbrir: (_) {}),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('documento fictício: número, assunto e progresso separados por pelo menos 16px', (tester) async {
      await pumpNoMinimo(tester, [ficticio()]);

      final numero = find.text(numeroFicticio);
      final assunto = find.text(assuntoFicticio);
      final progresso = find.text('2 pendentes · 0 concluídos');
      expect(numero, findsOneWidget);
      expect(assunto, findsOneWidget);
      expect(progresso, findsOneWidget);

      final n = tester.getRect(numero);
      final a = tester.getRect(assunto);
      final p = tester.getRect(progresso);
      expect(a.left - n.right, greaterThanOrEqualTo(16), reason: 'Documento e Assunto não podem se tocar');
      expect(p.left - a.right, greaterThanOrEqualTo(16), reason: 'Assunto e Progresso não podem se tocar');
    });

    testWidgets('assunto muito longo termina em reticências DENTRO da sua célula, com tooltip', (tester) async {
      const longo =
          'TESTE AUTOMATIZADO — EDIÇÃO CONFIRMADA — transferência de equipamentos de informática entre gerências '
          'com assunto propositalmente extenso para exercitar o truncamento da célula';
      await pumpNoMinimo(tester, [ficticio(assunto: longo)]);

      final assunto = find.text(longo);
      expect(tester.renderObject<RenderParagraph>(assunto).didExceedMaxLines, isTrue);
      expect(find.byTooltip(longo), findsOneWidget, reason: 'assunto completo por tooltip');

      final progresso = tester.getRect(find.text('2 pendentes · 0 concluídos'));
      expect(progresso.left - tester.getRect(assunto).right, greaterThanOrEqualTo(16));
    });

    testWidgets('número de documento muito longo: reticências + tooltip, sem invadir o Assunto', (tester) async {
      const numeroLongo = '999999/2026/SEMAD/GETEC/COORDENACAO-EXTREMAMENTE-LONGA-1234567890';
      await pumpNoMinimo(tester, [ficticio(numero: numeroLongo)]);

      expect(find.byTooltip(numeroLongo), findsOneWidget);
      final numero = tester.getRect(find.text(numeroLongo));
      final assunto = tester.getRect(find.text(assuntoFicticio));
      expect(assunto.left - numero.right, greaterThanOrEqualTo(16));
    });

    testWidgets('duas pendências (fictícia + Despacho 577): Situação e botão Abrir dentro do Card nas duas linhas', (
      tester,
    ) async {
      await pumpNoMinimo(tester, [ficticio(), _doc(assunto: null)]);

      expect(find.text('577/2026/SEMAD/GETEC-12014'), findsOneWidget);
      expect(find.text('33 pendentes · 0 concluídos'), findsOneWidget);
      final card = tester.getRect(find.byType(Card));
      final chips = find.byType(StatusChip);
      final abrir = find.byTooltip('Abrir documento');
      expect(chips, findsNWidgets(2));
      expect(abrir, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(tester.getRect(chips.at(i)).right, lessThanOrEqualTo(card.right));
        expect(tester.getRect(abrir.at(i)).right, lessThanOrEqualTo(card.right));
        expect(tester.getRect(abrir.at(i)).left, greaterThan(tester.getRect(chips.at(i)).right));
      }
      expect(find.byType(Scrollbar), findsNothing, reason: 'no mínimo do Windows não precisa rolar na horizontal');
    });

    testWidgets('número de documento curto aparece COMPLETO, sem reticências', (tester) async {
      // (a fonte dos testes é a Ahem, ~2x mais larga que a Segoe UI real — a
      // medição real do número fictício está no comentário da constante.)
      await pumpNoMinimo(tester, [ficticio(numero: '577/2026/GETEC')]);

      expect(tester.renderObject<RenderParagraph>(find.text('577/2026/GETEC')).didExceedMaxLines, isFalse);
    });

    testWidgets('Progresso: até 2 linhas dentro da própria coluna, sem invadir a Situação', (tester) async {
      await pumpNoMinimo(tester, [
        _doc(
          totalItens: 33,
          totalPendentes: 20,
          totalConcluidos: 10,
          totalCancelados: 3,
          situacao: 'PARCIALMENTE_CONCLUIDO',
        ),
      ]);

      final texto = find.text('20 pendentes · 10 concluídos · 3 cancelados');
      expect(tester.widget<Text>(texto).maxLines, 2);
      expect(
        tester.getRect(texto).right,
        lessThan(tester.getRect(find.byType(StatusChip)).left),
        reason: 'o progresso termina antes do chip de Situação',
      );
    });
  });
}
