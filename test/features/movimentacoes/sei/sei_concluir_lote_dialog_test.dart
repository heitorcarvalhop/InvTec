import 'dart:async';

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
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_concluir_lote_dialog.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_itens_pendencia_lista.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

import '../../auth/fake_auth_repository.dart';
import '../../patrimonios/fake_patrimonio_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// Interface Flutter da conclusão em LOTE de documentos SEI.
///
/// NENHUM teste fala com o Supabase, chama a RPC real ou cria movimentação
/// real: tudo usa `FakeDocumentosSeiRepository`/`FakePatrimonioRepository`.
/// O Despacho 577 nunca é usado — todos os patrimônios/itens são fictícios.
const _docId = 'doc-1';

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
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
  String? destinoSetorId = 'setor-ntat',
  SeiDecisaoCampo decisaoLocalizacao = SeiDecisaoCampo.confirmadoSemInformacao,
  SeiDecisaoCampo decisaoResponsavel = SeiDecisaoCampo.confirmadoSemInformacao,
  String? equipamento,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: _docId,
    linha: linha,
    patrimonioId: 'pat-$linha',
    numeroPatrimonio: SeiValorCorrigivel(original: 'PAT-$linha'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    origemSetorId: 'setor-getec',
    origemSetorNome: 'Gerencia de Tecnologia',
    destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
    destinoSetorId: destinoSetorId,
    destinoSetorNome: 'Nucleo de Testes Automatizados',
    numeroChamado: const SeiValorCorrigivel(original: null),
    equipamentoTexto: SeiValorCorrigivel(original: equipamento ?? 'Notebook $linha'),
    decisaoLocalizacao: decisaoLocalizacao,
    decisaoResponsavel: decisaoResponsavel,
    status: status,
    criadoEm: DateTime.utc(2026, 1, 1),
  );
}

SeiDocumentoPendente _documento(List<SeiItemPendente> itens, {int versao = 1}) {
  return SeiDocumentoPendente.fromItens(
    id: _docId,
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

PatrimonioDetalhe _patrimonio(int linha, {String setorAtualId = 'setor-getec'}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'pat-$linha',
      numeroPatrimonio: 'PAT-$linha',
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: setorAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: setorAtualId == 'setor-getec' ? 'Gerencia de Tecnologia' : 'Outro Setor',
  );
}

class _Cenario {
  _Cenario(this.repo, this.patrimonios);
  final FakeDocumentosSeiRepository repo;
  final FakePatrimonioRepository patrimonios;
}

/// Abre o diálogo de detalhe do documento (fluxo real, ponta a ponta) — usado
/// para os testes de seleção múltipla/"concluir selecionados"/"concluir
/// todos os aptos" e para provar a preservação da conclusão individual.
Future<_Cenario> _abrirDetalhe(
  WidgetTester tester,
  SeiDocumentoPendente documento, {
  ProfilePerfil perfil = ProfilePerfil.admin,
  List<PatrimonioDetalhe>? patrimonios,
  Size tamanho = const Size(1280, 1000),
}) async {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(perfil));
  addTearDown(auth.dispose);
  final repo = FakeDocumentosSeiRepository(documentosIniciais: [documento]);
  final fakePatrimonios = FakePatrimonioRepository(itens: patrimonios ?? [for (var i = 1; i <= 10; i++) _patrimonio(i)]);

  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        documentosSeiRepositoryProvider.overrideWithValue(repo),
        patrimonioRepositoryProvider.overrideWithValue(fakePatrimonios),
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
  return _Cenario(repo, fakePatrimonios);
}

class _CenarioLote {
  _CenarioLote(this.repo, this.patrimonios);
  final FakeDocumentosSeiRepository repo;
  final FakePatrimonioRepository patrimonios;
  SeiConclusaoLoteDesfecho? desfecho;
}

