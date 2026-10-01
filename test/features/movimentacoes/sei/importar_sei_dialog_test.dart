import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_parser.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/data/sei_pdf_text_extractor.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/importar_sei_dialog.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_import_controller.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../patrimonios/fake_patrimonio_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_movimentacao_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// PROMPT 11.3.5.1/11.3.5.2 — teste de LAYOUT do diálogo de importação SEI:
/// 11.3.5.1 corrigiu o rodapé de 5 botões ("RIGHT OVERFLOWED BY 14 PIXELS");
/// 11.3.5.2 corrigiu o `Text` sem `Expanded` de `_RodapeSelecao` (dentro da
/// revisão). Nunca simula seleção de arquivo real (nenhum
/// `file_selector`/plugin nativo) — dirige o `SeiImportController`
/// diretamente até o passo de revisão, exatamente como
/// `sei_import_controller_test.dart`, e só então abre o diálogo real com
/// `showImportarSeiDialog`.

class _FakeExtractor implements SeiPdfTextExtractor {
  const _FakeExtractor();

  @override
  Future<SeiPdfLido> extrair(Uint8List bytes) async =>
      const SeiPdfLido(textoPorPagina: ['texto'], quantidadePaginas: 1, hashSha256: 'hash-fake');
}

class _FakeParser implements SeiDocumentoParser {
  _FakeParser(this.documento);
  final SeiDocumentoExtraido documento;

  @override
  Future<SeiDocumentoExtraido> analisar({
    required String nomeArquivo,
    required int tamanhoBytes,
    required String hashSha256,
    required List<String> textoPorPagina,
  }) async => documento;
}

final _setorGetec = Setor(
  id: 'setor-getec',
  nome: 'Gerencia de Tecnologia',
  sigla: 'GETEC',
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
);
final _setorGeasi = Setor(
  id: 'setor-geasi',
  nome: 'Gerência de Licenciamento',
  sigla: 'GEASI',
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
);

PatrimonioDetalhe _patrimonio(String numero) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'id-$numero',
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-getec',
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'Gerencia de Tecnologia',
    setorSigla: 'GETEC',
  );
}

/// 33 itens (não 2) de propósito: reproduz a escala real que expôs o bug
/// original (Despacho 577 — 33 patrimônios), cujo rótulo "Copiar plano
/// (33)" é um pouco mais largo que com poucos itens e contribui para a
/// largura total do rodapé.
SeiDocumentoExtraido _documentoComItens() {
  return SeiDocumentoExtraido(
    nomeArquivo: 'despacho.pdf',
    tamanhoBytes: 500,
    quantidadePaginas: 1,
    hashSha256: 'hash-fake',
    numeroDocumentoSei: '95955192',
    numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
    tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
    itens: List.generate(
      33,
      (i) => SeiItemExtraido(
        linha: i + 1,
        paginaOrigem: 1,
        numeroPatrimonio: '${4157090 + i}',
        equipamento: 'Monitor Positivo',
        unidadeOrigemTexto: 'GETEC - Gerencia de Tecnologia',
        unidadeDestinoTexto: 'Gerência de Licenciamento – GEASI',
        numeroChamado: '4556',
      ),
    ),
  );
}

/// Cria o `ProviderContainer` já no passo `revisao` (o único em que o
/// rodapé de 5 botões aparece) — chamando o controller diretamente, nunca
/// via um seletor de arquivo real.
Future<ProviderContainer> _containerNaRevisao() async {
  final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090'), _patrimonio('9999999')]);
  final container = ProviderContainer(
    overrides: [
      seiPdfTextExtractorProvider.overrideWithValue(const _FakeExtractor()),
      seiDocumentoParserProvider.overrideWithValue(_FakeParser(_documentoComItens())),
      patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGeasi])),
      movimentacaoRepositoryProvider.overrideWithValue(FakeMovimentacaoRepository()),
      documentosSeiRepositoryProvider.overrideWithValue(FakeDocumentosSeiRepository()),
    ],
  );
  // Mantém o `NotifierProvider.autoDispose` vivo entre o `await` abaixo e o
  // `pumpWidget` — sem isto, ele se descartaria por falta de listener e o
  // diálogo abriria de volta no passo inicial.
  container.listen(seiImportControllerProvider, (_, _) {});

  await container
      .read(seiImportControllerProvider.notifier)
      .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1, 2, 3]));

  return container;
}

