import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_conclusao_lote_controller.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

import '../../auth/fake_auth_repository.dart';
import '../../patrimonios/fake_patrimonio_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// Auditoria de operações durante um LOTE PENDENTE: os handlers de escrita
/// (conclusão individual, cancelamento individual, cancelamento em massa,
/// edição do documento) precisam CONSULTAR o estado de uma decisão de lote
/// pendente/em conflito para o documento aberto
/// (`estadoLote.temTentativaPendente`) antes de permitir a escrita — nunca
/// basta desabilitar o botão na tela, pois nada impediria um callback
/// antigo de disparar a escrita de qualquer jeito. O aviso textual também
/// precisa comparar `documentoId`: uma tentativa pendente do Documento A
/// nunca pode "vazar" para a tela do Documento B.
///
/// Este arquivo testa exclusivamente essas duas garantias — NENHUM teste
/// aqui fala com o Supabase, usa o Despacho 577 ou toca a conclusão em
/// lote/individual "de verdade" (tudo via `FakeDocumentosSeiRepository`/
/// `FakePatrimonioRepository`).
const _docId = 'doc-1';
const _docId2 = 'doc-2';

Profile _perfil(ProfilePerfil perfil) => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

SeiItemPendente _item({
  required int linha,
  String documentoId = _docId,
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: documentoId,
    linha: linha,
    patrimonioId: 'pat-$linha',
    numeroPatrimonio: SeiValorCorrigivel(original: 'PAT-$linha'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    origemSetorId: 'setor-getec',
    origemSetorNome: 'Gerencia de Tecnologia',
    destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
    destinoSetorId: 'setor-ntat',
    destinoSetorNome: 'Nucleo de Testes Automatizados',
    numeroChamado: const SeiValorCorrigivel(original: null),
    equipamentoTexto: SeiValorCorrigivel(original: 'Notebook $linha'),
    decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
    decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
    status: status,
    criadoEm: DateTime.utc(2026, 1, 1),
  );
}

SeiDocumentoPendente _documento(List<SeiItemPendente> itens, {String id = _docId, int versao = 1}) {
  return SeiDocumentoPendente.fromItens(
    id: id,
    numeroDocumentoSei: '99999999',
    numeroDocumentoFormatado: '999999/2026/TESTE',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho.pdf',
    hashSha256: 'hash',
    versao: versao,
    criadoEm: DateTime.utc(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Fulana',
    itens: itens,
  );
}

PatrimonioDetalhe _patrimonio(int linha) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'pat-$linha',
      numeroPatrimonio: 'PAT-$linha',
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-getec', // coerente com a origem — sempre elegível.
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'Gerencia de Tecnologia',
  );
}

class _Cenario {
  _Cenario(this.repo, this.patrimonios);
  final FakeDocumentosSeiRepository repo;
  final FakePatrimonioRepository patrimonios;
}

