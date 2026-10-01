import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_situacao.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_evento_documento.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';

import '../../auth/fake_auth_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// Auditoria do cancelamento e documento ENCERRADO.
///
/// Só fake/local: nada é cancelado de verdade. Contrato de auditoria:
///  * botão da LINHA  → `cancelar_item_sei_pendente`        → 1 evento `ITEM_CANCELADO` (com `item_id`);
///  * botão do RODAPÉ → `cancelar_pendentes_documento_sei`  → 1 evento `DOCUMENTO_CANCELADO` (`item_id` nulo),
///    com 1 ou N pendentes — nunca degrada para cancelamento individual.
const _docId = 'doc-ficticio';
const _motivoDiagnostico = 'Teste diagnóstico do cancelamento em massa';

SeiItemPendente _item(
  int linha, {
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
  String? motivoCancelamento,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: _docId,
    linha: linha,
    numeroPatrimonio: SeiValorCorrigivel(original: '90000000$linha'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    destinoTexto: const SeiValorCorrigivel(original: 'GEASI'),
    numeroChamado: const SeiValorCorrigivel(original: '9999'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Equipamento fictício'),
    status: status,
    motivoCancelamento: motivoCancelamento,
    criadoEm: DateTime(2026, 9, 22),
  );
}

SeiDocumentoPendente _documento(List<SeiItemPendente> itens) => SeiDocumentoPendente.fromItens(
  id: _docId,
  numeroDocumentoSei: '99999999',
  numeroDocumentoFormatado: '999999/2026/TESTE-PROMPT1137',
  assunto: 'TESTE AUTOMATIZADO — EDIÇÃO CONFIRMADA',
  tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
  nomeArquivo: 'despacho.pdf',
  hashSha256: 'hash',
  versao: 1,
  criadoEm: DateTime(2026, 9, 22),
  criadoPorId: 'user-1',
  criadoPorNome: 'Fulano',
  itens: itens,
);

Profile _perfil(ProfilePerfil perfil) => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

Future<FakeDocumentosSeiRepository> _abrir(
  WidgetTester tester,
  SeiDocumentoPendente documento, {
  ProfilePerfil perfil = ProfilePerfil.admin,
  Future<void> Function(FakeDocumentosSeiRepository repo)? preparar,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(perfil));
  addTearDown(auth.dispose);
  final repo = FakeDocumentosSeiRepository(documentosIniciais: [documento]);
  if (preparar != null) await preparar(repo);

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
              onPressed: () => showSeiPendenciaDetalheDialog(context, _docId),
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

/// Botão do RODAPÉ + motivo + confirmar.
Future<void> _cancelarPendentesDoRodape(
  WidgetTester tester,
  int quantidade, {
  String motivo = _motivoDiagnostico,
}) async {
  await tester.tap(find.text('Cancelar $quantidade ${quantidade == 1 ? 'item pendente' : 'itens pendentes'}'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), motivo);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirmar'));
  await tester.pumpAndSettle();
}

Future<void> _expandirHistorico(WidgetTester tester) async {
  final tile = find.text('Histórico de alterações');
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  group('1. cancelamento individual', () {
    test('gera ITEM_CANCELADO, com item_id, documento, autor, data e o motivo', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1), _item(2)]),
        ],
      );

      await repo.cancelarItem(itemId: 'item-1', motivo: 'Motivo individual');

      final eventos = await repo.listarEventos(_docId);
      expect(eventos, hasLength(1));
      final evento = eventos.single;
      expect(evento.tipo, SeiTipoEventoDocumento.itemCancelado);
      expect(evento.itemId, 'item-1');
      expect(evento.documentoId, _docId);
      expect(evento.autorId, isNotEmpty);
      expect(evento.criadoEm, isNotNull);
      expect(evento.descricao, 'Motivo individual');
    });

    testWidgets('o botão da LINHA chama só o cancelamento individual', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));

      await tester.tap(find.text('Cancelar').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Motivo individual');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(repo.cancelarItemCallCount, 1);
      expect(repo.cancelarPendentesCallCount, 0);
      final eventos = await repo.listarEventos(_docId);
      expect(eventos.map((e) => e.tipo), [SeiTipoEventoDocumento.itemCancelado]);
    });
  });

  group('2. cancelamento em massa com 3 pendentes', () {
    testWidgets('cancela os 3 e grava UM único DOCUMENTO_CANCELADO com item_id nulo', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2), _item(3)]));

      await _cancelarPendentesDoRodape(tester, 3);

      final depois = await repo.obterPorId(_docId);
      expect(depois.itens.map((i) => i.status), everyElement(SeiItemPendenciaStatus.cancelado));
      expect(depois.itens.map((i) => i.motivoCancelamento), everyElement(_motivoDiagnostico));

      final eventos = await repo.listarEventos(_docId);
      expect(eventos, hasLength(1), reason: 'um único evento para a ação, não um por item');
      final evento = eventos.single;
      expect(evento.tipo, SeiTipoEventoDocumento.documentoCancelado);
      expect(evento.itemId, isNull);
      expect(evento.documentoId, _docId);
      expect(evento.autorId, isNotEmpty);
      expect(evento.criadoEm, isNotNull);
      expect(evento.descricao, '3 item(ns) pendente(s) cancelado(s): $_motivoDiagnostico');
      expect(eventos.where((e) => e.tipo == SeiTipoEventoDocumento.itemCancelado), isEmpty);
    });
  });

  group('3. cancelamento em massa com apenas 1 pendente', () {
    testWidgets('continua sendo DOCUMENTO_CANCELADO — não degrada para cancelamento individual', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1)]));

      await _cancelarPendentesDoRodape(tester, 1);

      // Caminho executado: o do RODAPÉ, nunca o individual.
      expect(repo.cancelarPendentesCallCount, 1);
      expect(repo.cancelarItemCallCount, 0, reason: 'nenhuma otimização "se restar 1, cancelar individual"');

      final eventos = await repo.listarEventos(_docId);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipo, SeiTipoEventoDocumento.documentoCancelado);
      expect(eventos.single.itemId, isNull);
      expect(eventos.single.descricao, '1 item(ns) pendente(s) cancelado(s): $_motivoDiagnostico');
      expect(eventos.any((e) => e.tipo == SeiTipoEventoDocumento.itemCancelado), isFalse);
    });
  });

  group('4. 1 cancelado + 1 pendente', () {
    testWidgets('preserva o anterior, cancela só o restante e grava o evento de documento', (tester) async {
      final repo = await _abrir(
        tester,
        _documento([_item(1), _item(2)]),
        preparar: (repo) => repo.cancelarItem(itemId: 'item-1', motivo: 'Cancelado individualmente'),
      );

      await _cancelarPendentesDoRodape(tester, 1);

      final depois = await repo.obterPorId(_docId);
      expect(depois.itens[0].motivoCancelamento, 'Cancelado individualmente');
      expect(depois.itens[1].motivoCancelamento, _motivoDiagnostico);
      expect(depois.situacao, SeiDocumentoSituacao.cancelado);

      // Ordem cronológica (o fake devolve o mais recente primeiro): o
      // auditor distingue "usuário cancelou um item" de "usuário cancelou
      // os pendentes do documento".
      final eventos = (await repo.listarEventos(_docId)).reversed.toList();
      expect(eventos.map((e) => e.tipo), [
        SeiTipoEventoDocumento.itemCancelado,
        SeiTipoEventoDocumento.documentoCancelado,
      ]);
      expect(eventos[0].itemId, 'item-1');
      expect(eventos[1].itemId, isNull);
    });
  });

  group('5. documento com 0 pendentes', () {
    testWidgets('não oferece cancelar (linha nem rodapé) e não oferece edição', (tester) async {
      await _abrir(
        tester,
        _documento([
          _item(1, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'A'),
          _item(2, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'B'),
        ]),
      );

      expect(find.textContaining('item(ns) pendente(s)'), findsNothing, reason: 'sem botão de rodapé');
      expect(find.text('Cancelar'), findsNothing, reason: 'sem botão por linha');
      expect(find.text('Editar documento'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Documento encerrado: não há itens pendentes. Somente consulta e histórico.'), findsOneWidget);
    });

    test('documento encerrado (0 pendentes), mesmo sem concluído: encerrado e sem edição', () {
      final doc = _documento([
        _item(1, status: SeiItemPendenciaStatus.cancelado),
        _item(2, status: SeiItemPendenciaStatus.cancelado),
      ]);
      expect(doc.encerrado, isTrue);
      expect(doc.podeSerEditado, isTrue, reason: 'a regra do concluído continua separada');
      expect(doc.permiteEdicao, isFalse);
    });

    test('a proteção espelhada do backend recusa editar documento encerrado (fake)', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([
            _item(1, status: SeiItemPendenciaStatus.cancelado),
            _item(2, status: SeiItemPendenciaStatus.cancelado),
          ]),
        ],
      );

      await expectLater(
        repo.editarDocumento(
          documentoId: _docId,
          versaoEsperada: 1,
          motivo: 'Tentativa',
          assunto: () => 'Novo assunto',
        ),
        throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()),
      );
      expect((await repo.obterPorId(_docId)).assunto, 'TESTE AUTOMATIZADO — EDIÇÃO CONFIRMADA', reason: 'nada mudou');
    });
  });

  group('6. documento totalmente cancelado continua consultável', () {
    testWidgets('itens e histórico visíveis, sem edição — inclusive após cancelar em massa', (tester) async {
      final repo = await _abrir(
        tester,
        _documento([_item(1), _item(2)]),
        preparar: (repo) => repo.cancelarItem(itemId: 'item-1', motivo: 'Cancelado individualmente'),
      );
      await _cancelarPendentesDoRodape(tester, 1);

      // Consulta: cabeçalho, contadores, itens e situação continuam na tela.
      expect(find.text('999999/2026/TESTE-PROMPT1137'), findsOneWidget);
      expect(find.text('2 item(ns) — 0 pendente(s), 0 concluído(s), 2 cancelado(s)'), findsOneWidget);
      expect(find.text('900000001'), findsWidgets);
      expect(find.text('900000002'), findsWidgets);

      // Histórico: os dois tipos de evento aparecem, distintos.
      await _expandirHistorico(tester);
      expect(find.text('Item cancelado'), findsOneWidget);
      expect(find.text('Itens pendentes cancelados'), findsOneWidget);
      expect(find.text('1 item(ns) pendente(s) cancelado(s): $_motivoDiagnostico'), findsOneWidget);

      // Nada de edição nem de novas ações de cancelamento.
      expect(find.text('Editar documento'), findsNothing);
      expect(find.textContaining('item(ns) pendente(s)'), findsWidgets, reason: 'só o texto do evento e o resumo');
      expect(find.widgetWithText(OutlinedButton, 'Cancelar 1 item pendente'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
      expect((await repo.obterPorId(_docId)).encerrado, isTrue);
    });
  });

  group('regras de edição preservadas', () {
    testWidgets('documento com pendentes e nenhum concluído: "Editar documento" visível e habilitado', (tester) async {
      await _abrir(tester, _documento([_item(1), _item(2)]));

      final botao = find.widgetWithText(TextButton, 'Editar documento');
      expect(botao, findsOneWidget);
      expect(tester.widget<TextButton>(botao).onPressed, isNotNull);
    });

    testWidgets('com item concluído e ainda pendente: botão visível, DESABILITADO (bloqueio existente)', (
      tester,
    ) async {
      await _abrir(
        tester,
        _documento([_item(1), _item(2)]),
        preparar: (repo) async => repo.marcarItemConcluidoParaTeste('item-1', movimentacaoId: 'mov-1'),
      );

      final botao = find.widgetWithText(TextButton, 'Editar documento');
      expect(botao, findsOneWidget);
      expect(tester.widget<TextButton>(botao).onPressed, isNull);
    });

    testWidgets('concluído e 0 pendentes (encerrado): sem botão de edição', (tester) async {
      await _abrir(
        tester,
        _documento([_item(1), _item(2, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'X')]),
        preparar: (repo) async => repo.marcarItemConcluidoParaTeste('item-1', movimentacaoId: 'mov-1'),
      );

      expect(find.text('Editar documento'), findsNothing);
    });

    testWidgets('perfil CONSULTA nunca vê edição nem cancelamento', (tester) async {
      await _abrir(tester, _documento([_item(1), _item(2)]), perfil: ProfilePerfil.consulta);

      expect(find.text('Editar documento'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.textContaining('item(ns) pendente(s)'), findsNothing);
    });
  });
}
