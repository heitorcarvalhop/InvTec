import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/presentation/widgets/patrimonio_desktop_table.dart';

/// PROMPT 11.3.10 — a listagem de Patrimônios ficou só com identificação e
/// consulta rápida (Patrimônio, Equipamento, Setor, Status, Ações). O clique
/// na linha usa `onTap` — o MESMO callback do botão "Ver detalhes", que a
/// página liga à ficha completa; "Editar" é um botão à parte.
const _descricaoLonga =
    'Notebook corporativo com 32 GB de memória, SSD de 1 TB, docking station e garantia estendida até 2028';

PatrimonioDetalhe _item(
  String id, {
  String numero = '00045872',
  String? descricao = _descricaoLonga,
  String? marca = 'Dell',
  String? modelo = 'Latitude 5440',
  String setorNome = 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
  String? setorSigla = 'GEASI',
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      numeroSerie: 'SERIE-XYZ-987',
      tipoId: 'tipo-1',
      marca: marca,
      modelo: modelo,
      descricao: descricao,
      status: PatrimonioStatus.emUso,
      setorAtualId: 'setor-1',
      responsavelAtual: 'João Silva',
      dataCadastro: DateTime.utc(2026, 1, 10),
      atualizadoEm: DateTime.utc(2026, 1, 10),
    ),
    tipoNome: 'Notebook',
    setorNome: setorNome,
    setorSigla: setorSigla,
    localizacaoNome: 'Sala 12 - Almoxarifado',
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<PatrimonioDetalhe> itens, {
  bool canManage = true,
  ValueChanged<PatrimonioDetalhe>? onTap,
  ValueChanged<PatrimonioDetalhe>? onEdit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PatrimonioDesktopTable(
            itens: itens,
            canManage: canManage,
            onTap: onTap ?? (_) {},
            onEdit: onEdit ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void _tamanho(WidgetTester tester, Size tamanho) {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('colunas', () {
    testWidgets('cabeçalho: Patrimônio, Equipamento, Setor, Status e Ações', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1')]);

      for (final coluna in ['Patrimônio', 'Equipamento', 'Setor', 'Status', 'Ações']) {
        expect(find.text(coluna), findsOneWidget, reason: coluna);
      }
      for (final removida in ['Identificação', 'Localização', 'Responsável']) {
        expect(find.text(removida), findsNothing, reason: '$removida agora só existe na ficha');
      }
    });

    testWidgets('a linha mostra número completo, tipo, marca + modelo, sigla do setor e status', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1')]);

      expect(find.text('00045872'), findsOneWidget);
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('Dell Latitude 5440'), findsOneWidget);
      expect(find.text('GEASI'), findsOneWidget);
      expect(find.text('Em uso'), findsOneWidget);
    });

    testWidgets('descrição longa, série, localização e responsável não aparecem na linha', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1')]);

      expect(find.text(_descricaoLonga), findsNothing, reason: 'a descrição integral fica no tooltip e na ficha');
      expect(find.textContaining('SERIE-XYZ-987'), findsNothing);
      expect(find.text('Sala 12 - Almoxarifado'), findsNothing);
      expect(find.text('João Silva'), findsNothing);
    });

    testWidgets('sem marca/modelo, usa um trecho CURTO da descrição existente (com reticências)', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1', marca: null, modelo: null)]);

      expect(find.text(_descricaoLonga), findsNothing);
      final trecho = _descricaoLonga.substring(0, 48).trimRight();
      expect(find.text('$trecho…'), findsOneWidget);
    });

    testWidgets('sem marca, modelo nem descrição: só o tipo, nunca "null"', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1', marca: null, modelo: null, descricao: null)]);

      expect(find.text('Notebook'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(resumoEquipamento(_item('1', marca: null, modelo: null, descricao: null)).secundaria, isNull);
    });

    testWidgets('setor: sigla visível, nome completo no tooltip', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1')]);

      expect(
        find.byTooltip('Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto'),
        findsOneWidget,
      );
    });

    testWidgets('equipamento: tooltip guarda tipo, marca/modelo e a descrição INTEGRAL', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1')]);

      expect(find.byTooltip('Notebook\nDell Latitude 5440\n$_descricaoLonga'), findsOneWidget);
    });

    testWidgets('espaçamento: a célula Equipamento termina antes da coluna Setor, com respiro', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _pump(tester, [_item('1', marca: 'Fabricante com nome muito comprido', modelo: 'Modelo ' * 12)]);

      final segundaLinha = tester.getRect(find.textContaining('Fabricante com nome'));
      final setor = tester.getRect(find.text('GEASI'));

      // O texto (mesmo longo) fica todo à esquerda do setor, com folga.
      expect(setor.left - segundaLinha.right, greaterThanOrEqualTo(16), reason: 'padding entre as colunas');
      final paragrafo = tester.renderObject<RenderParagraph>(find.textContaining('Fabricante com nome'));
      expect(paragrafo.didExceedMaxLines, isTrue, reason: 'texto longo termina em reticências na própria célula');
    });

    test('resumoEquipamento não repete o tipo na segunda linha', () {
      expect(resumoEquipamento(_item('1', marca: null, modelo: 'Notebook Latitude 5440')).secundaria, 'Latitude 5440');
      expect(resumoEquipamento(_item('1', marca: null, modelo: 'Notebook', descricao: null)).secundaria, isNull);
      expect(resumoEquipamento(_item('1', marca: 'Dell', modelo: 'Latitude 5440')).secundaria, 'Dell Latitude 5440');
    });

    test('resumoEquipamento usa só marca ou só modelo quando o outro falta', () {
      expect(resumoEquipamento(_item('1', marca: 'Dell', modelo: null)).secundaria, 'Dell');
      expect(resumoEquipamento(_item('1', marca: null, modelo: 'Latitude 5440')).secundaria, 'Latitude 5440');
    });
  });

  group('clique na linha, Visualizar e Editar', () {
    testWidgets('clicar na linha abre o registro certo, uma única vez', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final abertos = <String>[];
      final editados = <String>[];
      await _pump(
        tester,
        [_item('a', numero: '100'), _item('b', numero: '200')],
        onTap: (d) => abertos.add(d.patrimonio.id),
        onEdit: (d) => editados.add(d.patrimonio.id),
      );

      await tester.tap(find.text('200'));
      await tester.pump();

      expect(abertos, ['b']);
      expect(editados, isEmpty);
    });

    testWidgets('"Ver detalhes" abre o mesmo registro que o clique na linha', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final abertos = <String>[];
      await _pump(tester, [_item('a', numero: '100')], onTap: (d) => abertos.add(d.patrimonio.id));

      await tester.tap(find.text('100'));
      await tester.pump();
      await tester.tap(find.byTooltip('Ver detalhes'));
      await tester.pump();

      expect(abertos, ['a', 'a']);
    });

    testWidgets('clicar em Editar edita e NÃO abre também o detalhe', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final abertos = <String>[];
      final editados = <String>[];
      await _pump(
        tester,
        [_item('a', numero: '100')],
        onTap: (d) => abertos.add(d.patrimonio.id),
        onEdit: (d) => editados.add(d.patrimonio.id),
      );

      await tester.tap(find.byTooltip('Editar'));
      await tester.pump();

      expect(editados, ['a']);
      expect(abertos, isEmpty, reason: 'o clique do botão não propaga para a linha');
    });

    testWidgets('sem permissão de gerenciar não há botão Editar, mas a linha continua abrindo', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final abertos = <String>[];
      await _pump(tester, [_item('a', numero: '100')], canManage: false, onTap: (d) => abertos.add(d.patrimonio.id));

      expect(find.byTooltip('Editar'), findsNothing);
      await tester.tap(find.text('100'));
      await tester.pump();
      expect(abertos, ['a']);
    });

    testWidgets('teclado: a linha recebe foco e Enter abre o detalhe', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final abertos = <String>[];
      await _pump(tester, [_item('a', numero: '100')], onTap: (d) => abertos.add(d.patrimonio.id));

      // Tab #1 cai na própria linha (InkWell); o botão vem depois.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(abertos, ['a']);
    });
  });

  group('sem overflow no tamanho mínimo do Windows', () {
    for (final tamanho in const [Size(1280, 720), Size(1264, 641), Size(1920, 1009)]) {
      testWidgets('${tamanho.width.toInt()}x${tamanho.height.toInt()} com textos longos', (tester) async {
        _tamanho(tester, tamanho);
        final erros = <String>[];
        final anterior = FlutterError.onError;
        FlutterError.onError = (d) => erros.add(d.toString());
        await _pump(tester, [_item('1'), _item('2', numero: '00099999', setorSigla: null)]);
        FlutterError.onError = anterior;

        expect(erros.where((e) => e.toLowerCase().contains('overflow')), isEmpty);
        // Número completo, sem reticências: cabe inteiro na sua coluna.
        final numero = tester.renderObject<RenderParagraph>(find.text('00045872'));
        expect(numero.didExceedMaxLines, isFalse);
      });
    }
  });
}