/// Abre `_SeiPendenciaDetalheDialog` (o MESMO ponto de entrada real) para
/// [documentos] — todos pré-carregados no mesmo fake, para os testes de
/// "documento diferente" abrirem o outro sem reconstruir tudo.
Future<_Cenario> _abrirCenario(
  WidgetTester tester, {
  required List<SeiDocumentoPendente> documentos,
  List<PatrimonioDetalhe>? patrimonios,
  String Function()? gerarLoteId,
}) async {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(ProfilePerfil.admin));
  addTearDown(auth.dispose);
  final repo = FakeDocumentosSeiRepository(documentosIniciais: documentos);
  final fakePatrimonios = FakePatrimonioRepository(
    itens: patrimonios ?? [for (final d in documentos) for (final i in d.itens) _patrimonio(i.linha)],
  );

  // Mesmo padrão de `sei_editar_documento_dialog_test.dart`:
  // no viewport padrão de teste (800x600) o diálogo de detalhe some por
  // trás de overflow/scroll ao empilhar o cabeçalho + a lista de itens,
  // fazendo `ensureVisible`/`tap` falharem por hit-test — Windows/desktop
  // real nunca tem esse problema, é só o tamanho pequeno do harness.
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        documentosSeiRepositoryProvider.overrideWithValue(repo),
        patrimonioRepositoryProvider.overrideWithValue(fakePatrimonios),
        if (gerarLoteId != null)
          seiConclusaoLoteControllerProvider.overrideWith(() => SeiConclusaoLoteController(gerarLoteId: gerarLoteId)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (final d in documentos)
                  ElevatedButton(
                    onPressed: () => showSeiPendenciaDetalheDialog(context, d.id),
                    child: Text('abrir ${d.id}'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return _Cenario(repo, fakePatrimonios);
}

Future<void> _abrirDocumento(WidgetTester tester, String documentoId) async {
  await tester.ensureVisible(find.text('abrir $documentoId'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('abrir $documentoId'));
  await tester.pumpAndSettle();
}

/// Leva a decisão de lote CONGELADA (global) do item de linha [itemLinha] a
/// [SeiConclusaoLoteStatus.resultadoDesconhecido] — mesma choreografia de
/// `sei_concluir_lote_dialog_test.dart`: seleciona o item, "Concluir
/// selecionados", confirma com um timeout simulado injetado no fake, e
/// fecha o painel de resultado desconhecido (nunca `reiniciar()`,
/// preservando a tentativa — a mesma coisa que o botão "Fechar (mantém a
/// tentativa pendente)" faz).
Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _forcarResultadoDesconhecido(WidgetTester tester, FakeDocumentosSeiRepository repo, {int itemLinha = 1}) async {
  repo.falhaNaConclusao = Exception('timeout simulado');
  await _tocar(tester, find.byKey(Key('sei-item-selecao-item-$itemLinha')));
  await _tocar(tester, find.byKey(const Key('sei-botao-concluir-selecionados')));
  await _tocar(tester, find.byKey(const Key('sei-concluir-lote-checkbox-entrega')));
  await _tocar(tester, find.byKey(const Key('sei-concluir-lote-botao-confirmar')));
  expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget, reason: 'pré-condição do cenário');
  repo.falhaNaConclusao = null;
  await _tocar(tester, find.byKey(const Key('sei-concluir-lote-fechar')));
}

const _textoAvisoDesconhecido = 'conclusão em lote com resultado ainda desconhecido';
const _textoAvisoConflito = 'CONFLITO DE INTEGRIDADE';

void main() {
  group('timeout inicial (resultadoDesconhecido): todas as escritas do MESMO documento bloqueadas', () {
    testWidgets('conclusão individual bloqueada — nenhum diálogo de confirmação chega a abrir', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);

      expect(find.textContaining(_textoAvisoDesconhecido), findsOneWidget);
      // "Concluir entrega" sumiu da lista inteira (item-1 e item-2, ambos
      // ainda PENDENTES — nenhum foi de fato concluído pelo servidor).
      expect(find.widgetWithText(FilledButton, 'Concluir entrega'), findsNothing);
    });

    testWidgets('cancelamento individual bloqueado — nenhum diálogo de motivo chega a abrir', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);

      expect(find.widgetWithText(TextButton, 'Cancelar'), findsNothing);
      expect(c.repo.cancelarItemCallCount, 0);
    });

    testWidgets('cancelamento em massa bloqueado', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);

      final botao = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancelar 2 itens pendentes'));
      expect(botao.onPressed, isNull);
      expect(c.repo.cancelarPendentesCallCount, 0);
    });

    testWidgets('edição do documento bloqueada', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);

      final botao = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botao.onPressed, isNull);
      expect(c.repo.editarCallCount, 0);
    });

    testWidgets(
      'nova conclusão em lote bloqueada: "Concluir todos os aptos" reabre o painel PENDENTE, nunca cria uma decisão nova',
      (tester) async {
        final documento = _documento([_item(linha: 1), _item(linha: 2)]);
        final c = await _abrirCenario(tester, documentos: [documento]);
        await _abrirDocumento(tester, _docId);
        await _forcarResultadoDesconhecido(tester, c.repo);

        final chamadasAntes = c.repo.concluirLoteCallCount;
        await _tocar(tester, find.byKey(const Key('sei-botao-concluir-todos-aptos')));

        // Reabre DIRETO no painel da tentativa pendente — nunca a tela de
        // revisão "ocioso" com uma seleção nova.
        expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);
        expect(find.byKey(const Key('sei-concluir-lote-botao-confirmar')), findsNothing);
        expect(c.repo.concluirLoteCallCount, chamadasAntes, reason: 'só reabriu o painel — nenhuma chamada nova');

        await _tocar(tester, find.byKey(const Key('sei-concluir-lote-fechar')));
      },
    );
  });

  group('conflito de integridade: todas as escritas bloqueadas', () {
    /// Leva o documento a `conflitoDeIntegridade`: semeia um registro
    /// DIVERGENTE sob o mesmo `loteId` que o controller vai gerar, tenta
    /// concluir item-1 (timeout simulado), e reconcilia — a reconciliação
    /// encontra o registro (de item-2) sob o mesmo `loteId`, identidade
    /// diferente da decisão local (item-1) → conflito.
    Future<_Cenario> abrirComConflito(WidgetTester tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final repoSemente = FakeDocumentosSeiRepository(
        documentosIniciais: [documento],
        patrimonioRepository: FakePatrimonioRepository(itens: [_patrimonio(1), _patrimonio(2)]),
      );
      await repoSemente.concluirItensLote(
        documentoId: _docId,
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: 'lote-conflito-11-5-12',
        confirmarLimpezaDestino: false,
      );

      final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(ProfilePerfil.admin));
      addTearDown(auth.dispose);
      final fakePatrimonios = FakePatrimonioRepository(itens: [_patrimonio(1)]);

      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            documentosSeiRepositoryProvider.overrideWithValue(repoSemente),
            patrimonioRepositoryProvider.overrideWithValue(fakePatrimonios),
            seiConclusaoLoteControllerProvider.overrideWith(
              () => SeiConclusaoLoteController(gerarLoteId: () => 'lote-conflito-11-5-12'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSeiPendenciaDetalheDialog(context, _docId),
                  child: const Text('abrir doc-1'),
                ),
              ),
            ),
          ),
        ),
      );
      await _tocar(tester, find.text('abrir doc-1'));

      repoSemente.falhaNaConclusao = Exception('timeout simulado');
      await _tocar(tester, find.byKey(const Key('sei-item-selecao-item-1')));
      await _tocar(tester, find.byKey(const Key('sei-botao-concluir-selecionados')));
      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-checkbox-entrega')));
      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-botao-confirmar')));
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      repoSemente.falhaNaConclusao = null;
      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-reconciliar')));
      expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget, reason: 'pré-condição do cenário');

      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-fechar')));

      return _Cenario(repoSemente, fakePatrimonios);
    }

    testWidgets('todas as escritas bloqueadas — individual, massa e edição', (tester) async {
      final c = await abrirComConflito(tester);

      expect(find.textContaining(_textoAvisoConflito), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancelar'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Concluir entrega'), findsNothing);
      // item-2 já foi concluído pela semente direta — só item-1 continua
      // pendente neste documento.
      final botaoMassa = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Cancelar 1 item pendente'),
      );
      expect(botaoMassa.onPressed, isNull);
      final botaoEditar = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botaoEditar.onPressed, isNull);
      expect(c.repo.cancelarItemCallCount, 0);
      expect(c.repo.cancelarPendentesCallCount, 0);
      expect(c.repo.editarCallCount, 0);
    });

    testWidgets('"Concluir todos os aptos" reabre o painel de CONFLITO — nunca retry/reconciliar/nova decisão', (
      tester,
    ) async {
      final c = await abrirComConflito(tester);
      final chamadasAntes = c.repo.concluirLoteCallCount;
      final buscasAntes = c.repo.buscarLotePorIdCallCount;

      await _tocar(tester, find.byKey(const Key('sei-botao-concluir-todos-aptos')));

      expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget);
      // Painel de conflito NUNCA oferece retry/reconciliar (guard já
      // homologado do controller/diálogo) — só "Fechar".
      expect(find.byKey(const Key('sei-concluir-lote-retry')), findsNothing);
      expect(find.byKey(const Key('sei-concluir-lote-reconciliar')), findsNothing);
      expect(c.repo.concluirLoteCallCount, chamadasAntes);
      expect(c.repo.buscarLotePorIdCallCount, buscasAntes);
    });
  });

  group('o aviso persistente não pode ser "fechado", e o bloqueio sobrevive a fechar/reabrir', () {
    testWidgets('fechar o AVISO dispensável (da tentativa incerta) não remove o bloqueio persistente', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);

      // Fechar o painel de "resultado desconhecido" pelo botão "Fechar"
      // (dentro de `_forcarResultadoDesconhecido`) gera um AVISO dispensável
      // (`_AvisoDeAcao`/`_BannerDeAviso`, com um X de tooltip "Fechar aviso")
      // — DIFERENTE do texto persistente sobre o bloqueio (sem botão de
      // fechar) e DIFERENTE do X do topo do diálogo (tooltip "Fechar", que
      // fecha o diálogo inteiro) — usar `find.byTooltip` evita pegar o
      // botão errado (os dois usam o mesmo ícone `Icons.close`).
      await _tocar(tester, find.byTooltip('Fechar aviso'));

      // O bloqueio PERSISTENTE continua intacto.
      expect(find.textContaining(_textoAvisoDesconhecido), findsOneWidget);
      final botaoEditar = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botaoEditar.onPressed, isNull);
    });

    testWidgets('fechar e reabrir o MESMO documento: bloqueio permanece (controller é global)', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);

      // Fecha o diálogo de detalhe inteiro (ícone "Fechar" do topo).
      await _tocar(tester, find.byTooltip('Fechar'));
      expect(find.textContaining(_textoAvisoDesconhecido), findsNothing, reason: 'diálogo fechado');

      await _abrirDocumento(tester, _docId);

      expect(find.textContaining(_textoAvisoDesconhecido), findsOneWidget);
      final botaoEditar = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botaoEditar.onPressed, isNull);
    });
  });

  group('callback antigo disparado durante a pendência: nenhuma chamada de escrita', () {
    testWidgets('um callback de "Cancelar" capturado ANTES do bloqueio, chamado DEPOIS, não escreve nada', (tester) async {
      final documento = _documento([_item(linha: 1)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);

      // Captura o callback ENQUANTO ainda está tudo liberado.
      final cancelarCallback = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar')).onPressed;
      expect(cancelarCallback, isNotNull);

      await _forcarResultadoDesconhecido(tester, c.repo);

      // O botão em si já sumiu da árvore (a lista inteira ficou sem
      // `podeGerenciar`) — mas o callback CAPTURADO antes ainda existe como
      // uma closure comum: dispará-lo agora simula um gesto que já estava
      // "em voo" no exato instante em que o bloqueio começou.
      expect(find.widgetWithText(TextButton, 'Cancelar'), findsNothing);
      cancelarCallback!();
      await tester.pumpAndSettle();

      expect(find.text('Cancelar item'), findsNothing, reason: 'nenhum diálogo de motivo chegou a abrir');
      expect(c.repo.cancelarItemCallCount, 0);
    });
  });

  group('o bloqueio é CONTEXTUAL: nunca vaza para outro documento', () {
    testWidgets('tentativa pendente do Documento A não bloqueia o Documento B', (tester) async {
      final documentoA = _documento([_item(linha: 1, documentoId: _docId)]);
      final documentoB = _documento([_item(linha: 1, documentoId: _docId2)], id: _docId2);
      final c = await _abrirCenario(
        tester,
        documentos: [documentoA, documentoB],
        patrimonios: [_patrimonio(1)], // mesmo `pat-1` reaproveitado pelos dois documentos de teste
      );

      await _abrirDocumento(tester, _docId);
      await _forcarResultadoDesconhecido(tester, c.repo);
      await _tocar(tester, find.byTooltip('Fechar'));

      await _abrirDocumento(tester, _docId2);

      expect(find.textContaining(_textoAvisoDesconhecido), findsNothing, reason: 'aviso não deve vazar entre documentos');
      final botaoEditar = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botaoEditar.onPressed, isNotNull, reason: 'Documento B continua liberado normalmente');
      final cancelar = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'));
      expect(cancelar.onPressed, isNotNull);
    });
  });

  group('sucesso confirmado: recarga coerente e bloqueio liberado', () {
    testWidgets('reconciliação encontra o registro aplicado: painel de sucesso, documento recarregado, escritas liberadas', (
      tester,
    ) async {
      final documento = _documento([_item(linha: 1)]);
      final c = await _abrirCenario(tester, documentos: [documento], gerarLoteId: () => 'lote-sucesso-11-5-12');
      await _abrirDocumento(tester, _docId);

      c.repo.falhaNaConclusao = Exception('timeout simulado');
      await _tocar(tester, find.byKey(const Key('sei-item-selecao-item-1')));
      await _tocar(tester, find.byKey(const Key('sei-botao-concluir-selecionados')));
      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-checkbox-entrega')));
      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-botao-confirmar')));
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      // A tentativa original, na verdade, TINHA sido aplicada no servidor.
      c.repo.falhaNaConclusao = null;
      await c.repo.concluirItensLote(
        documentoId: _docId,
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-sucesso-11-5-12',
        confirmarLimpezaDestino: false,
      );

      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-reconciliar')));
      expect(find.byKey(const Key('sei-concluir-lote-sucesso')), findsOneWidget);

      await _tocar(tester, find.byKey(const Key('sei-concluir-lote-fechar')));

      // Bloqueio liberado...
      expect(find.textContaining(_textoAvisoDesconhecido), findsNothing);
      expect(find.textContaining(_textoAvisoConflito), findsNothing);
      // ...e o documento foi recarregado: 0 pendentes (item-1 concluiu de
      // verdade), então nem a linha de ações em lote aparece mais.
      expect(find.textContaining('0 pendente(s)'), findsOneWidget);
      expect(find.byKey(const Key('sei-botao-concluir-todos-aptos')), findsNothing);
    });
  });

  group('sem tentativa pendente, as regras individuais existentes continuam intactas', () {
    testWidgets('cancelar item individual continua funcionando normalmente (sem lote envolvido)', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final c = await _abrirCenario(tester, documentos: [documento]);
      await _abrirDocumento(tester, _docId);

      await _tocar(tester, find.widgetWithText(TextButton, 'Cancelar').first);
      await tester.enterText(find.byType(TextField).last, 'motivo de teste');
      await _tocar(tester, find.widgetWithText(FilledButton, 'Confirmar'));

      expect(c.repo.cancelarItemCallCount, 1);
    });
  });
}