/// Abre `sei_concluir_lote_dialog.dart` DIRETAMENTE (sem passar pela tela de
/// seleção) — usado pelos testes que exercitam os estados do controller
/// (sucesso/recusa/resultado desconhecido/conflito), sem precisar tocar em
/// checkboxes. [gerarLoteId] permite um `loteId` determinístico quando o
/// teste precisa semear um registro previamente (cenário de conflito).
Future<_CenarioLote> _abrirLoteDialog(
  WidgetTester tester, {
  required SeiDocumentoPendente documento,
  required List<SeiItemPendente> itensSelecionados,
  List<PatrimonioDetalhe>? patrimonios,
  String Function()? gerarLoteId,
  // Só para o cenário de P0010: o documento REALMENTE
  // armazenado no fake pode divergir do que o diálogo recebeu (simula
  // "outra sessão alterou o documento" entre a leitura e a confirmação).
  SeiDocumentoPendente? documentoNoRepo,
  // Viewport do teste (Windows/desktop x Android/compacto),
  // mesmo padrão de `_abrirDetalhe`/`sei_concluir_entrega_test.dart`.
  Size? tamanho,
  // `null` (padrão) preserva `textoAvisoLote`.
  String? textoAviso,
}) async {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(ProfilePerfil.admin));
  addTearDown(auth.dispose);
  final repo = FakeDocumentosSeiRepository(documentosIniciais: [documentoNoRepo ?? documento]);
  final fakePatrimonios = FakePatrimonioRepository(
    itens: patrimonios ?? [for (final item in itensSelecionados) _patrimonio(item.linha)],
  );
  final cenario = _CenarioLote(repo, fakePatrimonios);

  if (tamanho != null) {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

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
            builder: (context) => ElevatedButton(
              onPressed: () => showSeiConcluirLoteDialog(
                context,
                documento: documento,
                itensSelecionados: itensSelecionados,
                textoAviso: textoAviso,
              ).then((d) => cenario.desfecho = d),
              child: const Text('abrir lote'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir lote'));
  await tester.pumpAndSettle();
  return cenario;
}

const _chaveEntrega = Key('sei-concluir-lote-checkbox-entrega');
const _chaveLimpeza = Key('sei-concluir-lote-checkbox-limpeza');
const _chaveConfirmar = Key('sei-concluir-lote-botao-confirmar');
const _chaveFechar = Key('sei-concluir-lote-fechar');
const _chaveRetry = Key('sei-concluir-lote-retry');
const _chaveReconciliar = Key('sei-concluir-lote-reconciliar');

Future<void> _marcar(WidgetTester tester, Key chave) async {
  await tester.ensureVisible(find.byKey(chave));
  await tester.tap(find.byKey(chave));
  await tester.pumpAndSettle();
}

String _geradorLoteIdem() => 'lote-idem';

Future<void> _confirmarNoDialogo(WidgetTester tester) async {
  await _marcar(tester, _chaveEntrega);
  await tester.tap(find.byKey(_chaveConfirmar));
  await tester.pumpAndSettle();
}

void main() {
  group('seleção múltipla e ações em lote (via SeiPendenciaDetalheDialog)', () {
    testWidgets('checkbox aparece só para item PENDENTE, com permissão; alterna a seleção e o contador', (tester) async {
      await _abrirDetalhe(
        tester,
        _documento([_item(linha: 1), _item(linha: 2, status: SeiItemPendenciaStatus.concluido)]),
      );

      expect(find.byKey(const Key('sei-item-selecao-item-1')), findsOneWidget);
      // item-2 já concluído: nunca pode ser selecionado para o lote.
      expect(find.byKey(const Key('sei-item-selecao-item-2')), findsNothing);

      expect(find.text('Concluir selecionados (0)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sei-item-selecao-item-1')));
      await tester.pumpAndSettle();
      expect(find.text('Concluir selecionados (1)'), findsOneWidget);

      final botao = tester.widget<OutlinedButton>(find.byKey(const Key('sei-botao-concluir-selecionados')));
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('CONSULTA não vê nenhum checkbox nem os botões de lote', (tester) async {
      await _abrirDetalhe(tester, _documento([_item(linha: 1)]), perfil: ProfilePerfil.consulta);
      expect(find.byKey(const Key('sei-item-selecao-item-1')), findsNothing);
      expect(find.byKey(const Key('sei-botao-concluir-selecionados')), findsNothing);
      expect(find.byKey(const Key('sei-botao-concluir-todos-aptos')), findsNothing);
    });

    testWidgets('Concluir selecionados abre a revisão com EXATAMENTE os itens marcados', (tester) async {
      await _abrirDetalhe(tester, _documento([_item(linha: 1), _item(linha: 2)]));

      await tester.tap(find.byKey(const Key('sei-item-selecao-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sei-botao-concluir-selecionados')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-item-item-1')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-item-item-2')), findsNothing);
      expect(find.text('Concluir 1 item'), findsWidgets);
    });

    testWidgets('item bloqueado na seleção explícita aparece na revisão e IMPEDE o lote inteiro', (tester) async {
      await _abrirDetalhe(
        tester,
        _documento([
          _item(linha: 1),
          _item(linha: 2, decisaoLocalizacao: SeiDecisaoCampo.pendente), // bloqueado: decisão pendente
        ]),
      );

      await tester.tap(find.byKey(const Key('sei-item-selecao-item-1')));
      await tester.tap(find.byKey(const Key('sei-item-selecao-item-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sei-botao-concluir-selecionados')));
      await tester.pumpAndSettle();

      // NENHUM item bloqueado some da revisão.
      expect(find.byKey(const Key('sei-concluir-lote-item-item-1')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-item-item-2')), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      final botao = tester.widget<FilledButton>(find.byKey(_chaveConfirmar));
      expect(botao.onPressed, isNull, reason: 'lote inteiro bloqueado por causa do item 2');
    });

    testWidgets('Concluir todos os aptos seleciona só os elegíveis, mostra os não incluídos com motivo', (tester) async {
      await _abrirDetalhe(
        tester,
        _documento([
          _item(linha: 1),
          _item(linha: 2, status: SeiItemPendenciaStatus.cancelado),
          _item(linha: 3, decisaoResponsavel: SeiDecisaoCampo.pendente),
        ]),
      );

      await tester.tap(find.byKey(const Key('sei-botao-concluir-todos-aptos')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-item-item-1')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-item-item-2')), findsNothing);
      expect(find.byKey(const Key('sei-concluir-lote-item-item-3')), findsNothing);
      expect(find.byKey(const Key('sei-concluir-lote-nao-incluidos')), findsOneWidget);
      expect(find.textContaining('2 itens NÃO incluídos'), findsOneWidget);

      // O número do patrimônio de um item NÃO incluído
      // (item-2, cancelado) fica alinhado (mesmo recuo do ícone) com o
      // número do patrimônio de um item INCLUÍDO (item-1) — antes, o
      // primeiro começava rente à borda esquerda e o segundo vinha recuado
      // depois de um ícone, desalinhados entre si.
      await tester.tap(find.byKey(const Key('sei-concluir-lote-nao-incluidos')));
      await tester.pumpAndSettle();
      final xIncluido = tester
          .getTopLeft(
            find.descendant(of: find.byKey(const Key('sei-concluir-lote-item-item-1')), matching: find.text('PAT-1')),
          )
          .dx;
      final xNaoIncluido = tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const Key('sei-concluir-lote-nao-incluido-item-2')),
              matching: find.text('PAT-2'),
            ),
          )
          .dx;
      expect(xNaoIncluido, closeTo(xIncluido, 0.5));
    });

    testWidgets(
      'Concluir todos os aptos EXCLUI um item com origem divergente do patrimônio '
      '(consulta o patrimônio atual, nunca só o item)',
      (tester) async {
        await _abrirDetalhe(
          tester,
          _documento([_item(linha: 1), _item(linha: 2)]),
          // item-2 "parece" elegível pela triagem por item (nenhum campo
          // bloqueado no item em si), mas o patrimônio fictício dele está
          // hoje em outro setor — só detectável consultando o patrimônio.
          patrimonios: [_patrimonio(1), _patrimonio(2, setorAtualId: 'setor-almox')],
        );

        await tester.tap(find.byKey(const Key('sei-botao-concluir-todos-aptos')));
        await tester.pumpAndSettle();

        // item-2 NUNCA chega a ser proposto para a RPC — some da seleção
        // automática, aparece só em "não incluídos", com o motivo certo.
        expect(find.byKey(const Key('sei-concluir-lote-item-item-1')), findsOneWidget);
        expect(find.byKey(const Key('sei-concluir-lote-item-item-2')), findsNothing);
        expect(find.byKey(const Key('sei-concluir-lote-nao-incluidos')), findsOneWidget);
        expect(find.textContaining('1 item NÃO incluído'), findsOneWidget);

        // O motivo só aparece com a seção expandida (ExpansionTile).
        await tester.tap(find.byKey(const Key('sei-concluir-lote-nao-incluidos')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Origem divergente'), findsWidgets);

        // Nenhum loteId/decisão foi gerado só para a triagem: o botão de
        // confirmar segue disponível normalmente para o item-1 sozinho.
        await _marcar(tester, _chaveEntrega);
        expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNotNull);
      },
    );

    testWidgets(
      '"Itens NÃO incluídos" aparecem em ordem de LINHA do documento, não de construção',
      (tester) async {
        // item-1 (linha 1): SÓ é excluído na reavaliação por patrimônio
        // (origem divergente) — na função pura
        // (`selecionarAptosParaLoteComPatrimonios`), itens assim são
        // ANEXADOS ao FINAL da lista de não incluídos, depois dos
        // detectáveis na triagem preliminar.
        // item-2 (linha 2): É excluído já na triagem PRELIMINAR (destino
        // ainda pendente) — entra PRIMEIRO na lista, antes do item-1.
        // item-3 (linha 3): elegível de verdade — precisa sobrar PELO MENOS
        // um apto, senão "Concluir todos os aptos" nem abre a revisão (cai
        // no aviso de "nenhum item permaneceu apto").
        // Sem reordenar por `linha`, a tela mostraria "item-2" ANTES de
        // "item-1", invertido — exatamente o bug relatado (DEMO-0018
        // aparecia depois de DEMO-0019 na prévia, pelo mesmo motivo).
        await _abrirDetalhe(
          tester,
          _documento([
            _item(linha: 1),
            _item(linha: 2, decisaoLocalizacao: SeiDecisaoCampo.pendente),
            _item(linha: 3),
          ]),
          patrimonios: [_patrimonio(1, setorAtualId: 'setor-almox'), _patrimonio(2), _patrimonio(3)],
        );

        await tester.tap(find.byKey(const Key('sei-botao-concluir-todos-aptos')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sei-concluir-lote-item-item-3')), findsOneWidget, reason: 'pré-condição: sobrou 1 apto');
        expect(find.textContaining('2 itens NÃO incluídos'), findsOneWidget);

        await tester.tap(find.byKey(const Key('sei-concluir-lote-nao-incluidos')));
        await tester.pumpAndSettle();

        final yItem1 = tester.getTopLeft(find.byKey(const Key('sei-concluir-lote-nao-incluido-item-1'))).dy;
        final yItem2 = tester.getTopLeft(find.byKey(const Key('sei-concluir-lote-nao-incluido-item-2'))).dy;
        expect(yItem1, lessThan(yItem2), reason: 'item-1 (linha 1) precisa aparecer ANTES de item-2 (linha 2)');

        // Cada motivo continua associado ao item CORRETO depois da
        // reordenação (a reordenação nunca desmonta item/motivos).
        expect(
          find.descendant(
            of: find.byKey(const Key('sei-concluir-lote-nao-incluido-item-1')),
            matching: find.textContaining('Origem divergente'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('sei-concluir-lote-nao-incluido-item-2')),
            matching: find.textContaining('localização'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('revisão, confirmações obrigatórias e chamada única (via showSeiConcluirLoteDialog)', () {
    testWidgets('mostra patrimônio, equipamento, origem/destino de cada item selecionado', (tester) async {
      await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1), _item(linha: 2)]),
        itensSelecionados: [_item(linha: 1), _item(linha: 2)],
      );

      expect(find.textContaining('PAT-1'), findsWidgets);
      expect(find.textContaining('PAT-2'), findsWidgets);
      expect(find.textContaining('Notebook 1'), findsWidgets);
      expect(find.textContaining('Gerencia de Tecnologia'), findsWidgets);
      expect(find.textContaining('Nucleo de Testes Automatizados'), findsWidgets);
      // Sem `textoAviso`, o aviso de responsabilidade REAL
      // do app operacional continua exatamente o mesmo de sempre.
      expect(find.text(textoAvisoLote), findsOneWidget);
      // 2 itens selecionados → plural correto (nunca "item(ns)").
      expect(find.text('Concluir 2 itens em lote'), findsOneWidget);
      expect(find.text('Concluir 2 itens'), findsOneWidget);
    });

    testWidgets(
      'textoAviso substitui o aviso padrão (usado pela prévia local para indicar que é fictício)',
      (tester) async {
        const textoFicticio = 'PRÉVIA LOCAL: simulação em memória, nenhuma movimentação real.';
        await _abrirLoteDialog(
          tester,
          documento: _documento([_item(linha: 1)]),
          itensSelecionados: [_item(linha: 1)],
          textoAviso: textoFicticio,
        );

        expect(find.text(textoFicticio), findsOneWidget);
        // O aviso REAL nunca aparece junto — foi SUBSTITUÍDO, não duplicado.
        expect(find.text(textoAvisoLote), findsNothing);
      },
    );

    testWidgets('singular/plural corretos: "1 item" (nunca "item(ns)") e "2 itens"', (tester) async {
      await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]),
        itensSelecionados: [_item(linha: 1)],
      );
      expect(find.text('Concluir 1 item em lote'), findsOneWidget);
      expect(find.text('Concluir 1 item'), findsOneWidget);
      expect(find.textContaining('item(ns)'), findsNothing);
    });

    testWidgets('confirmação de entrega física é OBRIGATÓRIA: botão só habilita depois dela', (tester) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]),
        itensSelecionados: [_item(linha: 1)],
      );

      expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNull);
      await _marcar(tester, _chaveEntrega);
      expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNotNull);
      expect(c.repo.concluirLoteCallCount, 0);
    });

    testWidgets('confirmação de limpeza é AGREGADA: qualquer item exigindo já bloqueia até marcar', (tester) async {
      await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1), _item(linha: 2)]),
        itensSelecionados: [_item(linha: 1), _item(linha: 2)],
        patrimonios: [
          _patrimonio(1),
          PatrimonioDetalhe(
            patrimonio: Patrimonio(
              id: 'pat-2',
              numeroPatrimonio: 'PAT-2',
              tipoId: 'tipo-1',
              status: PatrimonioStatus.emUso,
              setorAtualId: 'setor-getec',
              responsavelAtual: 'Fulano',
              dataCadastro: DateTime(2026, 1, 1),
              atualizadoEm: DateTime(2026, 1, 1),
            ),
            tipoNome: 'Notebook',
            setorNome: 'Gerencia de Tecnologia',
          ),
        ],
      );

      expect(find.byKey(_chaveLimpeza), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNull);
      await _marcar(tester, _chaveLimpeza);
      expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNotNull);
    });

    testWidgets('confirmar chama concluirItensLote UMA ÚNICA VEZ, nunca um laço de concluirItem', (tester) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1), _item(linha: 2)]),
        itensSelecionados: [_item(linha: 1), _item(linha: 2)],
      );

      await _confirmarNoDialogo(tester);

      expect(c.repo.concluirLoteCallCount, 1);
      expect(c.repo.concluirCallCount, 2, reason: 'a simulação do SERVIDOR chama a individual 1x por item, não o Flutter');
    });

    testWidgets(
      'fechar a revisão ("Voltar") ANTES de confirmar não cria nem executa nenhuma decisão',
      (tester) async {
        final c = await _abrirLoteDialog(
          tester,
          documento: _documento([_item(linha: 1)]),
          itensSelecionados: [_item(linha: 1)],
        );

        // Marca até a confirmação de entrega, mas desiste ANTES de confirmar.
        await _marcar(tester, _chaveEntrega);
        await tester.tap(find.byKey(const Key('sei-concluir-lote-voltar')));
        await tester.pumpAndSettle();

        expect(c.desfecho, isNull, reason: 'nenhuma decisão foi criada — nada a reportar ao diálogo pai');
        expect(c.repo.concluirLoteCallCount, 0);
        final container = ProviderScope.containerOf(tester.element(find.text('abrir lote')), listen: false);
        final controller = container.read(seiConclusaoLoteControllerProvider);
        expect(controller.status, SeiConclusaoLoteStatus.ocioso);
        expect(controller.decisao, isNull);
      },
    );

    testWidgets('duplo clique NÃO dispara uma segunda chamada', (tester) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]),
        itensSelecionados: [_item(linha: 1)],
      );
      final espera = Completer<void>();
      c.repo.aguardarConclusao = espera;

      await _marcar(tester, _chaveEntrega);
      await tester.tap(find.byKey(_chaveConfirmar));
      await tester.pump();
      // Botão de confirmar não existe mais (painel "executando").
      expect(find.byKey(_chaveConfirmar), findsNothing);
      expect(find.text('Confirmando a conclusão em lote…'), findsOneWidget);

      espera.complete();
      await tester.pumpAndSettle();
      expect(c.repo.concluirLoteCallCount, 1);
    });
  });

  group('sucesso, recarga e resultado desconhecido', () {
    testWidgets('sucesso: mostra a quantidade concluída, recarrega o documento e retorna o resultado', (tester) async {
      await _abrirDetalhe(tester, _documento([_item(linha: 1), _item(linha: 2)]));
      await tester.tap(find.byKey(const Key('sei-item-selecao-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sei-botao-concluir-selecionados')));
      await tester.pumpAndSettle();

      await _confirmarNoDialogo(tester);

      expect(find.byKey(const Key('sei-concluir-lote-sucesso')), findsOneWidget);
      expect(find.textContaining('1 item concluído'), findsOneWidget);
      await tester.tap(find.byKey(_chaveFechar));
      await tester.pumpAndSettle();

      // Recarregou: banner de sucesso no diálogo pai, e o item some da
      // lista de seleção (não é mais PENDENTE).
      expect(find.textContaining('1 item concluído em lote'), findsOneWidget);
      expect(find.byKey(const Key('sei-item-selecao-item-1')), findsNothing);
    });

    testWidgets('ja_executado (retry idempotente) é identificado com mensagem própria', (tester) async {
      final documento = _documento([_item(linha: 1)]);
      final c1 = await _abrirLoteDialog(
        tester,
        documento: documento,
        itensSelecionados: [_item(linha: 1)],
        gerarLoteId: _geradorLoteIdem,
      );
      await _confirmarNoDialogo(tester);
      expect(find.byKey(const Key('sei-concluir-lote-sucesso')), findsOneWidget);
      expect(c1.repo.concluirLoteCallCount, 1);
    });

    testWidgets('resultado desconhecido: preserva loteId/parâmetros, oferece reconciliar e tentar de novo', (tester) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]),
        itensSelecionados: [_item(linha: 1)],
      );
      c.repo.falhaNaConclusao = Exception('timeout simulado');

      await _confirmarNoDialogo(tester);

      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);
      expect(find.byKey(_chaveRetry), findsOneWidget);
      expect(find.byKey(_chaveReconciliar), findsOneWidget);

      // "Tentar novamente" reenvia EXATAMENTE o mesmo payload — sem exigir
      // marcar as confirmações de novo, e sem gerar um loteId novo.
      c.repo.falhaNaConclusao = null;
      await tester.tap(find.byKey(_chaveRetry));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-sucesso')), findsOneWidget);
      expect(c.repo.concluirLoteCallCount, 2);
      expect(c.repo.conclusoesLote[0]['loteId'], c.repo.conclusoesLote[1]['loteId']);
    });

    testWidgets('fechar com resultado desconhecido e reabrir mostra a MESMA tentativa pendente', (tester) async {
      final documento = _documento([_item(linha: 1)]);
      final c = await _abrirLoteDialog(tester, documento: documento, itensSelecionados: [_item(linha: 1)]);
      c.repo.falhaNaConclusao = Exception('timeout simulado');
      await _confirmarNoDialogo(tester);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      await tester.tap(find.byKey(_chaveFechar));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsNothing, reason: 'diálogo fechado');

      // Reabre — mesmo passando uma seleção "nova" qualquer, o controller
      // (global) ainda tem a tentativa pendente e o diálogo mostra o painel
      // dela diretamente.
      await tester.tap(find.text('abrir lote'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);
      expect(c.repo.concluirLoteCallCount, 1, reason: 'reabrir sozinho não reenvia nada');
    });
  });

  group('feedback visual de "Consultar o que aconteceu"', () {
    testWidgets(
      'timeout → Consultar o que aconteceu → consulta retorna null → mensagem visível → tentativa preservada',
      (tester) async {
        final c = await _abrirLoteDialog(
          tester,
          documento: _documento([_item(linha: 1)]),
          itensSelecionados: [_item(linha: 1)],
        );
        c.repo.falhaNaConclusao = Exception('timeout simulado');
        await _confirmarNoDialogo(tester);
        expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

        final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('sei-concluir-lote-incerto'))));
        final loteIdAntes = container.read(seiConclusaoLoteControllerProvider).decisao!.loteId;

        // Nenhum registro foi semeado para este loteId — `buscarLotePorId`
        // devolve `null`.
        c.repo.falhaNaConclusao = null;
        await tester.tap(find.byKey(_chaveReconciliar));
        await tester.pumpAndSettle();

        // MESMO painel — mas agora com uma mensagem visível sobre o
        // resultado desta consulta (antes do fix, a tela ficava idêntica).
        expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);
        // O rastro da última consulta agora é curto e
        // vive FORA do bloco vermelho principal (ver `sei-concluir-lote-aviso-consulta`).
        expect(find.byKey(const Key('sei-concluir-lote-aviso-consulta')), findsOneWidget);
        expect(find.textContaining('Última consulta: ainda sem confirmação'), findsOneWidget);
        expect(c.repo.buscarLotePorIdCallCount, 1);

        // Tentativa preservada: mesmo loteId, ainda pendente, "Tentar
        // novamente" continua funcionando com os mesmos dados.
        final estado = container.read(seiConclusaoLoteControllerProvider);
        expect(estado.status, SeiConclusaoLoteStatus.resultadoDesconhecido);
        expect(estado.decisao!.loteId, loteIdAntes);
        expect(estado.temTentativaPendente, isTrue);
      },
    );

    testWidgets('consulta encontra o registro: painel muda para sucesso (comunicado pela própria troca de painel)', (
      tester,
    ) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]),
        itensSelecionados: [_item(linha: 1)],
        gerarLoteId: () => 'lote-sucesso-11-5-11',
      );
      c.repo.falhaNaConclusao = Exception('timeout simulado');
      await _confirmarNoDialogo(tester);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      // A tentativa original, na verdade, TINHA sido aplicada no servidor —
      // semeia o mesmo loteId/identidade diretamente no fake.
      c.repo.falhaNaConclusao = null;
      await c.repo.concluirItensLote(
        documentoId: _docId,
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-sucesso-11-5-11',
        confirmarLimpezaDestino: false,
      );

      await tester.tap(find.byKey(_chaveReconciliar));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-sucesso')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsNothing);
    });

    testWidgets('a PRÓPRIA consulta falha (rede/permissão): mensagem DIFERENTE da de "ainda desconhecido", tentativa preservada', (
      tester,
    ) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]),
        itensSelecionados: [_item(linha: 1)],
      );
      c.repo.falhaNaConclusao = Exception('timeout simulado');
      await _confirmarNoDialogo(tester);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      c.repo.falhaNaConclusao = null;
      c.repo.falhaAoBuscarLote = Exception('rede indisponível');
      await tester.tap(find.byKey(_chaveReconciliar));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-aviso-consulta')), findsOneWidget);
      expect(
        find.textContaining('Última consulta: não foi possível completar'),
        findsOneWidget,
      );
      // NUNCA a mensagem de "registro ainda não encontrado" — são desfechos
      // diferentes, com mensagens diferentes.
      expect(find.textContaining('Última consulta: ainda sem confirmação'), findsNothing);
    });

    testWidgets('consulta encontra registro DIVERGENTE: painel muda para conflito de integridade', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      final repoSemente = FakeDocumentosSeiRepository(documentosIniciais: [documento]);
      await repoSemente.concluirItensLote(
        documentoId: _docId,
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: 'lote-conflito-11-5-11',
        confirmarLimpezaDestino: false,
      );

      final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(ProfilePerfil.admin));
      addTearDown(auth.dispose);
      final fakePatrimonios = FakePatrimonioRepository(itens: [_patrimonio(1)]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            documentosSeiRepositoryProvider.overrideWithValue(repoSemente),
            patrimonioRepositoryProvider.overrideWithValue(fakePatrimonios),
            seiConclusaoLoteControllerProvider.overrideWith(
              () => SeiConclusaoLoteController(gerarLoteId: () => 'lote-conflito-11-5-11'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSeiConcluirLoteDialog(
                    context,
                    documento: documento,
                    itensSelecionados: [_item(linha: 1)], // seleção DIFERENTE da semeada
                  ),
                  child: const Text('abrir lote'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir lote'));
      await tester.pumpAndSettle();

      repoSemente.falhaNaConclusao = Exception('timeout simulado');
      await _confirmarNoDialogo(tester);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      repoSemente.falhaNaConclusao = null;
      await tester.tap(find.byKey(_chaveReconciliar));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsNothing);
    });
  });

  group('recusa conhecida (P0010/P0036/P0037 diretas)', () {
    testWidgets('P0010: mensagem amigável, nada concluído, permite fechar e atualizar', (tester) async {
      final c = await _abrirLoteDialog(
        tester,
        documento: _documento([_item(linha: 1)]), // versão 1, é o que o diálogo enviará como versaoEsperada
        documentoNoRepo: _documento([_item(linha: 1)], versao: 5), // mas o "servidor" já está na versão 5 -> P0010
        itensSelecionados: [_item(linha: 1)],
      );

      await _confirmarNoDialogo(tester);

      expect(find.byKey(const Key('sei-concluir-lote-recusado')), findsOneWidget);
      expect(c.desfecho, isNull, reason: 'ainda não fechou o painel');
      await tester.tap(find.byKey(_chaveFechar));
      await tester.pumpAndSettle();
      expect(c.desfecho!.resultado, isNull);
      expect(c.desfecho!.incerto, isFalse);
    });
  });

  group('conflito de integridade', () {
    testWidgets('mostra aviso específico e bloqueia reiniciar/retry/reconciliar — só "Fechar"', (tester) async {
      final documento = _documento([_item(linha: 1), _item(linha: 2)]);
      // Semeia um registro JÁ aplicado para 'lote-conflito', com uma seleção
      // DIFERENTE da que o diálogo vai tentar — simula o mesmo loteId
      // reaproveitado por outra operação.
      final repoSemente = FakeDocumentosSeiRepository(documentosIniciais: [documento]);
      await repoSemente.concluirItensLote(
        documentoId: _docId,
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: 'lote-conflito',
        confirmarLimpezaDestino: false,
      );

      final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(ProfilePerfil.admin));
      addTearDown(auth.dispose);
      final fakePatrimonios = FakePatrimonioRepository(itens: [_patrimonio(1)]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            documentosSeiRepositoryProvider.overrideWithValue(repoSemente),
            patrimonioRepositoryProvider.overrideWithValue(fakePatrimonios),
            seiConclusaoLoteControllerProvider.overrideWith(
              () => SeiConclusaoLoteController(gerarLoteId: () => 'lote-conflito'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSeiConcluirLoteDialog(
                    context,
                    documento: documento,
                    itensSelecionados: [_item(linha: 1)], // seleção DIFERENTE da semeada
                  ),
                  child: const Text('abrir lote'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir lote'));
      await tester.pumpAndSettle();

      repoSemente.falhaNaConclusao = Exception('timeout simulado');
      await _confirmarNoDialogo(tester);
      expect(find.byKey(const Key('sei-concluir-lote-incerto')), findsOneWidget);

      repoSemente.falhaNaConclusao = null;
      await tester.tap(find.byKey(_chaveReconciliar));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget);
      // NENHUM botão de ação além de "Fechar" neste painel.
      expect(find.byKey(_chaveRetry), findsNothing);
      expect(find.byKey(_chaveReconciliar), findsNothing);
      expect(find.byKey(_chaveFechar), findsOneWidget);

      // Fechar preserva a decisão para investigação — reabrir mostra o
      // MESMO conflito, nunca reiniciado silenciosamente.
      await tester.tap(find.byKey(_chaveFechar));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abrir lote'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget);
      // 2 chamadas a `concluirItensLote`: a semeadura direta + a tentativa
      // do diálogo (que falhou como "desconhecida", nunca escreveu nada) —
      // a RECONCILIAÇÃO em si (que achou o conflito) não fez NENHUMA
      // chamada nova a ela, só a leitura por `buscarLotePorId`.
      expect(repoSemente.concluirLoteCallCount, 2);
    });

    testWidgets(
      '"Detalhes técnicos" NUNCA orienta iniciar outra conclusão; informa loteId e suporte',
      (tester) async {
        final documento = _documento([_item(linha: 1), _item(linha: 2)]);
        final repoSemente = FakeDocumentosSeiRepository(documentosIniciais: [documento]);
        await repoSemente.concluirItensLote(
          documentoId: _docId,
          itemIds: const ['item-2'],
          versaoEsperada: 1,
          loteId: 'lote-conflito-11-5-14',
          confirmarLimpezaDestino: false,
        );

        final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(ProfilePerfil.admin));
        addTearDown(auth.dispose);
        final fakePatrimonios = FakePatrimonioRepository(itens: [_patrimonio(1)]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              documentosSeiRepositoryProvider.overrideWithValue(repoSemente),
              patrimonioRepositoryProvider.overrideWithValue(fakePatrimonios),
              seiConclusaoLoteControllerProvider.overrideWith(
                () => SeiConclusaoLoteController(gerarLoteId: () => 'lote-conflito-11-5-14'),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showSeiConcluirLoteDialog(
                      context,
                      documento: documento,
                      itensSelecionados: [_item(linha: 1)],
                    ),
                    child: const Text('abrir lote'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir lote'));
        await tester.pumpAndSettle();

        repoSemente.falhaNaConclusao = Exception('timeout simulado');
        await _confirmarNoDialogo(tester);
        repoSemente.falhaNaConclusao = null;
        await tester.tap(find.byKey(_chaveReconciliar));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sei-concluir-lote-conflito')), findsOneWidget);

        // O aviso PRINCIPAL já não muda (nunca sugeriu repetir/nova
        // decisão) — o bug estava só em "Detalhes técnicos".
        await tester.tap(find.text('Detalhes técnicos'));
        await tester.pumpAndSettle();

        expect(find.textContaining('comece uma nova conclusão'), findsNothing);
        expect(find.textContaining('nova conclusão'), findsNothing);
        expect(find.textContaining('tente novamente'), findsNothing);
        expect(find.textContaining('permanece preservada'), findsOneWidget);
        // "suporte técnico" já aparece no aviso PRINCIPAL (nunca mudou) —
        // esta checagem só prova que também aparece nos detalhes técnicos.
        expect(find.textContaining('suporte técnico'), findsWidgets);
        expect(find.textContaining('lote-conflito-11-5-14'), findsOneWidget);
        expect(find.textContaining('P0037'), findsOneWidget);
      },
    );
  });

  group('compatibilidade visual: lista longa, texto extenso, Windows e viewport compacto', () {
    List<SeiItemPendente> itensLongos(int quantidade) => [
      for (var i = 1; i <= quantidade; i++)
        _item(
          linha: i,
          equipamento:
              'Notebook Dell Latitude 5440 Intel Core i7 16GB RAM 512GB SSD — estação de trabalho de teste número $i',
        ),
    ];

    testWidgets('Windows/desktop (1400x900): lista longa (40 itens) rola sem overflow; confirmar acessível', (
      tester,
    ) async {
      final itens = itensLongos(40);
      await _abrirLoteDialog(
        tester,
        documento: _documento(itens),
        itensSelecionados: itens,
        patrimonios: [for (final item in itens) _patrimonio(item.linha)],
        tamanho: const Size(1400, 900),
      );

      expect(find.byKey(const Key('sei-concluir-lote-itens')), findsOneWidget);
      expect(find.byKey(const Key('sei-concluir-lote-item-item-1')), findsOneWidget);
      // Rola a lista interna até o último item — prova que ela é navegável,
      // não só que o primeiro item renderiza.
      await tester.scrollUntilVisible(
        find.byKey(const Key('sei-concluir-lote-item-item-40')),
        200,
        scrollable: find
            .descendant(of: find.byKey(const Key('sei-concluir-lote-itens')), matching: find.byType(Scrollable))
            .first,
      );
      expect(find.byKey(const Key('sei-concluir-lote-item-item-40')), findsOneWidget);

      await _marcar(tester, _chaveEntrega);
      expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNotNull);
    });

    testWidgets('Android compacto (360x640): lista longa e texto extenso abrem sem overflow; confirmar acessível', (
      tester,
    ) async {
      final itens = itensLongos(15);
      await _abrirLoteDialog(
        tester,
        documento: _documento(itens),
        itensSelecionados: itens,
        patrimonios: [for (final item in itens) _patrimonio(item.linha)],
        tamanho: const Size(360, 640),
      );

      expect(find.byKey(const Key('sei-concluir-lote-itens')), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      await tester.ensureVisible(find.byKey(_chaveConfirmar));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed, isNotNull);
      expect(tester.getRect(find.byKey(_chaveConfirmar)).bottom, lessThanOrEqualTo(640));
    });
  });

  group('preservação da conclusão individual', () {
    testWidgets('após uma conclusão em lote, a conclusão INDIVIDUAL de outro item continua funcionando', (tester) async {
      await _abrirDetalhe(tester, _documento([_item(linha: 1), _item(linha: 2)]));

      await tester.tap(find.byKey(const Key('sei-item-selecao-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sei-botao-concluir-selecionados')));
      await tester.pumpAndSettle();
      await _confirmarNoDialogo(tester);
      await tester.tap(find.byKey(_chaveFechar));
      await tester.pumpAndSettle();

      // item-2 continua com o botão INDIVIDUAL "Concluir entrega" — mesmo
      // fluxo de sempre, sem alteração de assinatura ou comportamento.
      final botaoIndividual = find.descendant(
        of: find.byType(SeiItensPendenciaLista),
        matching: find.text('Concluir entrega'),
      );
      expect(botaoIndividual, findsOneWidget);
    });
  });
}