/// Abre o diálogo e devolve as mensagens de "RenderFlex overflowed"
/// capturadas durante o pump (nunca deixa nenhuma vazar como falha
/// automática do teste — coletamos para poder dar uma mensagem de erro
/// legível, mas quem decide se é falha é o `expect` no teste). PROMPT
/// 11.3.5.1 corrigiu o rodapé de ações do próprio diálogo
/// (`importar_sei_dialog.dart`); PROMPT 11.3.5.2 corrigiu o overflow que
/// sobrava em `_RodapeSelecao` (`sei_revisao_step.dart`) — agora o diálogo
/// inteiro (dentro do `SingleChildScrollView` incluso) precisa ficar livre
/// de overflow, não só o rodapé.
Future<List<String>> _abrirDialogo(WidgetTester tester, ProviderContainer container) async {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toString().contains('RenderFlex overflowed')) {
      overflows.add(details.toString());
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                ElevatedButton(onPressed: () => showImportarSeiDialog(context), child: const Text('abrir')),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();

  FlutterError.onError = original;
  return overflows;
}

void main() {
  group('PROMPT 11.3.5.1/11.3.5.2 — diálogo de importação SEI nunca estoura (overflow)', () {
    testWidgets('no tamanho normal do diálogo, os 5 botões e a mensagem de seleção aparecem sem overflow', (
      tester,
    ) async {
      // Largura >= 900 + o `insetPadding` padrão do `Dialog`: o diálogo
      // chega à sua própria `maxWidth: 900` (a mesma condição do bug
      // original — "RIGHT OVERFLOWED BY 14 PIXELS" — não dependia de uma
      // janela estreita, e sim do rodapé ser ligeiramente mais largo do
      // que o próprio diálogo já permite).
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _containerNaRevisao();
      addTearDown(container.dispose);

      final overflows = await _abrirDialogo(tester, container);

      expect(overflows, isEmpty, reason: 'o diálogo inteiro (rodapé + revisão) não pode estourar: $overflows');

      for (final rotulo in [
        'Analisar outro documento',
        'Copiar resumo da análise',
        'Copiar plano (0)',
        'Fechar sem salvar',
        'Salvar como pendência',
      ]) {
        expect(find.text(rotulo), findsOneWidget, reason: 'botão "$rotulo" precisa estar visível e acessível');
      }

      // PROMPT 11.3.5.2: a mensagem de `_RodapeSelecao` precisa continuar
      // completa (nunca truncada/reticências) — só quebrando linha.
      expect(
        find.text(
          '0 de 33 itens selecionados para um futuro lote · 0 aptos tecnicamente (nenhum registrado agora).',
        ),
        findsOneWidget,
      );
      expect(find.text('Revalidar estado atual'), findsOneWidget);
    });

    testWidgets('com escala de texto aumentada, o diálogo inteiro continua sem overflow e sem botões escondidos', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = await _containerNaRevisao();
      addTearDown(container.dispose);

      final overflows = await _abrirDialogo(tester, container);

      expect(
        overflows,
        isEmpty,
        reason: 'o diálogo inteiro não pode estourar mesmo com texto maior: $overflows',
      );
      expect(find.text('Salvar como pendência'), findsOneWidget);
      expect(find.text('Fechar sem salvar'), findsOneWidget);
    });
  });

  group('PROMPT 11.3.5.4 — tabela de revisão do SEI mostra a sigla do setor resolvido', () {
    testWidgets('Origem/Destino mostram a sigla (GETEC/GEASI), não o nome completo', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _containerNaRevisao();
      addTearDown(container.dispose);

      await _abrirDialogo(tester, container);

      // `_setorGetec`/`_setorGeasi` (sigla GETEC/GEASI) resolvem para os 33
      // itens (mesmo texto de origem/destino repetido) — a coluna mostra a
      // sigla, nunca o nome completo do setor resolvido.
      expect(find.text('GETEC'), findsNWidgets(33));
      expect(find.text('GEASI'), findsNWidgets(33));
      expect(find.text(_setorGeasi.nome), findsNothing);
    });

    testWidgets('detalhe do item (clique na linha) mostra a sigla do setor atual, com nome completo no tooltip', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _containerNaRevisao();
      addTearDown(container.dispose);

      await _abrirDialogo(tester, container);

      // PROMPT 11.3.5.5: `sei_item_detalhe_dialog.dart` tinha um overflow
      // no `Row` da seção "Responsável de destino" (TextField + botões não
      // cabiam nos 520px do diálogo) — corrigido trocando o `Row` por um
      // `TextField` de largura total seguido de um `Wrap` para os botões.
      // Este teste agora também garante que abrir o diálogo de detalhe do
      // item não introduz nenhum overflow.
      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('RenderFlex overflowed')) {
          overflows.add(details.toString());
          return;
        }
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);

      // Linha 1 (patrimônio 4157090) é a única com patrimônio resolvido no
      // InvTec neste teste — clicar nela abre `sei_item_detalhe_dialog`.
      final linha1 = find.text('4157090');
      await tester.ensureVisible(linha1);
      await tester.pumpAndSettle();
      await tester.tap(linha1);
      await tester.pumpAndSettle();

      FlutterError.onError = original;

      expect(overflows, isEmpty, reason: 'o diálogo de detalhe do item não pode estourar: $overflows');
      expect(find.text('GETEC'), findsWidgets);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.text('GETEC').last, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, 'Gerencia de Tecnologia');
    });
  });

  group('PROMPT 11.3.5.5 — seção "Responsável de destino" do detalhe do item nunca estoura', () {
    testWidgets('no tamanho normal do diálogo, o campo e os dois botões aparecem sem overflow', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _containerNaRevisao();
      addTearDown(container.dispose);

      await _abrirDialogo(tester, container);

      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('RenderFlex overflowed')) {
          overflows.add(details.toString());
          return;
        }
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);

      final linha1 = find.text('4157090');
      await tester.ensureVisible(linha1);
      await tester.pumpAndSettle();
      await tester.tap(linha1);
      await tester.pumpAndSettle();

      FlutterError.onError = original;

      expect(overflows, isEmpty, reason: 'a seção "Responsável de destino" não pode estourar: $overflows');
      // Nenhuma opção foi ocultada: os dois botões continuam visíveis, ao
      // lado do campo de texto do responsável.
      expect(find.widgetWithText(OutlinedButton, 'Definir'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Confirmar sem responsável'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('com escala de texto aumentada, o campo e os dois botões continuam visíveis e sem overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final container = await _containerNaRevisao();
      addTearDown(container.dispose);

      await _abrirDialogo(tester, container);

      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('RenderFlex overflowed')) {
          overflows.add(details.toString());
          return;
        }
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);

      final linha1 = find.text('4157090');
      await tester.ensureVisible(linha1);
      await tester.pumpAndSettle();
      await tester.tap(linha1);
      await tester.pumpAndSettle();

      FlutterError.onError = original;

      expect(
        overflows,
        isEmpty,
        reason: 'a seção "Responsável de destino" não pode estourar mesmo com texto maior: $overflows',
      );
      expect(find.widgetWithText(OutlinedButton, 'Definir'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Confirmar sem responsável'), findsOneWidget);
    });
  });
}
