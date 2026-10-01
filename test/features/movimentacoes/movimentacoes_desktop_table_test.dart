import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacao_detail_dialog.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacoes_desktop_table.dart';

/// PROMPT 11.3.10 — o histórico de movimentações (EXECUTADAS) mostra só
/// Data, Patrimônio, Tipo, Origem → Destino e o botão de abrir; Responsável,
/// Autor, motivo, documento, chamado etc. ficam no diálogo de detalhe.
const _nomeLongo = 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto';

MovimentacaoListagemItem _item(String id, {String numero = '00045872', String? autor = 'Maria Autora'}) {
  return MovimentacaoListagemItem(
    id: id,
    tipo: MovimentacaoTipo.transferencia,
    patrimonioId: 'patrimonio-$id',
    patrimonioNumero: numero,
    patrimonioTipoNome: 'Notebook',
    setorOrigemNome: 'Gerência de Tecnologia',
    setorOrigemSigla: 'GETEC',
    setorDestinoNome: _nomeLongo,
    setorDestinoSigla: 'GEASI',
    responsavelDestino: 'João Silva',
    autorNome: autor,
    motivo: 'Reorganização do setor',
    observacao: 'Entregue com carregador',
    numeroDocumento: '577/2026',
    numeroChamado: '9999',
    dataMovimentacao: DateTime(2026, 1, 10, 14, 30),
  );
}

void _tamanho(WidgetTester tester, Size tamanho) {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  List<MovimentacaoListagemItem> itens, {
  ValueChanged<MovimentacaoListagemItem>? onVisualizar,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MovimentacoesDesktopTable(itens: itens, onVisualizar: onVisualizar ?? (_) {}),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('cabeçalho: Data, Patrimônio, Tipo e Origem → Destino (sem Responsável/Autor)', (tester) async {
    _tamanho(tester, const Size(1280, 720));
    await _pump(tester, [_item('1')]);

    for (final coluna in ['Data', 'Patrimônio', 'Tipo', 'Origem → Destino']) {
      expect(find.text(coluna), findsOneWidget, reason: coluna);
    }
    for (final removida in ['Origem', 'Destino', 'Responsável', 'Autor']) {
      expect(find.text(removida), findsNothing, reason: '$removida saiu da listagem');
    }
  });

  testWidgets('PROMPT 11.3.10.2 — a última coluna tem o cabeçalho "Ações", inteiro e alinhado ao botão', (
    tester,
  ) async {
    _tamanho(tester, const Size(1280, 720));
    await _pump(tester, [_item('1')]);

    final cabecalho = find.text('Ações');
    expect(cabecalho, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(cabecalho).didExceedMaxLines, isFalse, reason: 'cabeçalho não cortado');

    final rotulo = tester.getRect(cabecalho);
    final botao = tester.getRect(find.byTooltip('Visualizar'));
    final card = tester.getRect(find.byType(Card));
    expect(rotulo.right, lessThanOrEqualTo(card.right));
    expect(botao.right, lessThanOrEqualTo(card.right));
    // O rótulo fica sobre a coluna do botão (mesma faixa horizontal).
    expect(rotulo.left, lessThan(botao.right));
    expect(rotulo.right, greaterThan(botao.left));
  });

  testWidgets('a linha mostra data, patrimônio, tipo e sigla origem → sigla destino', (tester) async {
    _tamanho(tester, const Size(1280, 720));
    await _pump(tester, [_item('1')]);

    expect(find.text('10/01/2026 14:30'), findsOneWidget);
    expect(find.text('00045872'), findsOneWidget);
    expect(find.text('Notebook'), findsOneWidget);
    expect(find.text('Transferência'), findsOneWidget);
    expect(find.text('GETEC'), findsOneWidget);
    expect(find.text('GEASI'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    expect(find.byTooltip(_nomeLongo), findsOneWidget, reason: 'nome completo por tooltip');
    // Redundâncias que só existem no detalhe.
    expect(find.text('Maria Autora'), findsNothing);
    expect(find.text('João Silva'), findsNothing);
  });

  testWidgets('clicar na linha e no botão abrem o detalhe do MESMO registro', (tester) async {
    _tamanho(tester, const Size(1280, 720));
    final abertos = <String>[];
    await _pump(tester, [_item('a', numero: '100'), _item('b', numero: '200')], onVisualizar: (i) => abertos.add(i.id));

    await tester.tap(find.text('200'));
    await tester.pump();
    expect(abertos, ['b']);

    await tester.tap(find.byTooltip('Visualizar').last);
    await tester.pump();
    expect(abertos, ['b', 'b'], reason: 'o botão não dispara também o clique da linha');
  });

  testWidgets('o detalhe continua com responsável, autor, motivo, observação, documento e chamado', (tester) async {
    _tamanho(tester, const Size(1280, 720));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MovimentacaoDetailDialog(item: _item('1'))),
      ),
    );

    for (final texto in [
      'João Silva',
      'Maria Autora',
      'Reorganização do setor',
      'Entregue com carregador',
      '577/2026',
      '9999',
      '00045872',
    ]) {
      expect(find.text(texto), findsOneWidget, reason: texto);
    }
    expect(find.text('Origem'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
  });

  for (final tamanho in const [Size(1280, 720), Size(1264, 641), Size(1920, 1009)]) {
    testWidgets('sem overflow em ${tamanho.width.toInt()}x${tamanho.height.toInt()} com textos longos', (tester) async {
      _tamanho(tester, tamanho);
      final erros = <String>[];
      final anterior = FlutterError.onError;
      FlutterError.onError = (d) => erros.add(d.toString());
      await _pump(tester, [_item('1'), _item('2', autor: null)]);
      FlutterError.onError = anterior;

      expect(erros.where((e) => e.toLowerCase().contains('overflow')), isEmpty);
    });
  }
}
