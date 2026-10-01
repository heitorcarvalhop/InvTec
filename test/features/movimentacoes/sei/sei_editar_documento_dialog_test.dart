import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/documentos_sei_repository.dart';
import 'package:invtec/features/movimentacoes/sei/domain/documentos_sei_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_item_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_lote_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_evento_documento.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// PROMPT 11.3.6 — conecta o botão "Editar documento" à RPC
/// `editar_documento_sei_pendente` (já implementada desde o PROMPT 11.3.2
/// em `DocumentosSeiRepository.editarDocumento`/`FakeDocumentosSeiRepository`
/// — este arquivo testa só a camada de UI nova: o botão em
/// `sei_pendencia_detalhe_dialog.dart` e o formulário
/// `sei_editar_documento_dialog.dart`). Nunca usa o Despacho 577 real, nunca
/// chama `registrarMovimentacao`, nunca faz UPDATE/INSERT/DELETE em
/// produção — só o fake em memória.

Profile _profile() => Profile(
  id: 'user-1',
  nome: 'Usuária de Teste',
  email: 'teste@example.com',
  perfil: ProfilePerfil.admin,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorGeasi = Setor(id: 'setor-geasi', nome: 'Gerência de Licenciamento', sigla: 'GEASI', ativo: true, criadoEm: DateTime(2026, 1, 1));

final _localizacaoSala101 = Localizacao(id: 'loc-101', setorId: 'setor-geasi', nome: 'Sala 101', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _localizacaoSala102 = Localizacao(id: 'loc-102', setorId: 'setor-geasi', nome: 'Sala 102', ativo: true, criadoEm: DateTime(2026, 1, 1));

SeiItemPendente _itemPendente({
  int linha = 1,
  String numeroPatrimonioOriginal = '1001',
  String destinoTextoOriginal = 'Gerência de Licenciamento – GEASI',
  String numeroChamadoOriginal = '4556',
  String equipamentoTextoOriginal = 'Monitor Positivo',
  String? destinoSetorId,
  String? destinoSetorNome,
  String? destinoSetorSigla,
  String? localizacaoDestinoId,
  String? localizacaoDestinoNome,
  SeiDecisaoCampo decisaoLocalizacao = SeiDecisaoCampo.pendente,
  String? responsavelDestino,
  SeiDecisaoCampo decisaoResponsavel = SeiDecisaoCampo.pendente,
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
  String? movimentacaoId,
}) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: 'doc-1',
    linha: linha,
    numeroPatrimonio: SeiValorCorrigivel(original: numeroPatrimonioOriginal),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC - Gerencia de Tecnologia'),
    origemSetorId: 'setor-getec',
    origemSetorNome: 'Gerencia de Tecnologia',
    origemSetorSigla: 'GETEC',
    destinoTexto: SeiValorCorrigivel(original: destinoTextoOriginal),
    destinoSetorId: destinoSetorId,
    destinoSetorNome: destinoSetorNome,
    destinoSetorSigla: destinoSetorSigla,
    localizacaoDestinoId: localizacaoDestinoId,
    localizacaoDestinoNome: localizacaoDestinoNome,
    decisaoLocalizacao: decisaoLocalizacao,
    responsavelDestino: responsavelDestino,
    decisaoResponsavel: decisaoResponsavel,
    numeroChamado: SeiValorCorrigivel(original: numeroChamadoOriginal),
    equipamentoTexto: SeiValorCorrigivel(original: equipamentoTextoOriginal),
    status: status,
    movimentacaoId: movimentacaoId,
    criadoEm: DateTime(2026, 1, 1),
  );
}

SeiDocumentoPendente _documento({required String id, required List<SeiItemPendente> itens, int versao = 1}) {
  return SeiDocumentoPendente.fromItens(
    id: id,
    numeroDocumentoSei: '95955192',
    numeroProcesso: '2026.0001',
    numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
    assunto: 'Transferência de equipamentos',
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

/// Abre o diálogo de DETALHE (mesmo ponto de entrada real: o botão "Editar
/// documento" fica dentro dele) com as dependências de setor/localização
/// disponíveis — necessárias para o dropdown "Setor de destino resolvido" e
/// os chips de localização do formulário de edição.
Future<FakeDocumentosSeiRepository> _pumpDetalheComEdicao(
  WidgetTester tester,
  SeiDocumentoPendente documento, {
  List<Setor> setores = const [],
  List<Localizacao> localizacoes = const [],
}) async {
  final fakeAuth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _profile());
  addTearDown(fakeAuth.dispose);
  final fakeDocumentosSei = FakeDocumentosSeiRepository(documentosIniciais: [documento]);

  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        documentosSeiRepositoryProvider.overrideWithValue(fakeDocumentosSei),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
        localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: localizacoes)),
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
  return fakeDocumentosSei;
}

