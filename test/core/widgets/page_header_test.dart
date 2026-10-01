import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/page_header.dart';

/// PROMPT 11.3.9.1 — reproduz, isolado do resto da tela, o defeito do
/// vídeo: em largura de TABLET (600–1024px, onde `compact` continua
/// `false` — só telas < 600 usam a pilha vertical), um `Row` com
/// `Expanded(child: titulo)` ao lado de um `Wrap` de botões NÃO flexível
/// dava aos botões sua largura NATURAL irrestrita, sobrando pouco/nenhum
/// espaço para o título — que quebrava letra por letra, e o próprio `Row`
/// estourava ("RenderFlex overflowed ... on the right").
void main() {
  Future<void> pumpHeader(WidgetTester tester, Size tamanho) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: InvTecPageHeader(
              title: 'Movimentações',
              subtitle: 'Consulte e acompanhe o histórico de movimentações patrimoniais.',
              actions: [
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Importar documento SEI'),
                ),
                FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Nova movimentação')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('PROMPT 11.3.9.1 — InvTecPageHeader (não-compacto) nunca esmaga título/botões', () {
    for (final tamanho in [const Size(1920, 1080), const Size(1280, 720), const Size(800, 600), const Size(700, 600)]) {
      testWidgets('em ${tamanho.width.toInt()}x${tamanho.height.toInt()}: sem overflow, título e botões legíveis', (
        tester,
      ) async {
        // A `FlutterError.onError` original PRECISA ser restaurada logo
        // depois do pump, nunca só num `addTearDown` — deixá-la sobrescrita
        // durante os `expect()` seguintes confunde o estado interno do
        // `TestWidgetsFlutterBinding` ("test overrode FlutterError.onError
        // but ... failed to return it to its original state") e trava TODOS
        // os testes seguintes do arquivo (mesmo padrão já usado em
        // `importar_sei_dialog_test.dart`).
        final overflows = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('RenderFlex overflowed')) {
            overflows.add(details.summary.toString());
            return;
          }
          original?.call(details);
        };
        addTearDown(() => FlutterError.onError = original);

        await pumpHeader(tester, tamanho);

        FlutterError.onError = original;

        expect(overflows, isEmpty, reason: 'não pode haver RenderFlex overflowed: $overflows');

        // Nunca uma letra por linha: a largura real do título precisa ser
        // compatível com o texto inteiro numa única linha (bem maior que a
        // largura de um único caractere).
        final tituloSize = tester.getSize(find.text('Movimentações'));
        expect(tituloSize.width, greaterThan(80), reason: 'título não pode estar espremido a poucos pixels');

        final botaoSize = tester.getSize(find.text('Nova movimentação'));
        expect(botaoSize.width, greaterThan(80), reason: 'texto do botão não pode estar espremido a poucos pixels');

        expect(find.text('Importar documento SEI'), findsOneWidget);
        expect(find.text('Nova movimentação'), findsOneWidget);
      });
    }

    testWidgets('janela maximizada (1920x1080): botões ficam à direita, título à esquerda (aparência preservada)', (
      tester,
    ) async {
      await pumpHeader(tester, const Size(1920, 1080));

      final tituloLeft = tester.getTopLeft(find.text('Movimentações')).dx;
      final botaoLeft = tester.getTopLeft(find.text('Importar documento SEI')).dx;
      expect(tituloLeft, lessThan(50));
      expect(botaoLeft, greaterThan(1200), reason: 'botões continuam empurrados para a direita, como antes');
    });

    testWidgets('compact=true (mobile) continua empilhando título acima dos botões', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvTecPageHeader(
              title: 'Movimentações',
              compact: true,
              actions: [FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('Nova movimentação'))],
            ),
          ),
        ),
      );

      final tituloTop = tester.getTopLeft(find.text('Movimentações')).dy;
      final botaoTop = tester.getTopLeft(find.text('Nova movimentação')).dy;
      expect(botaoTop, greaterThan(tituloTop), reason: 'botão continua abaixo do título no modo compacto');
    });
  });
}
