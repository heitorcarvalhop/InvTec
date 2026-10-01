import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_erros.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_plano.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_pendencia_regras.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_item_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_evento_documento.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_concluir_entrega_dialog.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_historico_alteracoes.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_itens_pendencia_lista.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../patrimonios/fake_patrimonio_repository.dart';
import '../../setores/fake_setor_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// PROMPT 11.4.3 — "Concluir entrega" de um item SEI.
///
/// NENHUM teste fala com o Supabase, chama a RPC real ou cria movimentação
/// real: tudo usa `FakeDocumentosSeiRepository.concluirItem` (que apenas
/// simula, em memória, as regras de `concluir_item_documento_sei`) e o
/// `FakePatrimonioRepository`. O Despacho 577 nunca é usado.
const _docId = 'doc-1';

final _setores = [
  Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(
    id: 'setor-ntat',
    nome: 'Nucleo de Testes Automatizados',
    sigla: 'NTAT',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
];

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
  int linha = 1,
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
  String? patrimonioId = 'pat-1',
  String? origemSetorId = 'setor-getec',
  String? destinoSetorId = 'setor-ntat',
  SeiDecisaoCampo decisaoLocalizacao = SeiDecisaoCampo.confirmadoSemInformacao,
  String? localizacaoId,
  String? localizacaoNome,
  SeiDecisaoCampo decisaoResponsavel = SeiDecisaoCampo.confirmadoSemInformacao,
  String? responsavel,
  String? movimentacaoId,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: _docId,
    linha: linha,
    patrimonioId: patrimonioId == null ? null : (linha == 1 ? patrimonioId : 'pat-$linha'),
    numeroPatrimonio: SeiValorCorrigivel(original: '90000000$linha'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    origemSetorId: origemSetorId,
    origemSetorNome: 'Gerencia de Tecnologia',
    origemSetorSigla: 'GETEC',
    destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
    destinoSetorId: destinoSetorId,
    destinoSetorNome: 'Nucleo de Testes Automatizados',
    destinoSetorSigla: 'NTAT',
    numeroChamado: const SeiValorCorrigivel(original: '4556'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Monitor Teste'),
    localizacaoDestinoId: localizacaoId,
    localizacaoDestinoNome: localizacaoNome,
    decisaoLocalizacao: decisaoLocalizacao,
    responsavelDestino: responsavel,
    decisaoResponsavel: decisaoResponsavel,
    status: status,
    motivoCancelamento: status == SeiItemPendenciaStatus.cancelado ? 'motivo' : null,
    movimentacaoId: movimentacaoId,
    criadoEm: DateTime(2026, 1, 1),
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
    criadoEm: DateTime(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Fulano',
    itens: itens,
  );
}

PatrimonioDetalhe _patrimonio({
  String id = 'pat-1',
  String setorId = 'setor-getec',
  String setorNome = 'Gerencia de Tecnologia',
  String? responsavel,
  String? localizacaoId,
  String? localizacaoNome,
  PatrimonioStatus status = PatrimonioStatus.disponivel,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: '900000001',
      tipoId: 'tipo-1',
      status: responsavel != null && status == PatrimonioStatus.disponivel ? PatrimonioStatus.emUso : status,
      setorAtualId: setorId,
      localizacaoAtualId: localizacaoId,
      responsavelAtual: responsavel,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: setorNome,
    setorSigla: 'GETEC',
    localizacaoNome: localizacaoNome,
  );
}

class _Cenario {
  _Cenario(this.repo, this.patrimonios);

  final FakeDocumentosSeiRepository repo;
  final FakePatrimonioRepository patrimonios;
}

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
  final fakePatrimonios = FakePatrimonioRepository(itens: patrimonios ?? [_patrimonio()]);

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
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
        localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
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

Finder get _botoesConcluirNaLista =>
    find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Concluir entrega'));
Finder get _botoesCancelarNaLista =>
    find.descendant(of: find.byType(SeiItensPendenciaLista), matching: find.text('Cancelar'));

const _chaveConfirmar = Key('sei-concluir-botao-confirmar');
const _chaveEntrega = Key('sei-concluir-checkbox-entrega');
const _chaveLimpeza = Key('sei-concluir-checkbox-limpeza');

Future<void> _abrirConfirmacao(WidgetTester tester, {int indice = 0}) async {
  await tester.tap(_botoesConcluirNaLista.at(indice));
  await tester.pumpAndSettle();
}

bool _confirmarHabilitado(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_chaveConfirmar)).onPressed != null;

Future<void> _marcar(WidgetTester tester, Key chave) async {
  await tester.ensureVisible(find.byKey(chave));
  await tester.tap(find.byKey(chave));
  await tester.pumpAndSettle();
}

Future<void> _clicarConfirmar(WidgetTester tester) async {
  await tester.tap(find.byKey(_chaveConfirmar));
  await tester.pumpAndSettle();
}

void main() {
  group('4. botão "Concluir entrega" na lista de itens', () {
    testWidgets('1. item PENDENTE mostra "Concluir entrega" (ADMIN, GESTOR e OPERADOR), ao lado de "Cancelar"', (
      tester,
    ) async {
      for (final perfil in [ProfilePerfil.admin, ProfilePerfil.gestor, ProfilePerfil.operador]) {
        await _abrirDetalhe(tester, _documento([_item()]), perfil: perfil);
        expect(_botoesConcluirNaLista, findsOneWidget, reason: perfil.name);
        // as duas ações continuam SEPARADAS: Cancelar não foi substituído
        expect(_botoesCancelarNaLista, findsOneWidget, reason: perfil.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('2. CONSULTA não vê "Concluir entrega" (nem "Cancelar")', (tester) async {
      await _abrirDetalhe(tester, _documento([_item()]), perfil: ProfilePerfil.consulta);
      expect(_botoesConcluirNaLista, findsNothing);
      expect(_botoesCancelarNaLista, findsNothing);
    });

    testWidgets('3. item CANCELADO não mostra "Concluir entrega"', (tester) async {
      await _abrirDetalhe(tester, _documento([_item(status: SeiItemPendenciaStatus.cancelado), _item(linha: 2)]));
      expect(_botoesConcluirNaLista, findsOneWidget, reason: 'só o item 2 (pendente)');
      expect(itemPodeSerConcluido(_item(status: SeiItemPendenciaStatus.cancelado)), isFalse);
    });

    testWidgets('4. item CONCLUIDO não mostra "Concluir entrega"', (tester) async {
      await _abrirDetalhe(
        tester,
        _documento([_item(status: SeiItemPendenciaStatus.concluido, movimentacaoId: 'mov-9'), _item(linha: 2)]),
      );
      expect(_botoesConcluirNaLista, findsOneWidget, reason: 'só o item 2 (pendente)');
      expect(itemPodeSerConcluido(_item(status: SeiItemPendenciaStatus.concluido)), isFalse);
    });
  });

  group('5/6/7/8. diálogo de confirmação', () {
    testWidgets('abrir NÃO executa nada e mostra o resumo: patrimônio, origem, destino, documento e o aviso', (
      tester,
    ) async {
      final c = await _abrirDetalhe(
        tester,
        _documento([
          _item(
            decisaoLocalizacao: SeiDecisaoCampo.definido,
            localizacaoId: 'loc-1',
            localizacaoNome: 'Sala 10',
            decisaoResponsavel: SeiDecisaoCampo.definido,
            responsavel: 'Maria',
          ),
        ]),
      );
      await _abrirConfirmacao(tester);

      expect(c.repo.concluirCallCount, 0);
      expect(find.text(textoAvisoMovimentacaoReal), findsOneWidget);
      // Patrimônio
      expect(find.text('900000001'), findsWidgets);
      expect(find.text('Monitor Teste'), findsWidgets);
      // Origem (setor atual, lido do patrimônio) e destino
      expect(find.text('Gerencia de Tecnologia'), findsWidgets);
      expect(find.text('Nucleo de Testes Automatizados'), findsWidgets);
      expect(find.text('Sala 10'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget);
      // Documento
      expect(find.text('999999/2026/TESTE'), findsWidgets);
      expect(find.text('4556'), findsWidgets);
    });

    testWidgets('5. a confirmação de entrega física é OBRIGATÓRIA: o botão final só habilita depois dela', (
      tester,
    ) async {
      final c = await _abrirConfirmacao2(tester);
      expect(find.text(textoConfirmacaoEntregaFisica), findsOneWidget);
      expect(_confirmarHabilitado(tester), isFalse);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isTrue);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse, reason: 'desmarcar volta a bloquear');
      expect(c.repo.concluirCallCount, 0, reason: 'nada foi enviado ao servidor');
    });

    testWidgets('6. limpeza de responsável/localização: mostra a consequência e exige uma confirmação ADICIONAL', (
      tester,
    ) async {
      final c = await _abrirDetalhe(
        tester,
        _documento([_item()]), // CONFIRMADO_SEM_INFORMACAO nos dois
        patrimonios: [
          _patrimonio(responsavel: 'Fulano Atual', localizacaoId: 'loc-atual', localizacaoNome: 'Sala Antiga'),
        ],
      );
      await _abrirConfirmacao(tester);

      // destinos nulos, mostrados com clareza
      expect(find.text(textoNaoInformado), findsNWidgets(2));
      // consequências
      expect(
        find.text('A conclusão removerá o responsável atual (Fulano Atual) e o patrimônio ficará DISPONÍVEL.'),
        findsOneWidget,
      );
      expect(find.text('A conclusão removerá a localização atual (Sala Antiga).'), findsOneWidget);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse, reason: 'só a entrega física NÃO basta quando há limpeza');

      await _marcar(tester, _chaveLimpeza);
      expect(_confirmarHabilitado(tester), isTrue);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse, reason: 'as duas confirmações são necessárias');
      expect(c.repo.concluirCallCount, 0);
    });

    testWidgets('6b. só o responsável é limpo: a mensagem cita só o responsável', (tester) async {
      await _abrirDetalhe(
        tester,
        _documento([
          _item(decisaoLocalizacao: SeiDecisaoCampo.definido, localizacaoId: 'loc-1', localizacaoNome: 'Sala 10'),
        ]),
        patrimonios: [_patrimonio(responsavel: 'Fulano Atual')],
      );
      await _abrirConfirmacao(tester);
      expect(find.textContaining('removerá o responsável atual (Fulano Atual)'), findsOneWidget);
      expect(find.textContaining('removerá a localização atual'), findsNothing);
      expect(find.byKey(_chaveLimpeza), findsOneWidget);
    });

    testWidgets('7. confirmação SEM limpeza: sem a segunda caixa, e envia confirmarLimpezaDestino = false', (
      tester,
    ) async {
      // destino sem informação, mas o patrimônio já não tem localização nem responsável: nada a limpar
      final c = await _abrirConfirmacao2(tester);
      expect(find.byKey(_chaveLimpeza), findsNothing);
      expect(find.textContaining('A conclusão removerá'), findsNothing);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isTrue);
      await _clicarConfirmar(tester);

      expect(c.repo.concluirCallCount, 1);
      expect(c.repo.conclusoes.single['confirmarLimpezaDestino'], isFalse);
    });

    testWidgets('7b. com limpeza confirmada, envia confirmarLimpezaDestino = true (nunca automático)', (tester) async {
      final c = await _abrirDetalhe(
        tester,
        _documento([_item()]),
        patrimonios: [_patrimonio(responsavel: 'Fulano Atual')],
      );
      await _abrirConfirmacao(tester);
      await _marcar(tester, _chaveEntrega);
      await _marcar(tester, _chaveLimpeza);
      await _clicarConfirmar(tester);

      expect(c.repo.conclusoes.single['confirmarLimpezaDestino'], isTrue);
    });

    testWidgets('8. observação é OPCIONAL: conclui sem observação; com observação, ela é enviada', (tester) async {
      final c = await _abrirConfirmacao2(tester);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isTrue, reason: 'observação não é exigida');
      await tester.enterText(find.byKey(const Key('sei-concluir-observacao')), 'Entregue ao Fulano');
      await tester.pump();
      await _clicarConfirmar(tester);

      expect(c.repo.conclusoes.single['observacao'], 'Entregue ao Fulano');
      expect(c.repo.conclusoes.single['versaoEsperada'], 1);
      expect(c.repo.conclusoes.single['itemId'], 'item-1');
      expect(c.repo.conclusoes.single['documentoId'], _docId);
    });

    testWidgets('bloqueios conhecidos (item sem patrimônio) desabilitam o botão mesmo com a confirmação marcada', (
      tester,
    ) async {
      final c = await _abrirDetalhe(tester, _documento([_item(patrimonioId: null)]));
      await _abrirConfirmacao(tester);
      expect(find.byKey(const Key('sei-concluir-bloqueios')), findsOneWidget);
      expect(find.textContaining('não está vinculado a um patrimônio'), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
      expect(c.repo.concluirCallCount, 0);
    });

    testWidgets('bloqueio: origem do documento diverge do setor atual do patrimônio', (tester) async {
      await _abrirDetalhe(
        tester,
        _documento([_item()]),
        patrimonios: [_patrimonio(setorId: 'setor-ntat', setorNome: 'Nucleo de Testes Automatizados')],
      );
      await _abrirConfirmacao(tester);
      expect(find.textContaining('Origem divergente'), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
    });

    testWidgets('bloqueio: movimentação dentro do mesmo setor exige localização definida', (tester) async {
      await _abrirDetalhe(tester, _documento([_item(destinoSetorId: 'setor-getec')]));
      await _abrirConfirmacao(tester);
      expect(find.textContaining('mesmo setor exige uma localização de destino definida'), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
    });

    testWidgets('"Voltar" fecha sem chamar a RPC', (tester) async {
      final c = await _abrirConfirmacao2(tester);
      await tester.tap(find.byKey(const Key('sei-concluir-voltar')));
      await tester.pumpAndSettle();
      expect(find.byKey(_chaveConfirmar), findsNothing);
      expect(c.repo.concluirCallCount, 0);
    });
  });

  group('9/10/15. execução e sucesso', () {
    testWidgets('sucesso normal: mensagem, linha vira CONCLUÍDO, botão some, movimentação fica no detalhe', (
      tester,
    ) async {
      final c = await _abrirDetalhe(tester, _documento([_item(), _item(linha: 2)]));
      await _abrirConfirmacao(tester);
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);

      expect(c.repo.concluirCallCount, 1);
      expect(find.text(mensagemSeiEntregaConcluida), findsOneWidget);
      expect(find.byKey(_chaveConfirmar), findsNothing, reason: 'o diálogo fechou');

      // o documento foi RELIDO: item 1 concluído, com movimentacao_id
      final atualizado = await c.repo.obterPorId(_docId);
      expect(atualizado.itens[0].status, SeiItemPendenciaStatus.concluido);
      expect(atualizado.itens[0].movimentacaoId, 'mov-1');
      expect(atualizado.versao, 2);

      // na tela: só o item 2 ainda oferece "Concluir entrega"
      expect(_botoesConcluirNaLista, findsOneWidget);
      expect(find.text('Concluído'), findsWidgets);

      // 15. movimentacao_id visível na ficha do item concluído
      await tester.tap(find.text('900000001').first);
      await tester.pumpAndSettle();
      expect(find.text('Movimentação registrada'), findsOneWidget);
      expect(find.text('mov-1'), findsOneWidget);
    });

    testWidgets('9. ja_concluido = true NÃO é erro: avisa "já havia sido concluído", recarrega e não duplica', (
      tester,
    ) async {
      final c = await _abrirDetalhe(tester, _documento([_item(), _item(linha: 2)]));
      await _abrirConfirmacao(tester);
      // outra sessão conclui o MESMO item enquanto o diálogo está aberto
      await c.repo.concluirItem(documentoId: _docId, itemId: 'item-1', versaoEsperada: 1);
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);

      expect(find.text(mensagemSeiItemJaConcluido), findsOneWidget);
      expect(find.text(mensagemSeiEntregaConcluida), findsNothing);
      expect(find.byKey(const Key('sei-concluir-erro')), findsNothing);
      final eventos = await c.repo.listarEventos(_docId);
      expect(eventos.where((e) => e.tipo == SeiTipoEventoDocumento.itemConcluido), hasLength(1));
      expect((await c.repo.obterPorId(_docId)).itens[0].movimentacaoId, 'mov-1', reason: 'mesma movimentação');
      expect(_botoesConcluirNaLista, findsOneWidget, reason: 'a tela foi recarregada: só o item 2 segue pendente');
    });

    testWidgets('10. clique duplo NÃO chama a RPC duas vezes; botão desabilitado e progresso enquanto executa', (
      tester,
    ) async {
      final c = await _abrirConfirmacao2(tester);
      final espera = Completer<void>();
      c.repo.aguardarConclusao = espera;
      await _marcar(tester, _chaveEntrega);

      await tester.tap(find.byKey(_chaveConfirmar));
      await tester.pump();
      expect(find.text('Concluindo…'), findsOneWidget);
      expect(_confirmarHabilitado(tester), isFalse);

      // segundo clique enquanto a primeira chamada ainda não terminou
      await tester.tap(find.byKey(_chaveConfirmar), warnIfMissed: false);
      await tester.pump();
      expect(c.repo.concluirCallCount, 1);

      espera.complete();
      await tester.pumpAndSettle();
      expect(c.repo.concluirCallCount, 1, reason: 'uma única chamada, mesmo com dois cliques');
      expect(find.text(mensagemSeiEntregaConcluida), findsOneWidget);
    });

    testWidgets('durante a execução o diálogo não pode ser fechado ("Voltar" desabilitado)', (tester) async {
      final c = await _abrirConfirmacao2(tester);
      c.repo.aguardarConclusao = Completer<void>();
      await _marcar(tester, _chaveEntrega);
      await tester.tap(find.byKey(_chaveConfirmar));
      await tester.pump();

      expect(tester.widget<TextButton>(find.byKey(const Key('sei-concluir-voltar'))).onPressed, isNull);
      c.repo.aguardarConclusao!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('3/11/12. erros da RPC', () {
    testWidgets('11. P0010 (conflito de versão): mensagem clara, nada concluído, detalhes técnicos opcionais', (
      tester,
    ) async {
      final c = await _abrirDetalhe(tester, _documento([_item(), _item(linha: 2)]));
      await _abrirConfirmacao(tester);
      // outra pessoa cancela o item 2: a versão do documento muda
      await c.repo.cancelarItem(itemId: 'item-2', motivo: 'x');
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);

      expect(find.byKey(const Key('sei-concluir-erro')), findsOneWidget);
      expect(find.textContaining('O documento foi alterado por outra pessoa'), findsOneWidget);
      expect(find.textContaining('Conflito de edição'), findsNothing, reason: 'o texto cru não é a mensagem principal');
      expect(_confirmarHabilitado(tester), isFalse, reason: 'sem tentativa cega de repetir');

      await tester.ensureVisible(find.text('Detalhes técnicos'));
      await tester.tap(find.text('Detalhes técnicos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Código: P0010'), findsOneWidget);
      expect(find.textContaining('Servidor: Conflito de edição: versão 1 informada'), findsOneWidget);

      // "Fechar e atualizar" relê o documento (item 2 aparece cancelado)
      await tester.tap(find.text('Fechar e atualizar'));
      await tester.pumpAndSettle();
      expect(find.byKey(_chaveConfirmar), findsNothing);
      expect(_botoesConcluirNaLista, findsOneWidget);
      expect((await c.repo.obterPorId(_docId)).itens[0].status, SeiItemPendenciaStatus.pendente);
    });

    const casos = <String, String>{
      'P0030': 'estado deste item está inconsistente',
      'P0031': 'vínculo do item com o patrimônio está incoerente',
      'P0032': 'estado atual do patrimônio diverge',
      'P0033': 'foi movimentado depois que a pendência foi criada',
      'P0034': 'mesmo documento SEI (possível entrega duplicada)',
      'P0035': 'limparia a localização ou o responsável atual',
    };
    for (final entrada in casos.entries) {
      testWidgets('12. ${entrada.key}: mensagem compreensível (sem Postgres cru) e detalhes técnicos', (tester) async {
        final c = await _abrirConfirmacao2(tester);
        c.repo.falhaNaConclusao = falhaDeConclusaoSei(
          codigo: entrada.key,
          mensagemDoServidor: 'RAW_POSTGRES_${entrada.key} item 0000-uuid',
        );
        await _marcar(tester, _chaveEntrega);
        await _clicarConfirmar(tester);

        expect(find.textContaining(entrada.value), findsOneWidget);
        expect(find.textContaining('RAW_POSTGRES_${entrada.key}'), findsNothing);
        expect(find.byKey(_chaveConfirmar), findsOneWidget, reason: 'o diálogo continua aberto, mostrando o erro');
        expect(_confirmarHabilitado(tester), isFalse);

        await tester.ensureVisible(find.text('Detalhes técnicos'));
        await tester.tap(find.text('Detalhes técnicos'));
        await tester.pumpAndSettle();
        expect(find.textContaining('RAW_POSTGRES_${entrada.key}'), findsOneWidget);
        expect(find.textContaining('Código: ${entrada.key}'), findsOneWidget);
        expect(c.repo.concluirCallCount, 1);
      });
    }

    testWidgets('falha de comunicação (resultado incerto): avisa para NÃO repetir e recarrega ao fechar', (
      tester,
    ) async {
      final c = await _abrirConfirmacao2(tester);
      c.repo.falhaNaConclusao = Exception('timeout');
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);

      expect(find.byKey(const Key('sei-concluir-incerto')), findsOneWidget);
      expect(find.textContaining('NÃO repita a ação'), findsOneWidget);
      await tester.tap(find.text('Fechar e atualizar'));
      await tester.pumpAndSettle();
      expect(find.text(mensagemConclusaoIncerta), findsOneWidget);
      expect(c.repo.concluirCallCount, 1);
    });
  });

  group('12/13/14. primeira conclusão, itens restantes e histórico', () {
    testWidgets('13. após a primeira conclusão o documento deixa de permitir edição global', (tester) async {
      final c = await _abrirDetalhe(tester, _documento([_item(), _item(linha: 2)]));
      final editar = find.widgetWithText(TextButton, 'Editar documento');
      expect(tester.widget<TextButton>(editar).onPressed, isNotNull, reason: 'antes: edição permitida');

      await _abrirConfirmacao(tester);
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);

      expect(tester.widget<TextButton>(editar).onPressed, isNull, reason: 'depois: edição bloqueada');
      expect(find.textContaining('já tem item(ns) concluído(s)'), findsWidgets);
      expect(c.repo.concluirCallCount, 1);
    });

    testWidgets('14. os outros itens PENDENTES continuam podendo ser concluídos e cancelados', (tester) async {
      final c = await _abrirDetalhe(
        tester,
        _documento([_item(), _item(linha: 2), _item(linha: 3)]),
        patrimonios: [
          _patrimonio(),
          _patrimonio(id: 'pat-2'),
          _patrimonio(id: 'pat-3'),
        ],
      );
      await _abrirConfirmacao(tester);
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);

      expect(_botoesConcluirNaLista, findsNWidgets(2));
      expect(_botoesCancelarNaLista, findsNWidgets(2));

      // e o segundo item pode ser concluído em seguida (versão relida = 2)
      await _abrirConfirmacao(tester);
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);
      expect(c.repo.concluirCallCount, 2);
      expect(c.repo.conclusoes.last['versaoEsperada'], 2);
      expect(_botoesConcluirNaLista, findsOneWidget);
    });

    testWidgets('11. histórico: "Item concluído" com patrimônio, usuário, movimentação e origem → destino', (
      tester,
    ) async {
      final c = await _abrirDetalhe(
        tester,
        _documento([
          _item(
            decisaoLocalizacao: SeiDecisaoCampo.definido,
            localizacaoId: 'loc-1',
            localizacaoNome: 'Sala 10',
            decisaoResponsavel: SeiDecisaoCampo.definido,
            responsavel: 'Maria',
          ),
        ]),
      );
      await _abrirConfirmacao(tester);
      await _marcar(tester, _chaveEntrega);
      await _clicarConfirmar(tester);
      expect(c.repo.concluirCallCount, 1);

      final tile = find.text('Histórico de alterações');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      final historico = find.byType(SeiHistoricoAlteracoes);
      Finder dentro(Finder f) => find.descendant(of: historico, matching: f);
      expect(dentro(find.text('Item concluído')), findsOneWidget);
      expect(dentro(find.text('Usuário: Usuária de Teste')), findsOneWidget);
      expect(dentro(find.text('Item afetado: Patrimônio 900000001 (linha 1)')), findsOneWidget);
      expect(dentro(find.text('Movimentação criada:')), findsOneWidget);
      expect(dentro(find.text('mov-1')), findsOneWidget);
      expect(dentro(find.text('Origem → Destino:')), findsOneWidget);
      expect(dentro(find.text('GETEC')), findsOneWidget);
      expect(dentro(find.text('NTAT')), findsOneWidget);
      expect(dentro(find.text('Maria')), findsOneWidget);
    });
  });

  group('Android compacto (360x640)', () {
    testWidgets('lista com as duas ações e confirmação abrem sem overflow; botão final acessível', (tester) async {
      final c = await _abrirDetalhe(
        tester,
        _documento([_item()]),
        patrimonios: [_patrimonio(responsavel: 'Fulano Atual', localizacaoId: 'l', localizacaoNome: 'Sala Antiga')],
        tamanho: const Size(360, 640),
      );
      expect(_botoesConcluirNaLista, findsOneWidget);
      expect(_botoesCancelarNaLista, findsOneWidget);

      await tester.ensureVisible(_botoesConcluirNaLista);
      await tester.pumpAndSettle();
      await tester.tap(_botoesConcluirNaLista);
      await tester.pumpAndSettle();

      await _marcar(tester, _chaveLimpeza);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isTrue);
      expect(tester.getRect(find.byKey(_chaveConfirmar)).bottom, lessThanOrEqualTo(640));
      expect(c.repo.concluirCallCount, 0);
    });
  });

  // PROMPT 11.4.3.1 — PENDENTE não é CONFIRMADO_SEM_INFORMACAO.
  group('11.4.3.1 PENDENTE x CONFIRMADO_SEM_INFORMACAO x DEFINIDO', () {
    final patrimonioComTudo = _patrimonio(
      responsavel: 'Fulano Atual',
      localizacaoId: 'loc-atual',
      localizacaoNome: 'Sala Antiga',
    );

    Future<_Cenario> abrir(WidgetTester tester, SeiItemPendente item) async {
      final c = await _abrirDetalhe(tester, _documento([item]), patrimonios: [patrimonioComTudo]);
      await _abrirConfirmacao(tester);
      return c;
    }

    void semEfeitoDestrutivo() {
      expect(find.textContaining('A conclusão removerá'), findsNothing);
      expect(find.textContaining('ficará DISPONÍVEL'), findsNothing);
      expect(find.byKey(_chaveLimpeza), findsNothing);
    }

    testWidgets('1. localização PENDENTE: "Pendente de definição", sem aviso de remoção e sem checkbox de limpeza', (
      tester,
    ) async {
      final c = await abrir(
        tester,
        _item(
          decisaoLocalizacao: SeiDecisaoCampo.pendente,
          decisaoResponsavel: SeiDecisaoCampo.definido,
          responsavel: 'Maria',
        ),
      );
      expect(find.text(textoPendenteDeDefinicao), findsOneWidget);
      expect(find.text(textoNaoInformado), findsNothing);
      semEfeitoDestrutivo();
      expect(find.text('Defina a localização de destino (pela edição do documento).'), findsOneWidget);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse, reason: 'bloqueado enquanto houver decisão pendente');
      expect(c.repo.concluirCallCount, 0);
    });

    testWidgets('2. responsável PENDENTE: não prevê DISPONÍVEL e a conclusão fica bloqueada', (tester) async {
      final c = await abrir(
        tester,
        _item(
          decisaoLocalizacao: SeiDecisaoCampo.definido,
          localizacaoId: 'loc-1',
          localizacaoNome: 'Sala 10',
          decisaoResponsavel: SeiDecisaoCampo.pendente,
        ),
      );
      expect(find.text(textoPendenteDeDefinicao), findsOneWidget);
      expect(find.text(textoNaoInformado), findsNothing);
      expect(find.text(textoSituacaoIndeterminada), findsOneWidget);
      expect(find.text(PatrimonioStatus.disponivel.label), findsNothing);
      semEfeitoDestrutivo();
      expect(find.text('Defina o responsável de destino (pela edição do documento).'), findsOneWidget);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
      expect(c.repo.concluirCallCount, 0);
    });

    testWidgets('3. os dois PENDENTES (caso real): nenhum efeito destrutivo, situação indeterminada e bloqueio', (
      tester,
    ) async {
      final c = await abrir(
        tester,
        _item(decisaoLocalizacao: SeiDecisaoCampo.pendente, decisaoResponsavel: SeiDecisaoCampo.pendente),
      );
      expect(find.text(textoPendenteDeDefinicao), findsNWidgets(2));
      expect(find.text(textoNaoInformado), findsNothing);
      expect(find.text(textoSituacaoIndeterminada), findsOneWidget);
      semEfeitoDestrutivo();
      expect(find.byKey(const Key('sei-concluir-bloqueios')), findsOneWidget);
      expect(find.text('Defina a localização de destino (pela edição do documento).'), findsOneWidget);
      expect(find.text('Defina o responsável de destino (pela edição do documento).'), findsOneWidget);

      // a confirmação física pode ficar visível/marcada, mas o botão final segue desabilitado
      expect(find.byKey(_chaveEntrega), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
      expect(c.repo.concluirCallCount, 0);
    });

    testWidgets('4. CONFIRMADO_SEM_INFORMACAO com localização atual: mostra a remoção e exige confirmação', (
      tester,
    ) async {
      await _abrirDetalhe(
        tester,
        _documento([_item(decisaoResponsavel: SeiDecisaoCampo.definido, responsavel: 'Maria')]),
        patrimonios: [_patrimonio(localizacaoId: 'loc-atual', localizacaoNome: 'Sala Antiga')],
      );
      await _abrirConfirmacao(tester);
      expect(find.text(textoNaoInformado), findsOneWidget);
      expect(find.text('A conclusão removerá a localização atual (Sala Antiga).'), findsOneWidget);
      expect(find.byKey(_chaveLimpeza), findsOneWidget);

      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
      await _marcar(tester, _chaveLimpeza);
      expect(_confirmarHabilitado(tester), isTrue);
    });

    testWidgets('5. CONFIRMADO_SEM_INFORMACAO com responsável atual: remoção, ficará DISPONÍVEL e confirmação', (
      tester,
    ) async {
      await _abrirDetalhe(
        tester,
        _documento([
          _item(decisaoLocalizacao: SeiDecisaoCampo.definido, localizacaoId: 'loc-1', localizacaoNome: 'Sala 10'),
        ]),
        patrimonios: [_patrimonio(responsavel: 'Fulano Atual')],
      );
      await _abrirConfirmacao(tester);
      expect(find.text(textoNaoInformado), findsOneWidget);
      expect(find.text(PatrimonioStatus.disponivel.label), findsOneWidget, reason: 'situação após a conclusão');
      expect(
        find.text('A conclusão removerá o responsável atual (Fulano Atual) e o patrimônio ficará DISPONÍVEL.'),
        findsOneWidget,
      );
      expect(find.byKey(_chaveLimpeza), findsOneWidget);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isFalse);
      await _marcar(tester, _chaveLimpeza);
      expect(_confirmarHabilitado(tester), isTrue);
    });

    testWidgets('6. DEFINIDO: mostra os valores escolhidos, sem aviso indevido nem "Pendente"', (tester) async {
      await abrir(
        tester,
        _item(
          decisaoLocalizacao: SeiDecisaoCampo.definido,
          localizacaoId: 'loc-1',
          localizacaoNome: 'Sala 203',
          decisaoResponsavel: SeiDecisaoCampo.definido,
          responsavel: 'Fulano da Silva',
        ),
      );
      expect(find.text('Sala 203'), findsOneWidget);
      expect(find.text('Fulano da Silva'), findsOneWidget);
      expect(find.text(PatrimonioStatus.emUso.label), findsWidgets);
      expect(find.text(textoPendenteDeDefinicao), findsNothing);
      expect(find.text(textoNaoInformado), findsNothing);
      semEfeitoDestrutivo();
      expect(find.byKey(const Key('sei-concluir-bloqueios')), findsNothing);
      await _marcar(tester, _chaveEntrega);
      expect(_confirmarHabilitado(tester), isTrue);
    });

    test('plano: PENDENTE nunca vira null confirmado nem consequência destrutiva', () {
      final plano = planejarConclusaoEntrega(
        documento: _documento([_item()]),
        item: _item(decisaoLocalizacao: SeiDecisaoCampo.pendente, decisaoResponsavel: SeiDecisaoCampo.pendente),
        patrimonioAtual: patrimonioComTudo,
      );
      expect(plano.localizacaoPendente, isTrue);
      expect(plano.responsavelPendente, isTrue);
      expect(plano.limpaLocalizacao, isFalse);
      expect(plano.limpaResponsavel, isFalse);
      expect(plano.exigeConfirmacaoDeLimpeza, isFalse);
      expect(plano.statusResultante, isNull);
      expect(plano.podeConfirmar, isFalse);
      expect(plano.bloqueios, hasLength(2));

      // CONFIRMADO_SEM_INFORMACAO, com os mesmos dados atuais, SIM limpa
      final confirmado = planejarConclusaoEntrega(
        documento: _documento([_item()]),
        item: _item(),
        patrimonioAtual: patrimonioComTudo,
      );
      expect(confirmado.limpaLocalizacao, isTrue);
      expect(confirmado.limpaResponsavel, isTrue);
      expect(confirmado.statusResultante, PatrimonioStatus.disponivel);
      expect(confirmado.podeConfirmar, isTrue);
    });
  });

  group('regras puras', () {
    test('planejarConclusaoEntrega: DEFINIDO envia valores; CONFIRMADO_SEM_INFORMACAO envia null (Não informado)', () {
      final definido = planejarConclusaoEntrega(
        documento: _documento([_item()]),
        item: _item(
          decisaoLocalizacao: SeiDecisaoCampo.definido,
          localizacaoId: 'l',
          localizacaoNome: 'Sala 10',
          decisaoResponsavel: SeiDecisaoCampo.definido,
          responsavel: 'Maria',
        ),
        patrimonioAtual: _patrimonio(),
      );
      expect(definido.destinoLocalizacao, 'Sala 10');
      expect(definido.destinoResponsavel, 'Maria');
      expect(definido.statusResultante, PatrimonioStatus.emUso);
      expect(definido.exigeConfirmacaoDeLimpeza, isFalse);
      expect(definido.podeConfirmar, isTrue);

      final semInformacao = planejarConclusaoEntrega(
        documento: _documento([_item()]),
        item: _item(),
        patrimonioAtual: _patrimonio(),
      );
      expect(semInformacao.destinoLocalizacao, isNull);
      expect(semInformacao.destinoResponsavel, isNull);
      expect(semInformacao.statusResultante, PatrimonioStatus.disponivel);
    });

    test('limpeza só é exigida quando HÁ valor atual a apagar', () {
      PatrimonioDetalhe pat({String? resp, String? loc}) =>
          _patrimonio(responsavel: resp, localizacaoId: loc, localizacaoNome: loc);
      SeiPlanoConclusao plano(PatrimonioDetalhe p) =>
          planejarConclusaoEntrega(documento: _documento([_item()]), item: _item(), patrimonioAtual: p);

      expect(plano(pat()).exigeConfirmacaoDeLimpeza, isFalse);
      expect(plano(pat(resp: 'A')).limpaResponsavel, isTrue);
      expect(plano(pat(resp: 'A')).limpaLocalizacao, isFalse);
      expect(plano(pat(loc: 'L')).limpaLocalizacao, isTrue);
      expect(plano(pat(resp: 'A', loc: 'L')).exigeConfirmacaoDeLimpeza, isTrue);
    });

    test('sem patrimônio carregado (ou item sem vínculo), a conclusão fica bloqueada', () {
      final semCarga = planejarConclusaoEntrega(documento: _documento([_item()]), item: _item(), patrimonioAtual: null);
      expect(semCarga.podeConfirmar, isFalse);
      expect(semCarga.bloqueios.single, contains('situação atual do patrimônio'));
    });

    test('mensagemErroConclusaoSei cobre os códigos definidos e preserva 42501, P0001, P0002 e P0010', () {
      for (final codigo in ['42501', 'P0001', 'P0002', 'P0010', 'P0030', 'P0031', 'P0032', 'P0033', 'P0034', 'P0035']) {
        final texto = mensagemErroConclusaoSei(codigo: codigo, mensagemDoServidor: 'raw');
        expect(texto, isNotEmpty, reason: codigo);
        expect(texto, isNot(contains('raw')), reason: '$codigo não pode repassar o texto cru do servidor');
      }
      expect(mensagemErroConclusaoSei(codigo: '42501', mensagemDoServidor: ''), contains('permissão'));
      expect(mensagemErroConclusaoSei(codigo: 'P0002', mensagemDoServidor: ''), contains('não encontrado'));
      expect(
        mensagemErroConclusaoSei(codigo: 'P0001', mensagemDoServidor: 'Item x não está PENDENTE (está CANCELADO)'),
        contains('não está mais pendente'),
      );
      expect(mensagemErroConclusaoSei(codigo: 'XX999', mensagemDoServidor: ''), contains('Nada foi alterado'));
    });

    test('falhaDeConclusaoSei guarda o erro técnico original para "Detalhes técnicos"', () {
      final falha = falhaDeConclusaoSei(
        codigo: 'P0033',
        mensagemDoServidor: 'O patrimônio 1 foi movimentado depois',
        dica: 'dica',
      );
      expect(falha.operacao, operacaoConcluirItemSei);
      expect(falha.codigo, 'P0033');
      expect(falha.textoTecnico, contains('Servidor: O patrimônio 1 foi movimentado depois'));
      expect(falha.textoTecnico, contains('Código: P0033'));
      expect(falha.textoTecnico, contains('Dica: dica'));
    });

    test('SeiConclusaoItemResultado.fromJson interpreta o jsonb da RPC (nova conclusão e ja_concluido)', () {
      Map<String, dynamic> json({required bool jaConcluido}) => {
        'ja_concluido': jaConcluido,
        'documento': {'id': _docId, 'versao': 4, 'assunto': 'x'},
        'item': {
          'id': 'item-1',
          'documento_id': _docId,
          'linha': 1,
          'patrimonio_id': 'pat-1',
          'numero_patrimonio_original': '900000001',
          'numero_patrimonio_corrigido': null,
          'origem_setor_id': 'setor-getec',
          'destino_setor_id': 'setor-ntat',
          'decisao_localizacao': 'CONFIRMADO_SEM_INFORMACAO',
          'decisao_responsavel': 'DEFINIDO',
          'responsavel_destino': 'Maria',
          'status': 'CONCLUIDO',
          'movimentacao_id': 'mov-7',
          'criado_em': '2026-09-25T10:00:00+00:00',
        },
        'movimentacao': {
          'id': 'mov-7',
          'patrimonio_id': 'pat-1',
          'tipo': 'TRANSFERENCIA',
          'origem_id': 'setor-getec',
          'destino_id': 'setor-ntat',
          'responsavel_destino': 'Maria',
          'realizado_por': 'user-1',
          'data_movimentacao': '2026-09-25T12:00:00+00:00',
          'criado_em': '2026-09-25T12:00:00+00:00',
        },
      };

      final nova = SeiConclusaoItemResultado.fromJson(json(jaConcluido: false));
      expect(nova.jaConcluido, isFalse);
      expect(nova.documentoId, _docId);
      expect(nova.documentoVersao, 4);
      expect(nova.item.status, SeiItemPendenciaStatus.concluido);
      expect(nova.item.movimentacaoId, 'mov-7');
      expect(nova.movimentacao.id, 'mov-7');
      expect(nova.movimentacao.tipo, MovimentacaoTipo.transferencia);

      expect(SeiConclusaoItemResultado.fromJson(json(jaConcluido: true)).jaConcluido, isTrue);
    });

    test('SeiEscritaFalhouException é a falha tipada usada pela conclusão', () {
      final falha = falhaDeConclusaoSei(codigo: 'P0010', mensagemDoServidor: 'x');
      expect(falha, isA<SeiEscritaFalhouException>());
    });
  });
}

/// Abre o detalhe com UM item pendente (destino sem informação, patrimônio SEM
/// localização/responsável atuais — nada a limpar) e já abre a confirmação.
Future<_Cenario> _abrirConfirmacao2(WidgetTester tester) async {
  final c = await _abrirDetalhe(tester, _documento([_item()]));
  await _abrirConfirmacao(tester);
  return c;
}