Future<void> _abrirFormularioEdicao(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Editar documento'));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Repositório que sempre recusa `editarDocumento` com
/// [SeiDocumentoBloqueadoParaEdicaoException] — simula "o documento recebeu
/// sua primeira conclusão durante a edição" sem depender de uma corrida real
/// de versão (a versão otimista sempre muda numa conclusão real, então o
/// conflito de versão — testado à parte — sempre dispararia primeiro; este
/// dublê isola especificamente o tratamento do bloqueio na UI).
class _RepositorioBloqueadoParaEdicao implements DocumentosSeiRepository {
  _RepositorioBloqueadoParaEdicao(this._delegate);

  final DocumentosSeiRepository _delegate;

  @override
  Future<SeiDocumentoPendente> editarDocumento({
    required String documentoId,
    required int versaoEsperada,
    String? Function()? numeroDocumentoSei,
    String? Function()? numeroProcesso,
    String? Function()? numeroDocumentoFormatado,
    String? Function()? assunto,
    Map<String, SeiItemPendenteEdicao> itensAlterados = const {},
    required String motivo,
  }) async {
    throw SeiDocumentoBloqueadoParaEdicaoException(documentoId);
  }

  @override
  Future<DocumentosSeiResultado> listar({
    int limit = 25,
    int offset = 0,
    MovimentacaoTipo? tipo,
    SeiItemPendenciaStatus? situacaoContemStatus,
    String? numeroDocumentoSei,
    String? numeroProcesso,
    String? numeroPatrimonio,
  }) => _delegate.listar(
    limit: limit,
    offset: offset,
    tipo: tipo,
    situacaoContemStatus: situacaoContemStatus,
    numeroDocumentoSei: numeroDocumentoSei,
    numeroProcesso: numeroProcesso,
    numeroPatrimonio: numeroPatrimonio,
  );

  @override
  Future<SeiDocumentoPendente> obterPorId(String documentoId) => _delegate.obterPorId(documentoId);

  @override
  Future<List<SeiEventoDocumento>> listarEventos(String documentoId) => _delegate.listarEventos(documentoId);

  @override
  Future<List<SeiDocumentoPendente>> buscarPossivelDuplicata({required String numeroDocumentoSei, String? numeroProcesso}) =>
      _delegate.buscarPossivelDuplicata(numeroDocumentoSei: numeroDocumentoSei, numeroProcesso: numeroProcesso);

  @override
  Future<SeiDocumentoPendente> salvarRascunho(SeiDocumentoPendenteRascunho rascunho, {bool confirmarDuplicata = false}) =>
      _delegate.salvarRascunho(rascunho, confirmarDuplicata: confirmarDuplicata);

  @override
  Future<SeiDocumentoPendente> cancelarItem({required String itemId, required String motivo}) =>
      _delegate.cancelarItem(itemId: itemId, motivo: motivo);

  @override
  Future<SeiDocumentoPendente> cancelarPendentesDoDocumento({required String documentoId, required String motivo}) =>
      _delegate.cancelarPendentesDoDocumento(documentoId: documentoId, motivo: motivo);

  @override
  Future<SeiConclusaoItemResultado> concluirItem({
    required String documentoId,
    required String itemId,
    required int versaoEsperada,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  }) => _delegate.concluirItem(
    documentoId: documentoId,
    itemId: itemId,
    versaoEsperada: versaoEsperada,
    observacao: observacao,
    confirmarLimpezaDestino: confirmarLimpezaDestino,
  );

  @override
  Future<SeiConclusaoLoteResultado> concluirItensLote({
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    required String loteId,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  }) => _delegate.concluirItensLote(
    documentoId: documentoId,
    itemIds: itemIds,
    versaoEsperada: versaoEsperada,
    loteId: loteId,
    observacao: observacao,
    confirmarLimpezaDestino: confirmarLimpezaDestino,
  );

  @override
  Future<SeiConclusaoLoteResultado?> buscarLotePorId({
    required String loteId,
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    String? observacao,
    required bool confirmarLimpezaDestino,
  }) => _delegate.buscarLotePorId(
    loteId: loteId,
    documentoId: documentoId,
    itemIds: itemIds,
    versaoEsperada: versaoEsperada,
    observacao: observacao,
    confirmarLimpezaDestino: confirmarLimpezaDestino,
  );
}

void main() {
  group('PROMPT 11.3.6 — botão "Editar documento"', () {
    testWidgets('disponível (habilitado) enquanto nenhum item está concluído', (tester) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente(), _itemPendente(linha: 2)]);
      await _pumpDetalheComEdicao(tester, documento);

      final botao = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botao.onPressed, isNotNull);

      await _abrirFormularioEdicao(tester);
      expect(find.text('DADOS DO DOCUMENTO'), findsOneWidget);
    });

    testWidgets('desabilitado após a primeira conclusão, com tooltip explicando o motivo', (tester) async {
      final documento = _documento(
        id: 'doc-1',
        itens: [
          _itemPendente(),
          _itemPendente(linha: 2, status: SeiItemPendenciaStatus.concluido, movimentacaoId: 'mov-1'),
        ],
      );
      await _pumpDetalheComEdicao(tester, documento);

      final botao = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Editar documento'));
      expect(botao.onPressed, isNull);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.widgetWithText(TextButton, 'Editar documento'), matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, contains('bloqueados para edição permanentemente'));
    });
  });

  group('PROMPT 11.3.6 — formulário de edição', () {
    testWidgets('edição dos dados do documento (número SEI, processo, formatado, assunto) é salva', (tester) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      final fakeRepo = await _pumpDetalheComEdicao(tester, documento, setores: [_setorGetec, _setorGeasi]);
      await _abrirFormularioEdicao(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Número formatado'), '578/2026/SEMAD/GETEC-12014');
      await tester.enterText(find.widgetWithText(TextField, 'Processo'), '2026.9999');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Corrigindo numeração');
      await tester.pumpAndSettle();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Salvar alterações'));

      expect(find.text('Documento SEI atualizado com sucesso.'), findsOneWidget);
      expect(fakeRepo.editarCallCount, 1);
      final atualizado = await fakeRepo.obterPorId('doc-1');
      expect(atualizado.numeroDocumentoFormatado, '578/2026/SEMAD/GETEC-12014');
      expect(atualizado.numeroProcesso, '2026.9999');
      // A tela de detalhe recarrega sozinha: o novo título já aparece.
      expect(find.text('578/2026/SEMAD/GETEC-12014'), findsOneWidget);
      expect(find.text('Processo: 2026.9999'), findsOneWidget);
    });

    testWidgets('edição do destino (texto) e do número do chamado de um item é salva, preservando o original', (
      tester,
    ) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      final fakeRepo = await _pumpDetalheComEdicao(tester, documento, setores: [_setorGetec, _setorGeasi]);
      await _abrirFormularioEdicao(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Destino (texto do documento)'), 'GESOL - Gerência de Solo');
      await tester.enterText(find.widgetWithText(TextField, 'Número do chamado'), '9999');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Correção manual do destino');
      await tester.pumpAndSettle();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Salvar alterações'));

      final atualizado = await fakeRepo.obterPorId('doc-1');
      final item = atualizado.itens.single;
      expect(item.destinoTexto.corrigido, 'GESOL - Gerência de Solo');
      expect(item.destinoTexto.original, 'Gerência de Licenciamento – GEASI', reason: 'o texto original nunca é sobrescrito');
      expect(item.numeroChamado.corrigido, '9999');
      expect(item.numeroChamado.original, '4556', reason: 'o texto original nunca é sobrescrito');
      // Número patrimonial/equipamento não foram tocados: continuam sem
      // correção (nenhuma escrita de campo que o usuário não alterou).
      expect(item.numeroPatrimonio.foiCorrigido, isFalse);
      expect(item.equipamentoTexto.foiCorrigido, isFalse);
    });

    testWidgets('edição de setor de destino, localização e responsável é salva com os IDs reais', (tester) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      final fakeRepo = await _pumpDetalheComEdicao(
        tester,
        documento,
        setores: [_setorGetec, _setorGeasi],
        localizacoes: [_localizacaoSala101, _localizacaoSala102],
      );
      await _abrirFormularioEdicao(tester);

      await _tocar(tester, find.widgetWithText(DropdownButtonFormField<String>, 'Setor de destino resolvido'));
      await _tocar(tester, find.text('GEASI').last);

      await _tocar(tester, find.text('Sala 102').last);

      await tester.enterText(find.widgetWithText(TextField, 'Nome do responsável'), 'Maria Souza');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Resolvendo destino da linha');
      await tester.pumpAndSettle();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Salvar alterações'));

      final atualizado = await fakeRepo.obterPorId('doc-1');
      final item = atualizado.itens.single;
      expect(item.destinoSetorId, 'setor-geasi');
      expect(item.localizacaoDestinoId, 'loc-102');
      expect(item.decisaoLocalizacao, SeiDecisaoCampo.definido);
      expect(item.responsavelDestino, 'Maria Souza');
      expect(item.decisaoResponsavel, SeiDecisaoCampo.definido);
    });

    testWidgets('motivo é obrigatório — "Salvar alterações" só habilita depois de preenchido', (tester) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      await _pumpDetalheComEdicao(tester, documento, setores: [_setorGetec, _setorGeasi]);
      await _abrirFormularioEdicao(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Processo'), '2026.9999');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar alterações')).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Motivo qualquer');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar alterações')).onPressed, isNotNull);
    });

    testWidgets('sem nenhuma alteração, "Salvar alterações" fica desabilitado mesmo com motivo preenchido', (
      tester,
    ) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      await _pumpDetalheComEdicao(tester, documento, setores: [_setorGetec, _setorGeasi]);
      await _abrirFormularioEdicao(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Motivo qualquer');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar alterações')).onPressed, isNull);
    });

    testWidgets('conflito de versão: edição concorrente é detectada, informada, e nada é sobrescrito', (tester) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()], versao: 1);
      final fakeRepo = await _pumpDetalheComEdicao(tester, documento, setores: [_setorGetec, _setorGeasi]);
      await _abrirFormularioEdicao(tester);

      // Outra sessão edita o MESMO documento (versão 1 -> 2) DEPOIS que este
      // formulário já carregou seus dados, mas ANTES de salvar.
      await fakeRepo.editarDocumento(
        documentoId: 'doc-1',
        versaoEsperada: 1,
        motivo: 'edição de outra sessão',
        assunto: () => 'Assunto mudado por outra sessão',
      );

      await tester.enterText(find.widgetWithText(TextField, 'Processo'), '2026.9999');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Minha correção');
      await tester.pumpAndSettle();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Salvar alterações'));

      expect(find.textContaining('alterado por outra sessão'), findsOneWidget);
      // O diálogo de edição continua aberto — nada foi salvo por cima.
      expect(find.text('DADOS DO DOCUMENTO'), findsOneWidget);
      final atual = await fakeRepo.obterPorId('doc-1');
      expect(atual.assunto, 'Assunto mudado por outra sessão', reason: 'a edição da outra sessão não foi sobrescrita');
      expect(atual.numeroProcesso, '2026.0001', reason: 'a tentativa que falhou não gravou nada');
    });

    testWidgets('documento concluído durante a edição bloqueia o salvamento e informa o usuário', (
      tester,
    ) async {
      // A versão otimista sempre muda numa conclusão real, então o
      // conflito de versão (testado à parte, acima) sempre dispararia
      // primeiro — este teste usa `_RepositorioBloqueadoParaEdicao` para
      // isolar especificamente o tratamento do bloqueio na UI, sem
      // depender dessa corrida.
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      final fakeAuth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _profile());
      addTearDown(fakeAuth.dispose);
      final delegate = FakeDocumentosSeiRepository(documentosIniciais: [documento]);
      final repoBloqueado = _RepositorioBloqueadoParaEdicao(delegate);

      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(fakeAuth),
            documentosSeiRepositoryProvider.overrideWithValue(repoBloqueado),
            setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGeasi])),
            localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository()),
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
      await _abrirFormularioEdicao(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Processo'), '2026.9999');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Minha correção');
      await tester.pumpAndSettle();

      await _tocar(tester, find.widgetWithText(FilledButton, 'Salvar alterações'));

      expect(find.textContaining('bloqueados permanentemente'), findsOneWidget);
      expect(find.text('DADOS DO DOCUMENTO'), findsOneWidget, reason: 'o formulário continua aberto — nada foi salvo');
    });

    testWidgets('descartar fecha o formulário sem nenhuma chamada de escrita ao repositório', (tester) async {
      final documento = _documento(id: 'doc-1', itens: [_itemPendente()]);
      final fakeRepo = await _pumpDetalheComEdicao(tester, documento, setores: [_setorGetec, _setorGeasi]);
      await _abrirFormularioEdicao(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Processo'), '2026.9999');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Motivo da edição (obrigatório)'), 'Motivo qualquer');
      await tester.pumpAndSettle();

      await _tocar(tester, find.widgetWithText(TextButton, 'Descartar'));

      expect(fakeRepo.editarCallCount, 0);
      expect(find.text('DADOS DO DOCUMENTO'), findsNothing);
      final atual = await fakeRepo.obterPorId('doc-1');
      expect(atual.numeroProcesso, '2026.0001', reason: 'nada foi digitado que persistisse — descartar não escreve');
    });
  });
}
