import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_conclusao_lote_controller.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_concluir_lote_dialog.dart' show textoAvisoLote;

import '../features/movimentacoes/sei/fake_documentos_sei_repository.dart';
import 'sei_lote_preview_app.dart';

/// Regressão para um bug relatado ao validar a prévia
/// Windows: "Preparar conflito de integridade" deixava corretamente o
/// controller em `resultadoDesconhecido`, mas "Abrir documento" recusava
/// abrir ("Já há uma tentativa em andamento"), impedindo demonstrar
/// "Concluir selecionados"/"Concluir todos os aptos" → "Consultar o que
/// aconteceu" sobre a tentativa preparada.
///
/// Causa: `_abrirCenario` (em `sei_lote_preview_app.dart`) exigia o
/// controller OCIOSO em TODA chamada — inclusive quando `modoFalha` é
/// `null` (isto é, quando o clique é só "abrir o documento", sem preparar
/// nada novo). A correção distingue as duas coisas: só PREPARAR um
/// cenário novo (`modoFalha` não-nulo) continua exigindo ocioso; abrir o
/// documento existente nunca é bloqueado — mesmo comportamento do app
/// real, onde quem bloqueia escritas é o próprio diálogo,
/// não a abertura da tela.
///
/// Este teste NUNCA fala com o Supabase, usa o Despacho 577 ou toca a
/// conclusão real — é a MESMA prévia local (`SeiLotePreviewRoot`), só
/// dirigida por `flutter_test` em vez de `flutter run`.
void main() {
  testWidgets(
    'Preparar conflito → resultadoDesconhecido → Abrir documento → Concluir todos os aptos → Consultar → '
    'conflitoDeIntegridade (loteId preservado, nenhuma nova conclusão)',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SeiLotePreviewRoot());
      await tester.pumpAndSettle();

      // 1. Preparar conflito de integridade — leva o controller a
      // `resultadoDesconhecido` (a escolha original da RPC, timeout
      // simulado) e semeia um registro DIVERGENTE sob o MESMO `loteId`.
      final botaoPreparar = find.textContaining('Preparar conflito de integridade');
      await tester.ensureVisible(botaoPreparar);
      await tester.pumpAndSettle();
      await tester.tap(botaoPreparar);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(botaoPreparar));
      final repo = container.read(documentosSeiRepositoryProvider) as FakeDocumentosSeiRepository;

      final estadoAposPreparar = container.read(seiConclusaoLoteControllerProvider);
      expect(
        estadoAposPreparar.status,
        SeiConclusaoLoteStatus.resultadoDesconhecido,
        reason: 'pré-condição do cenário',
      );
      final loteIdOriginal = estadoAposPreparar.decisao!.loteId;
      final itemIdsOriginais = estadoAposPreparar.decisao!.itemIds;
      final chamadasAposPreparar = repo.concluirLoteCallCount;

      // 2. Abrir documento — ESTE é o passo que falhava antes da correção
      // ("Já há uma tentativa em andamento" impedia o diálogo de abrir).
      // `textContaining` sozinho casaria DUAS vezes (o botão e a frase
      // explicativa "Diferente do botão 'Abrir documento' acima..."), então
      // usa o rótulo completo e ÚNICO do botão.
      final botaoAbrir = find.text('Abrir documento (sempre permitido, mesmo com tentativa pendente)');
      await tester.ensureVisible(botaoAbrir);
      await tester.pumpAndSettle();
      await tester.tap(botaoAbrir);
      await tester.pumpAndSettle();

      expect(find.text('Já há uma tentativa em andamento'), findsNothing, reason: 'bug relatado na prévia');
      // O documento abriu de verdade — e o bloqueio operacional
      // continua ativo (mesmo documento, mesma tentativa).
      expect(find.textContaining('resultado ainda desconhecido'), findsOneWidget);

      // 3. "Concluir todos os aptos" — com o documento bloqueado,
      // redireciona DIRETO para o painel da tentativa pendente,
      // nunca cria uma seleção/decisão nova.
      await tester.tap(find.byKey(const Key('sei-botao-concluir-todos-aptos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-botao-confirmar')), findsNothing);

      // 4. "Consultar o que aconteceu" — encontra o registro DIVERGENTE
      // semeado no passo 1, sob o MESMO `loteId` → conflito de integridade.
      await tester.tap(find.byKey(const Key('sei-concluir-lote-reconciliar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget);

      final estadoFinal = container.read(seiConclusaoLoteControllerProvider);
      expect(estadoFinal.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      // loteId e os itens da decisão ORIGINAL (preparada no passo 1)
      // continuam intocados — nenhuma decisão nova foi criada ao abrir o
      // documento nem ao clicar em "Concluir todos os aptos".
      expect(estadoFinal.decisao!.loteId, loteIdOriginal, reason: 'loteId original preservado');
      expect(estadoFinal.decisao!.itemIds, itemIdsOriginais, reason: 'nenhuma decisão nova substituiu a original');
      // Nenhuma chamada nova a `concluirItensLote` — só a leitura por
      // `buscarLotePorId` (reconciliar), exatamente como no app real.
      expect(repo.concluirLoteCallCount, chamadasAposPreparar, reason: 'nenhuma nova conclusão foi executada');
    },
  );

  testWidgets('PREPARAR outro cenário continua bloqueado enquanto houver tentativa pendente (requisito 6, inalterado)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SeiLotePreviewRoot());
    await tester.pumpAndSettle();

    // Pré-condição: alguma tentativa pendente já existe (reaproveita
    // "Preparar conflito de integridade", que já dirige `confirmar()`
    // programaticamente e deixa o controller em `resultadoDesconhecido`
    // SEM precisar interagir dentro do diálogo de detalhe).
    final botaoPreparar = find.textContaining('Preparar conflito de integridade');
    await tester.ensureVisible(botaoPreparar);
    await tester.pumpAndSettle();
    await tester.tap(botaoPreparar);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(botaoPreparar));
    expect(container.read(seiConclusaoLoteControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

    final botaoRecusa = find.textContaining('Recusa conhecida');
    await tester.ensureVisible(botaoRecusa);
    await tester.pumpAndSettle();
    await tester.tap(botaoRecusa);
    await tester.pumpAndSettle();

    // Continua bloqueado: preparar um cenário NOVO por cima de uma
    // tentativa pendente não resolvida nunca é permitido.
    expect(find.text('Já há uma tentativa em andamento'), findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(
      container.read(seiConclusaoLoteControllerProvider).status,
      SeiConclusaoLoteStatus.resultadoDesconhecido,
      reason: 'a tentativa original nunca foi substituída',
    );
  });

  testWidgets(
    'a prévia mostra o aviso FICTÍCIO/em memória, nunca o aviso de movimentação REAL do app operacional',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SeiLotePreviewRoot());
      await tester.pumpAndSettle();

      final botaoAbrir = find.text('Abrir documento (sempre permitido, mesmo com tentativa pendente)');
      await tester.ensureVisible(botaoAbrir);
      await tester.pumpAndSettle();
      await tester.tap(botaoAbrir);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sei-botao-concluir-todos-aptos')));
      await tester.pumpAndSettle();

      expect(find.textContaining('EM MEMÓRIA'), findsOneWidget);
      expect(find.textContaining('nenhuma movimentação patrimonial real'), findsOneWidget);
      // O aviso REAL do app operacional nunca aparece aqui — foi
      // SUBSTITUÍDO (nunca duplicado/mostrado junto).
      expect(find.text(textoAvisoLote), findsNothing);
    },
  );

  testWidgets(
    'na prévia, DEMO-0018 aparece ANTES de DEMO-0019 em "Itens NÃO incluídos"',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const SeiLotePreviewRoot());
      await tester.pumpAndSettle();

      final botaoAbrir = find.text('Abrir documento (sempre permitido, mesmo com tentativa pendente)');
      await tester.ensureVisible(botaoAbrir);
      await tester.pumpAndSettle();
      await tester.tap(botaoAbrir);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sei-botao-concluir-todos-aptos')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('sei-concluir-lote-nao-incluidos')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sei-concluir-lote-nao-incluidos')));
      await tester.pumpAndSettle();

      // DEMO-0018 (linha 18) só é excluído na reavaliação por patrimônio
      // (origem divergente — ver `_fixturesDemo` em `sei_lote_preview_app.dart`),
      // então entrava ANEXADO ao final da lista, depois de DEMO-0019/20/21/22
      // (excluídos já na triagem preliminar) — o bug relatado. Depois da
      // ordenação por `linha`, precisa vir ANTES.
      final yDemo18 = tester.getTopLeft(find.byKey(const Key('sei-concluir-lote-nao-incluido-previa-item-18'))).dy;
      final yDemo19 = tester.getTopLeft(find.byKey(const Key('sei-concluir-lote-nao-incluido-previa-item-19'))).dy;
      expect(yDemo18, lessThan(yDemo19), reason: 'DEMO-0018 precisa aparecer antes de DEMO-0019');
    },
  );
}
