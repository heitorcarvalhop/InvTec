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
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../auth/fake_auth_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// Cancelamento em MASSA de pendências SEI.
///
/// Só repositório fake e funções puras: nenhum cancelamento real, nenhuma
/// chamada ao Supabase. O bug real (documento fictício `999999/2026/
/// TESTE-PROMPT1137`: 1 cancelado + 1 pendente → "Não foi possível concluir
/// a ação") escondia o erro original; estes testes cobrem os quatro
/// desfechos possíveis de uma escrita — sucesso, RPC recusada, RPC ok +
/// releitura falha e resultado incerto — e os cenários pedidos.
const _docId = 'doc-ficticio';

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

Profile _perfil() => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

Future<FakeDocumentosSeiRepository> _abrir(
  WidgetTester tester,
  SeiDocumentoPendente documento, {
  Future<void> Function(FakeDocumentosSeiRepository repo)? preparar,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil());
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

/// Clica no botão em massa, informa o [motivo] e confirma.
Future<void> _cancelarTodosOsPendentes(
  WidgetTester tester,
  int quantidade, {
  String motivo = 'Despacho revogado',
}) async {
  await tester.tap(find.text('Cancelar $quantidade ${quantidade == 1 ? 'item pendente' : 'itens pendentes'}'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), motivo);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirmar'));
  await tester.pumpAndSettle();
}

Finder _resumo(int itens, int pendentes, int concluidos, int cancelados) =>
    find.text('$itens item(ns) — $pendentes pendente(s), $concluidos concluído(s), $cancelados cancelado(s)');

void main() {
  group('1. documento com 2 itens pendentes → cancelar todos', () {
    testWidgets('cancela os dois, atualiza contadores e situação, grava UM evento com o motivo', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));
      expect(_resumo(2, 2, 0, 0), findsOneWidget);

      await _cancelarTodosOsPendentes(tester, 2, motivo: 'Despacho revogado');

      // Interface atualizada DEPOIS do sucesso.
      expect(_resumo(2, 0, 0, 2), findsOneWidget);
      expect(find.text('Cancelar 2 itens pendentes'), findsNothing, reason: 'nada mais a cancelar em massa');
      expect(find.text(mensagemSeiEscritaRecusada), findsNothing);
      expect(find.text(mensagemSeiEscritaIncerta), findsNothing);

      final depois = await repo.obterPorId(_docId);
      expect(depois.itens.map((i) => i.status), everyElement(SeiItemPendenciaStatus.cancelado));
      expect(depois.itens.map((i) => i.motivoCancelamento), everyElement('Despacho revogado'));
      expect(depois.totalPendentes, 0);
      expect(depois.totalCancelados, 2);
      expect(depois.situacao, SeiDocumentoSituacao.cancelado);
      expect(depois.versao, 2, reason: 'versão incrementada uma vez');
      expect(repo.cancelarPendentesCallCount, 1);

      final eventos = await repo.listarEventos(_docId);
      expect(eventos, hasLength(1));
      expect(eventos.single.tipo, SeiTipoEventoDocumento.documentoCancelado);
      expect(eventos.single.descricao, '2 item(ns) pendente(s) cancelado(s): Despacho revogado');
    });
  });

  group('2. 1 cancelado + 1 pendente (o caso real do documento fictício)', () {
    testWidgets('cancela SÓ o restante e preserva o item já cancelado', (tester) async {
      final repo = await _abrir(
        tester,
        _documento([_item(1), _item(2)]),
        // Reproduz o passo anterior do teste real: cancelamento INDIVIDUAL do item 1.
        preparar: (repo) => repo.cancelarItem(itemId: 'item-1', motivo: 'Motivo do cancelamento individual'),
      );
      expect(_resumo(2, 1, 0, 1), findsOneWidget, reason: '1 pendente, 0 concluídos, 1 cancelado');
      // Singular correto no botão de cancelamento em
      // massa: "1 item pendente", nunca "1 item(ns) pendente(s)" (o
      // resumo do cabeçalho, "2 item(ns) — ...", é outro texto, fora do
      // escopo deste ajuste — continua com o formato de sempre).
      expect(find.text('Cancelar 1 item pendente'), findsOneWidget);
      expect(find.text('Cancelar 1 item(ns) pendente(s)'), findsNothing);

      await _cancelarTodosOsPendentes(tester, 1, motivo: 'Cancelamento do restante');

      expect(_resumo(2, 0, 0, 2), findsOneWidget);
      expect(find.text(mensagemSeiEscritaRecusada), findsNothing);

      final depois = await repo.obterPorId(_docId);
      expect(
        depois.itens[0].motivoCancelamento,
        'Motivo do cancelamento individual',
        reason: 'item 1 NÃO é sobrescrito',
      );
      expect(depois.itens[1].status, SeiItemPendenciaStatus.cancelado);
      expect(depois.itens[1].motivoCancelamento, 'Cancelamento do restante');
      expect(depois.situacao, SeiDocumentoSituacao.cancelado);

      final eventos = await repo.listarEventos(_docId);
      expect(
        eventos.map((e) => e.tipo),
        containsAll([SeiTipoEventoDocumento.itemCancelado, SeiTipoEventoDocumento.documentoCancelado]),
      );
      final massa = eventos.singleWhere((e) => e.tipo == SeiTipoEventoDocumento.documentoCancelado);
      expect(massa.descricao, '1 item(ns) pendente(s) cancelado(s): Cancelamento do restante');
    });

    testWidgets('não toca item CONCLUÍDO', (tester) async {
      final repo = await _abrir(
        tester,
        _documento([_item(1), _item(2), _item(3)]),
        preparar: (repo) async => repo.marcarItemConcluidoParaTeste('item-1', movimentacaoId: 'mov-1'),
      );

      await _cancelarTodosOsPendentes(tester, 2);

      final depois = await repo.obterPorId(_docId);
      expect(depois.itens.map((i) => i.status), [
        SeiItemPendenciaStatus.concluido,
        SeiItemPendenciaStatus.cancelado,
        SeiItemPendenciaStatus.cancelado,
      ]);
      expect(depois.situacao, SeiDocumentoSituacao.encerradoParcialmente);
      expect(_resumo(3, 0, 1, 2), findsOneWidget);
    });
  });

  group('3. documento sem itens pendentes → não repete cancelamentos', () {
    testWidgets('o botão em massa nem aparece', (tester) async {
      await _abrir(
        tester,
        _documento([_item(1, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'Antes')]),
      );

      expect(find.textContaining('item(ns) pendente(s)'), findsNothing);
    });

    test('mesmo se chamado direto, não altera itens, não sobe a versão e não grava evento', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1, status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: 'Antes')]),
        ],
      );

      final resultado = await repo.cancelarPendentesDoDocumento(documentoId: _docId, motivo: 'Outra tentativa');

      expect(resultado.versao, 1);
      expect(resultado.itens.single.motivoCancelamento, 'Antes', reason: 'motivo original preservado');
      expect(await repo.listarEventos(_docId), isEmpty);
    });
  });

  group('4. falha da RPC → erro sem sucesso', () {
    testWidgets('mostra a recusa, NÃO altera a tela e expõe o erro técnico original em "Detalhes técnicos"', (
      tester,
    ) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));
      repo.falhaNaEscrita = const SeiEscritaFalhouException(
        operacao: 'cancelar_pendentes_documento_sei',
        mensagem: 'relation "tmp_itens_cancelados" does not exist',
        codigo: '42P01',
        detalhes: 'detalhe do servidor',
        dica: 'dica do servidor',
      );

      await _cancelarTodosOsPendentes(tester, 2);

      expect(find.text(mensagemSeiEscritaRecusada), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text(mensagemSeiEscritaRecusada)),
        findsOneWidget,
        reason: 'o aviso fica DENTRO do diálogo (um SnackBar apareceria atrás da barreira modal, sem receber cliques)',
      );
      expect(_resumo(2, 2, 0, 0), findsOneWidget, reason: 'contadores inalterados: nada foi cancelado');
      expect(find.text('Cancelar 2 itens pendentes'), findsOneWidget, reason: 'ainda há o que cancelar');
      expect((await repo.obterPorId(_docId)).totalPendentes, 2);
      expect(await repo.listarEventos(_docId), isEmpty);

      await tester.tap(find.text('Detalhes técnicos'));
      await tester.pumpAndSettle();
      expect(find.text('Ocultar detalhes técnicos'), findsOneWidget);
      final texto = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(texto, contains('Operação: cancelar_pendentes_documento_sei'));
      expect(texto, contains('Código: 42P01'));
      expect(texto, contains('Mensagem: relation "tmp_itens_cancelados" does not exist'));
      expect(texto, contains('Detalhes: detalhe do servidor'));
      expect(texto, contains('Dica: dica do servidor'));
    });

    testWidgets('falha na comunicação (resultado incerto): relê o documento e NÃO manda repetir às cegas', (
      tester,
    ) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));
      repo.falhaNaEscrita = Exception('SocketException: conexão perdida');

      await _cancelarTodosOsPendentes(tester, 2);

      expect(find.text(mensagemSeiEscritaIncerta), findsOneWidget);
      expect(find.textContaining('Tente novamente'), findsNothing);
      // Releu o documento: o estado mostrado é o real.
      expect(_resumo(2, 2, 0, 0), findsOneWidget);
    });
  });

  group('5. RPC bem-sucedida + falha no refresh → não sugere repetir', () {
    testWidgets('avisa que provavelmente concluiu, manda conferir e mostra o estado real', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));
      repo.falharRecargaAposEscrita = true;

      await _cancelarTodosOsPendentes(tester, 2);

      expect(find.text(mensagemSeiEscritaConcluidaRecargaFalhou), findsOneWidget);
      expect(mensagemSeiEscritaConcluidaRecargaFalhou, isNot(contains('Tente novamente')));
      expect(mensagemSeiEscritaConcluidaRecargaFalhou, contains('NÃO repita'));
      // A escrita foi aplicada e a tela foi relida logo depois.
      expect(_resumo(2, 0, 0, 2), findsOneWidget);
      expect(repo.cancelarPendentesCallCount, 1, reason: 'a UI não repetiu a escrita');
    });

    test(
      'executarEscritaSeiComRecarga: RPC ok + releitura falha → exceção específica com a operação e o documento',
      () async {
        Object? causa;
        try {
          await executarEscritaSeiComRecarga(
            operacao: 'cancelar_pendentes_documento_sei',
            escrever: () async => _docId,
            recarregar: (_) async => throw StateError('falha ao reler'),
          );
        } on SeiEscritaConcluidaRecargaFalhouException catch (e) {
          causa = e;
          expect(e.operacao, 'cancelar_pendentes_documento_sei');
          expect(e.documentoId, _docId);
          expect(e.cause, isA<StateError>());
        }
        expect(causa, isNotNull);
      },
    );
  });

  group('erro técnico original preservado (função pura, sem Supabase)', () {
    test('PostgrestException vira SeiEscritaFalhouException com código, mensagem, detalhes e dica', () async {
      var recarregou = false;
      try {
        await executarEscritaSeiComRecarga(
          operacao: 'cancelar_pendentes_documento_sei',
          escrever: () async => throw const PostgrestException(
            message: 'permission denied to create temporary table',
            code: '42501',
            details: 'detalhe',
            hint: 'dica',
          ),
          recarregar: (_) async {
            recarregou = true;
            return _documento([]);
          },
        );
        fail('devia lançar');
      } on SeiEscritaFalhouException catch (e) {
        expect(e.operacao, 'cancelar_pendentes_documento_sei');
        expect(e.codigo, '42501');
        expect(e.detalhes, 'detalhe');
        expect(e.dica, 'dica');
        expect(e.textoTecnico, contains('Código: 42501'));
        expect(e.cause, isA<PostgrestException>());
      }
      expect(recarregou, isFalse, reason: 'RPC falhou: nem tenta reler');
    });

    test('exceção que não é do Postgrest (ex.: rede) passa sem virar "recusa" — resultado incerto', () async {
      await expectLater(
        executarEscritaSeiComRecarga(
          operacao: 'cancelar_item_sei_pendente',
          escrever: () async => throw Exception('rede'),
          recarregar: (_) async => _documento([]),
        ),
        throwsA(
          isA<Exception>().having((e) => e, 'não é SeiEscritaFalhouException', isNot(isA<SeiEscritaFalhouException>())),
        ),
      );
    });

    test('sucesso completo devolve o documento relido', () async {
      final documento = _documento([_item(1)]);
      final resultado = await executarEscritaSeiComRecarga(
        operacao: 'cancelar_pendentes_documento_sei',
        escrever: () async => _docId,
        recarregar: (id) async {
          expect(id, _docId);
          return documento;
        },
      );
      expect(resultado, same(documento));
    });
  });

  group('6. motivo obrigatório e registrado no evento', () {
    testWidgets('sem motivo (vazio ou só espaços) o Confirmar não habilita e nada é cancelado', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));

      await tester.tap(find.text('Cancelar 2 itens pendentes'));
      await tester.pumpAndSettle();

      FilledButton confirmar() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'));
      expect(confirmar().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '    ');
      await tester.pumpAndSettle();
      expect(confirmar().onPressed, isNull, reason: 'só espaços não vale como motivo');

      await tester.enterText(find.byType(TextField), 'Motivo real');
      await tester.pumpAndSettle();
      expect(confirmar().onPressed, isNotNull);

      // "Voltar" não cancela nada.
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(repo.cancelarPendentesCallCount, 0);
      expect((await repo.obterPorId(_docId)).totalPendentes, 2);
    });

    testWidgets('o motivo digitado (aparado) chega ao repositório e ao evento de auditoria', (tester) async {
      final repo = await _abrir(tester, _documento([_item(1), _item(2)]));

      await _cancelarTodosOsPendentes(tester, 2, motivo: '  Duplicidade com o despacho 578  ');

      final eventos = await repo.listarEventos(_docId);
      expect(eventos.single.descricao, contains('Duplicidade com o despacho 578'));
      final depois = await repo.obterPorId(_docId);
      expect(depois.itens.map((i) => i.motivoCancelamento), everyElement('Duplicidade com o despacho 578'));
    });
  });

  group('7. contadores e situação depois do cancelamento', () {
    test('situação agregada: pendente → encerrado/cancelado conforme os itens', () {
      expect(_documento([_item(1), _item(2)]).situacao, SeiDocumentoSituacao.pendente);
      expect(
        _documento([_item(1, status: SeiItemPendenciaStatus.cancelado), _item(2)]).situacao,
        SeiDocumentoSituacao.pendente,
        reason: '1 cancelado + 1 pendente continua PENDENTE',
      );
      expect(
        _documento([
          _item(1, status: SeiItemPendenciaStatus.cancelado),
          _item(2, status: SeiItemPendenciaStatus.cancelado),
        ]).situacao,
        SeiDocumentoSituacao.cancelado,
      );
    });
  });
}
