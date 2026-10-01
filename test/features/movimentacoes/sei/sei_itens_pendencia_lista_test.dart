import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/widgets/status_chip.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_itens_pendencia_lista.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';

import '../../auth/fake_auth_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// PROMPT 11.3.10.2 — itens do Documento SEI no diálogo de detalhe.
///
/// Causa do bug real: a tabela de 7 colunas (~1150px) morava num diálogo de
/// ~850px atrás de uma rolagem horizontal SEM barra — o Status era cortado na
/// borda e a coluna Ações (botão Cancelar) ficava fora da viewport. Estes
/// testes medem posições REAIS na tela (retângulos dentro da viewport), não
/// só a presença dos widgets na árvore.
const _destinoLongo = 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto';

SeiItemPendente _item(
  int linha, {
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
  SeiValorCorrigivel<String>? chamado,
  SeiValorCorrigivel<String>? patrimonio,
  String? motivoCancelamento,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: 'doc-1',
    linha: linha,
    numeroPatrimonio: patrimonio ?? SeiValorCorrigivel(original: '90000${linha.toString().padLeft(4, '0')}'),
    origemTexto: const SeiValorCorrigivel(original: 'Gerencia de Tecnologia'),
    origemSetorNome: 'Gerencia de Tecnologia',
    origemSetorSigla: 'GETEC',
    destinoTexto: const SeiValorCorrigivel(original: _destinoLongo),
    destinoSetorNome: _destinoLongo,
    destinoSetorSigla: 'GEASI',
    numeroChamado: chamado ?? const SeiValorCorrigivel(original: '4556'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Monitor Dell 24 polegadas'),
    status: status,
    motivoCancelamento: motivoCancelamento,
    criadoEm: DateTime(2026, 9, 22),
  );
}

SeiDocumentoPendente _documento(List<SeiItemPendente> itens, {String? assunto}) {
  return SeiDocumentoPendente.fromItens(
    id: 'doc-1',
    numeroDocumentoSei: '95955192',
    numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
    assunto: assunto,
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho.pdf',
    hashSha256: 'hash',
    versao: 1,
    criadoEm: DateTime(2026, 9, 22),
    criadoPorId: 'user-1',
    criadoPorNome: 'Fulano',
    itens: itens,
  );
}

void _tamanho(WidgetTester tester, Size tamanho) {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Profile _perfil(ProfilePerfil perfil) => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

/// Abre o diálogo de detalhe REAL (com o repositório fake — nenhum acesso ao
/// banco) e devolve o fake para conferir o efeito das ações.
Future<FakeDocumentosSeiRepository> _abrirDialogo(
  WidgetTester tester,
  SeiDocumentoPendente documento, {
  ProfilePerfil perfil = ProfilePerfil.admin,
}) async {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(perfil));
  addTearDown(auth.dispose);
  final repo = FakeDocumentosSeiRepository(documentosIniciais: [documento]);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        documentosSeiRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSeiPendenciaDetalheDialog(context, documento.id),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return repo;
}

List<String> _overflows(List<FlutterErrorDetails> erros) =>
    [for (final e in erros) e.toString()].where((e) => e.toLowerCase().contains('overflow')).toList();

Future<List<FlutterErrorDetails>> _coletando(Future<void> Function() acao) async {
  final erros = <FlutterErrorDetails>[];
  final anterior = FlutterError.onError;
  FlutterError.onError = erros.add;
  try {
    await acao();
  } finally {
    FlutterError.onError = anterior;
  }
  return erros;
}

void main() {
  group('Despacho 577 — 33 itens no diálogo', () {
    for (final tamanho in const [Size(1280, 720), Size(1440, 810), Size(1920, 1009)]) {
      testWidgets(
        '${tamanho.width.toInt()}x${tamanho.height.toInt()}: Status e Cancelar de TODOS os itens dentro da lista, sem overflow',
        (tester) async {
          _tamanho(tester, tamanho);
          final documento = _documento([for (var i = 1; i <= 33; i++) _item(i)]);
          final erros = await _coletando(() => _abrirDialogo(tester, documento));
          expect(_overflows(erros), isEmpty);

          final lista = tester.getRect(find.byType(SeiItensPendenciaLista));
          final chips = find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.byType(StatusChip));
          final cancelar = find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar'));
          expect(chips, findsNWidgets(33));
          expect(cancelar, findsNWidgets(33));

          // Posição HORIZONTAL real de cada chip/botão (independe do scroll
          // vertical): nada pode passar da borda direita da lista, nem da
          // tela.
          for (var i = 0; i < 33; i++) {
            final chip = tester.getRect(chips.at(i));
            final botao = tester.getRect(cancelar.at(i));
            expect(chip.right, lessThanOrEqualTo(lista.right), reason: 'Status do item ${i + 1} cortado');
            expect(botao.right, lessThanOrEqualTo(lista.right), reason: 'Cancelar do item ${i + 1} fora da lista');
            expect(botao.right, lessThanOrEqualTo(tamanho.width));
            expect(botao.left, greaterThan(chip.right), reason: 'Cancelar não pode ficar colado/sobre o Status');
          }

          // Nenhuma rolagem horizontal escondendo colunas dentro do diálogo.
          final horizontais = find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).evaluate().where(
            (e) => (e.widget as Scrollable).axisDirection == AxisDirection.right,
          );
          expect(horizontais, isEmpty, reason: 'o diálogo não pode depender de rolagem horizontal');
        },
      );
    }

    testWidgets('visibilidade real na viewport: primeiro item e último item (após rolar) mostram Status e Cancelar', (
      tester,
    ) async {
      _tamanho(tester, const Size(1280, 720));
      final documento = _documento([for (var i = 1; i <= 33; i++) _item(i)]);
      await _abrirDialogo(tester, documento);

      final cancelar = find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar'));
      final chips = find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.byType(StatusChip));

      for (final indice in [0, 32]) {
        await tester.ensureVisible(cancelar.at(indice));
        await tester.pumpAndSettle();
        final botao = tester.getRect(cancelar.at(indice));
        final chip = tester.getRect(chips.at(indice));
        const tela = Rect.fromLTWH(0, 0, 1280, 720);
        expect(tela.contains(botao.center), isTrue, reason: 'Cancelar do item ${indice + 1} fora da tela');
        expect(tela.contains(chip.center), isTrue, reason: 'Status do item ${indice + 1} fora da tela');
      }
    });

    // PROMPT 11.4.3 — a coluna de ações agora tem DUAS ações ("Concluir entrega" e
    // "Cancelar"). Com a fonte REAL (Segoe UI, medida num teste descartável) elas
    // ficam lado a lado e a linha mede ~59px; com a fonte Ahem dos testes (~2x mais
    // larga) elas quebram em duas linhas e a linha mede ~75px — daí o limite de 80.
    testWidgets('a lista não vira uma coluna gigante: linha compacta (≤ 80px) por item', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _abrirDialogo(tester, _documento([for (var i = 1; i <= 33; i++) _item(i)]));

      final cancelar = find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar'));
      final y0 = tester.getRect(cancelar.at(0)).center.dy;
      final y1 = tester.getRect(cancelar.at(1)).center.dy;
      expect(y1 - y0, lessThanOrEqualTo(80));
    });
  });

  group('PROMPT 11.5.15 — cabeçalho da tabela desktop nunca quebra linha', () {
    testWidgets('"Chamado" e os demais cabeçalhos ficam em UMA linha (maxLines: 1 + ellipsis)', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final erros = await _coletando(() => _abrirDialogo(tester, _documento([_item(1)])));
      expect(_overflows(erros), isEmpty);

      // Causa do bug: nenhum cabeçalho tinha `maxLines`/`overflow` — em
      // certas larguras "Chamado" (a única palavra sem espaço onde quebrar)
      // virava duas linhas, cortando a última letra. `maxLines: 1` GARANTE
      // uma única linha independente da fonte/largura do teste (mais
      // robusto que medir pixels, que dependeria da fonte Ahem do harness).
      for (final rotulo in const ['Linha', 'Patrimônio', 'Chamado', 'Origem → Destino', 'Status', 'Ação']) {
        final texto = tester.widget<Text>(find.text(rotulo));
        expect(texto.maxLines, 1, reason: '"$rotulo" precisa ficar em uma única linha');
        expect(texto.overflow, TextOverflow.ellipsis, reason: '"$rotulo" precisa cortar com reticências, nunca quebrar');
      }
    });

    testWidgets(
      'PROMPT 11.5.16 — Patrimônio preserva o flex original (5); Chamado continua com o flex ampliado (5); '
      'quem cede é Origem→Destino (6)',
      (tester) async {
        _tamanho(tester, const Size(1280, 720));
        await _abrirDialogo(tester, _documento([_item(1)]));

        // Causa do bug residual do PROMPT 11.5.15: `maxLines: 1` parou de
        // quebrar "Chamado" em duas linhas, mas a coluna (flex: 3 de 16)
        // ainda era estreita demais para a palavra inteira, cortando para
        // "Chama...". A redistribuição (Patrimônio 5→4, Chamado 3→5,
        // Origem→Destino 8→7 — soma continua 16) precisa estar refletida
        // nos `Expanded` reais da árvore, tanto no cabeçalho quanto na
        // linha de dados (as duas precisam concordar, senão as colunas
        // saem da coluna do cabeçalho).
        int flexAncestral(Finder deTexto) =>
            tester.widget<Expanded>(find.ancestor(of: deTexto, matching: find.byType(Expanded)).first).flex;

        // PROMPT 11.5.16 — auditoria final encontrou: a redistribuição de
        // 11.5.15.1 tirava espaço do Patrimônio (5→4) para dar ao Chamado —
        // mas o Patrimônio mostra o NÚMERO do patrimônio (dado, não rótulo),
        // e com flex:4 ele truncava como "DEMO-00..."/"90000..." na tabela
        // desktop. Correção: Patrimônio volta a 5 (nunca menos), Chamado
        // continua em 5 (mantém a correção de 11.5.15.1), e quem cede o
        // espaço extra é Origem→Destino (8→6) — já preparada para isso
        // (`SetorCompactText`/`_TextoUmaLinha` cortam com reticências e
        // tooltip, sem perder um dado crítico como o número do patrimônio).
        expect(flexAncestral(find.text('Chamado')), 5);
        expect(flexAncestral(find.text('Patrimônio')), 5);
        expect(flexAncestral(find.text('Origem → Destino')), 6);

        // A linha de dados do item-1 (chamado "4556", padrão do helper
        // `_item`) usa a MESMA coluna — mesmo flex, para continuar alinhada
        // com o cabeçalho.
        expect(flexAncestral(find.text('4556')), 5);
      },
    );
  });

  group('Status Pendente, Concluído e Cancelado', () {
    testWidgets('cada status aparece completo e SÓ o item pendente tem Cancelar', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final documento = _documento([
        _item(1),
        _item(2, status: SeiItemPendenciaStatus.concluido),
        _item(3, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'Duplicado'),
      ]);
      await _abrirDialogo(tester, documento);

      final lista = find.byType(SeiItensPendenciaLista);
      for (final rotulo in ['Pendente', 'Concluído', 'Cancelado']) {
        final texto = find.descendant(of: lista, matching: find.text(rotulo));
        expect(texto, findsOneWidget, reason: rotulo);
        final rect = tester.getRect(texto);
        expect(rect.right, lessThanOrEqualTo(tester.getRect(lista).right), reason: '$rotulo cortado');
      }
      expect(find.descendant(of: lista, matching: find.text('Cancelar')), findsOneWidget);
    });

    testWidgets('sem permissão (CONSULTA) nenhum item mostra Cancelar', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _abrirDialogo(tester, _documento([_item(1), _item(2)]), perfil: ProfilePerfil.consulta);

      expect(find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar')), findsNothing);
      expect(find.textContaining('Cancelar 2 item'), findsNothing);
    });
  });

  group('cancelar somente um item', () {
    testWidgets('Cancelar do item 2 cancela SÓ o item 2 (fake, sem banco) e o botão em massa continua', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final documento = _documento([_item(1), _item(2), _item(3)]);
      final repo = await _abrirDialogo(tester, documento);

      expect(find.text('Cancelar 3 itens pendentes'), findsOneWidget, reason: 'cancelamento em massa preservado');

      final botoes = find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar'));
      await tester.tap(botoes.at(1));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'Item duplicado');
      await tester.pumpAndSettle();
      // Sem motivo o botão continua desabilitado (regra: motivo obrigatório).
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(repo.cancelarItemCallCount, 1);
      expect(repo.cancelarPendentesCallCount, 0);
      final depois = await repo.obterPorId('doc-1');
      expect(depois.itens.map((i) => i.status), [
        SeiItemPendenciaStatus.pendente,
        SeiItemPendenciaStatus.cancelado,
        SeiItemPendenciaStatus.pendente,
      ]);
      expect(find.text('Cancelar 2 itens pendentes'), findsOneWidget);
    });
  });

  group('ficha completa de cada item', () {
    testWidgets('a linha resume patrimônio, equipamento, chamado e origem → destino (siglas)', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _abrirDialogo(tester, _documento([_item(1)]));

      final lista = find.byType(SeiItensPendenciaLista);
      expect(find.descendant(of: lista, matching: find.text('900000001')), findsOneWidget);
      expect(find.descendant(of: lista, matching: find.text('Monitor Dell 24 polegadas')), findsOneWidget);
      expect(find.descendant(of: lista, matching: find.text('4556')), findsOneWidget);
      expect(find.descendant(of: lista, matching: find.text('GETEC')), findsOneWidget);
      expect(find.descendant(of: lista, matching: find.text('GEASI')), findsOneWidget);
      expect(find.byTooltip(_destinoLongo), findsWidgets, reason: 'nome completo por tooltip');
    });

    testWidgets('clicar na linha expande a ficha: setores por extenso, situação e dados originais x corrigidos', (
      tester,
    ) async {
      _tamanho(tester, const Size(1280, 720));
      final corrigido = SeiValorCorrigivel<String>(
        original: '9999',
        corrigido: '9998',
        corrigidoPorNome: 'Fulano',
        motivoCorrecao: 'Teste funcional de edição de pendência',
      );
      await _abrirDialogo(tester, _documento([_item(1, chamado: corrigido)]));

      expect(find.text('Dados corrigidos'), findsNothing);
      // O valor EFETIVO (corrigido) é o que a linha mostra.
      expect(find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('9998')), findsOneWidget);

      await tester.tap(find.text('900000001'));
      await tester.pumpAndSettle();

      expect(find.text('Dados corrigidos'), findsOneWidget);
      expect(
        find.textContaining('Chamado: original "9999" → corrigido "9998" (por Fulano) — Teste funcional'),
        findsOneWidget,
      );
      expect(find.text('GEASI — $_destinoLongo'), findsOneWidget);
      expect(find.text('GETEC — Gerencia de Tecnologia'), findsOneWidget);
      expect(find.text('Situação'), findsWidgets);

      await tester.tap(find.text('900000001').first);
      await tester.pumpAndSettle();
      expect(find.text('Dados corrigidos'), findsNothing, reason: 'clicar de novo recolhe a ficha');
    });

    testWidgets('item cancelado mostra o motivo do cancelamento na ficha', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      await _abrirDialogo(
        tester,
        _documento([_item(1, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'Equipamento devolvido')]),
      );

      await tester.tap(find.text('900000001'));
      await tester.pumpAndSettle();

      expect(find.text('Motivo do cancelamento'), findsOneWidget);
      expect(find.text('Equipamento devolvido'), findsOneWidget);
    });

    testWidgets('patrimônio sem equipamento no documento: não inventa nada', (tester) async {
      _tamanho(tester, const Size(1280, 720));
      final semEquipamento = SeiItemPendente(
        id: 'item-1',
        documentoId: 'doc-1',
        linha: 1,
        numeroPatrimonio: const SeiValorCorrigivel(original: '900000001'),
        origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
        destinoTexto: const SeiValorCorrigivel(original: 'GEASI'),
        numeroChamado: const SeiValorCorrigivel(original: null),
        equipamentoTexto: const SeiValorCorrigivel(original: null),
        status: SeiItemPendenciaStatus.pendente,
        criadoEm: DateTime(2026, 9, 22),
      );
      await _abrirDialogo(tester, _documento([semEquipamento]));

      expect(find.textContaining('null'), findsNothing);
      expect(find.text('900000001'), findsOneWidget);
    });
  });

  group('mobile', () {
    testWidgets('360x640: item vira bloco compacto com Status e Cancelar visíveis, sem overflow', (tester) async {
      _tamanho(tester, const Size(360, 640));
      final erros = await _coletando(() => _abrirDialogo(tester, _documento([_item(1), _item(2)])));
      expect(_overflows(erros), isEmpty);

      final lista = tester.getRect(find.byType(SeiItensPendenciaLista));
      final chip = tester.getRect(find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.byType(StatusChip)).first);
      final cancelar = tester.getRect(
        find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar')).first,
      );
      expect(chip.right, lessThanOrEqualTo(lista.right));
      expect(cancelar.right, lessThanOrEqualTo(360));
      expect(find.text('Origem → Destino'), findsNothing, reason: 'sem cabeçalho de colunas no modo compacto');
    });
  });
}
