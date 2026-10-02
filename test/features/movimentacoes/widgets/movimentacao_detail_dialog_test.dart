import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/movimentacao_detail_dialog.dart';

/// Item com TODOS os campos opcionais preenchidos (equipamento, localização,
/// motivo, observação, documento, chamado) — exercita o arranjo completo em
/// grade/coluna sem deixar nenhum par "pela metade".
MovimentacaoListagemItem _itemCompleto() {
  return MovimentacaoListagemItem(
    id: '1',
    tipo: MovimentacaoTipo.transferencia,
    patrimonioId: 'patrimonio-1',
    patrimonioNumero: '00045872',
    patrimonioTipoNome: 'Notebook',
    setorOrigemNome: 'Gerência de Tecnologia',
    setorOrigemSigla: 'GETEC',
    setorDestinoNome: 'Gerência de Posturas',
    setorDestinoSigla: 'GEPOS',
    localizacaoOrigemNome: 'Sala 1',
    localizacaoDestinoNome: 'Sala 2',
    responsavelDestino: 'João Silva',
    autorNome: 'Maria Autora',
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

Future<void> _pump(WidgetTester tester, Size tamanho) async {
  _tamanho(tester, tamanho);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: MovimentacaoDetailDialog(item: _itemCompleto()))),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MovimentacaoDetailDialog — responsividade', () {
    testWidgets('diálogo largo: pares de campo ficam lado a lado na mesma linha', (tester) async {
      await _pump(tester, const Size(1100, 800));

      final patrimonio = tester.getTopLeft(find.text('Patrimônio'));
      final equipamento = tester.getTopLeft(find.text('Equipamento'));
      final origem = tester.getTopLeft(find.text('Origem'));
      final destino = tester.getTopLeft(find.text('Destino'));
      final autor = tester.getTopLeft(find.text('Autor'));
      final dataHora = tester.getTopLeft(find.text('Data/hora'));

      expect(equipamento.dy, patrimonio.dy, reason: 'Equipamento ao lado de Patrimônio, não abaixo');
      expect(equipamento.dx, greaterThan(patrimonio.dx));

      expect(destino.dy, origem.dy, reason: 'Destino ao lado de Origem, não abaixo');
      expect(destino.dx, greaterThan(origem.dx));

      expect(dataHora.dy, autor.dy, reason: 'Data/hora ao lado de Autor, não abaixo');
      expect(dataHora.dx, greaterThan(autor.dx));
    });

    testWidgets('diálogo estreito: campos empilham em coluna única', (tester) async {
      await _pump(tester, const Size(380, 900));

      final patrimonio = tester.getTopLeft(find.text('Patrimônio'));
      final equipamento = tester.getTopLeft(find.text('Equipamento'));
      final origem = tester.getTopLeft(find.text('Origem'));
      final destino = tester.getTopLeft(find.text('Destino'));

      expect(equipamento.dy, greaterThan(patrimonio.dy), reason: 'Equipamento abaixo de Patrimônio em coluna');
      expect(destino.dy, greaterThan(origem.dy), reason: 'Destino abaixo de Origem em coluna');

      // Nenhum dado some ao reempilhar — só o arranjo muda.
      for (final texto in ['João Silva', 'Maria Autora', 'Reorganização do setor', '577/2026', '9999']) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
    });

    for (final tamanho in const [Size(380, 900), Size(760, 800), Size(1280, 800), Size(1920, 1080)]) {
      testWidgets('sem overflow/exceções em ${tamanho.width.toInt()}x${tamanho.height.toInt()}', (tester) async {
        final erros = <String>[];
        final anterior = FlutterError.onError;
        FlutterError.onError = (details) => erros.add(details.toString());

        await _pump(tester, tamanho);

        FlutterError.onError = anterior;
        expect(erros, isEmpty, reason: erros.join('\n'));
      });
    }
  });
}
