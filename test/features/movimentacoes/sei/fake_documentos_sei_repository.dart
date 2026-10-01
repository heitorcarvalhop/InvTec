import 'dart:async';

import 'package:invtec/core/utils/text_normalization.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_erros.dart';
import 'package:invtec/features/movimentacoes/sei/domain/documentos_sei_repository.dart';
import 'package:invtec/features/movimentacoes/sei/domain/documentos_sei_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_item_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_conclusao_lote_resultado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_situacao.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_evento_documento.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

import '../../patrimonios/fake_patrimonio_repository.dart';

/// Fake em memória de [DocumentosSeiRepository] (PROMPT 11.3) — reproduz as
/// MESMAS regras que a migration proposta implementaria no banco (versão
/// otimista, bloqueio de edição após a primeira conclusão, transições de
/// status), para testar controllers/telas isolados do Supabase real. Nenhum
/// método aqui, em nenhuma circunstância, cria uma `Movimentacao` nem toca
/// `FakeMovimentacaoRepository` — as duas pendências (documento SEI x
/// movimentação efetiva) são persistências deliberadamente independentes
/// (nenhuma linha em `movimentacoes`/`FakeMovimentacaoRepository` é criada
/// aqui, igual à RPC real: `registrar_movimentacao` faz os dois na MESMA
/// transação, mas a listagem de movimentações é testada à parte).
///
/// PROMPT 11.5.9.2 — isso NÃO significa que o CADASTRO ATUAL do patrimônio
/// (setor/localização/responsável) fica intocado: a RPC real
/// (`registrar_movimentacao`, chamada por `concluir_item_documento_sei`)
/// atualiza `public.patrimonios` na MESMA transação (ver
/// `supabase/migrations/20260914140000_add_localizacoes.sql`, branch
/// `TRANSFERENCIA` do `case p_tipo`) — só a listagem de movimentações
/// (`FakeMovimentacaoRepository`) é que fica de fora, por ser uma
/// funcionalidade testada isoladamente. Quando [patrimonioRepository] é
/// informado, [concluirItem] (chamado também por [concluirItensLote], uma
/// vez por item) sincroniza o cadastro do patrimônio fictício com a MESMA
/// fórmula da RPC real — ver [_sincronizarPatrimonioAposConclusao].
/// Parâmetro OPCIONAL (`null` por padrão): nenhum teste existente que não
/// precisa dessa sincronização é afetado.
class FakeDocumentosSeiRepository implements DocumentosSeiRepository {
  FakeDocumentosSeiRepository({
    this.autorId = 'user-1',
    this.autorNome = 'Usuária de Teste',
    // PROMPT 11.3.5.3 — permite pré-popular documentos já montados à mão
    // (ex.: com setor/sigla resolvidos, como um embed real devolveria),
    // para testar widgets que só leem (`obterPorId`/`listar`) sem precisar
    // passar pelo fluxo completo de criação deste fake.
    List<SeiDocumentoPendente> documentosIniciais = const [],
    // PROMPT 11.5.9.2 — opcional: quando informado, toda conclusão bem
    // sucedida (individual ou, via `concluirItensLote`, em lote) também
    // atualiza o cadastro do patrimônio fictício correspondente neste
    // repositório — ver o comentário de classe.
    this.patrimonioRepository,
  }) {
    for (final documento in documentosIniciais) {
      _documentos[documento.id] = documento;
    }
  }

  final String autorId;
  final FakePatrimonioRepository? patrimonioRepository;
  final String autorNome;

  final Map<String, SeiDocumentoPendente> _documentos = {};
  final Map<String, List<SeiEventoDocumento>> _eventos = {};
  int _proximoIdDocumento = 1;
  int _proximoIdItem = 1;
  int _proximoIdEvento = 1;

  int criarCallCount = 0;
  int editarCallCount = 0;
  int cancelarItemCallCount = 0;
  int cancelarPendentesCallCount = 0;

  /// PROMPT 11.4.3 — conclusão de entrega SIMULADA em memória (espelha as
  /// regras de `concluir_item_documento_sei`, sem nenhum Supabase e sem criar
  /// movimentação real). [concluirCallCount] conta as chamadas (prova do
  /// clique duplo); [conclusoes] guarda os parâmetros de cada uma;
  /// [falhaNaConclusao] é lançada ANTES de qualquer alteração (a RPC recusou);
  /// [aguardarConclusao] segura a chamada até ser completado (para testar o
  /// estado de carregamento / clique duplo).
  int concluirCallCount = 0;
  final List<Map<String, Object?>> conclusoes = [];
  Object? falhaNaConclusao;
  Completer<void>? aguardarConclusao;
  int _proximoIdMovimentacao = 1;
  final Map<String, Movimentacao> _movimentacoesPorItem = {};

  /// PROMPT 11.5.5 — conclusão em LOTE simulada em memória. Reaproveita
  /// [concluirItem] internamente, uma vez por item (o MESMO simulacro do que
  /// a RPC real faz no servidor, dentro de uma única transação) — isto NÃO é
  /// o laço client-side proibido pelo PROMPT 11.5.5 (que se aplica só a
  /// `DocumentosSeiRepositorySupabase`, onde o Flutter faria uma chamada de
  /// rede por item; aqui é só a simulação do que o SERVIDOR faz numa única
  /// chamada). [concluirLoteCallCount] conta as chamadas a este método;
  /// [conclusoesLote] guarda os parâmetros de cada uma, para os testes
  /// provarem que os seis chegam intactos.
  ///
  /// A simulação de idempotência (mesmo `loteId` + mesmos 6 campos de
  /// identidade → devolve o resultado registrado, sem escrever nada) segue a
  /// MESMA regra da RPC real (comparação campo a campo, `lote_id` como
  /// chave), mas continua sendo só um dublê de teste — não substitui a
  /// homologação transacional real feita em `supabase/homolog/11_5_3_*`
  /// contra o PostgreSQL de verdade.
  int concluirLoteCallCount = 0;
  final List<Map<String, Object?>> conclusoesLote = [];
  final Map<String, _LoteFake> _lotes = {};

  /// PROMPT 11.5.6/11.5.6.1 — reconciliação: espelha a leitura direta
  /// (SELECT, nunca RPC) de `documentos_sei_lotes_conclusao` por `lote_id`,
  /// COM a validação de identidade completa (nunca só o `loteId`). `null`
  /// quando nada foi registrado para este `loteId` (a tentativa REALMENTE
  /// não foi aplicada). [buscarLotePorIdCallCount] conta as chamadas.
  int buscarLotePorIdCallCount = 0;

  /// SÓ PARA TESTE — lançada no INÍCIO de [buscarLotePorId], antes de
  /// qualquer comparação: simula a própria CONSULTA de reconciliação
  /// falhando (rede/permissão) — nunca "registro não encontrado".
  Object? falhaAoBuscarLote;

  /// SÓ PARA TESTE — quando definido, [buscarLotePorId] compara
  /// `criado_por` contra ESTE valor em vez de [autorId]: simula a sessão
  /// ATUAL (no momento da reconciliação) ser diferente de quem criou o
  /// registro originalmente (via [concluirItensLote], que sempre grava
  /// `criado_por: autorId`) — o mesmo efeito que `_client.auth.currentUser`
  /// mudar entre as duas chamadas na implementação real.
  String? usuarioAtualParaTeste;

  /// PROMPT 11.3.11 — injeção de falhas SÓ PARA TESTE das escritas de
  /// cancelamento (nenhum acesso ao banco). [falhaNaEscrita] é lançada ANTES
  /// de qualquer alteração (a RPC recusou: nada muda);
  /// [falharRecargaAposEscrita] aplica a escrita e DEPOIS lança
  /// `SeiEscritaConcluidaRecargaFalhouException` (a RPC funcionou, a
  /// releitura falhou).
  Object? falhaNaEscrita;
  bool falharRecargaAposEscrita = false;

  /// SÓ PARA TESTE (PROMPT 11.3, seção 19): esta versão do app não
  /// implementa a conclusão real de um item (depende de uma RPC futura,
  /// seção 15/21.6) — este método simula o efeito que essa conclusão teria
  /// no banco (status CONCLUIDO + `movimentacaoId` vinculado + versão do
  /// documento incrementada + evento ITEM_CONCLUIDO), para permitir testar
  /// a regra "documento com item concluído fica bloqueado para edição"
  /// (seção 8) sem depender de código de produção ainda não escrito.
  /// Nenhum código do app chama isto.
  SeiDocumentoPendente marcarItemConcluidoParaTeste(String itemId, {required String movimentacaoId}) {
    final entrada = _documentos.values
        .expand((d) => d.itens.map((i) => (d, i)))
        .firstWhere((par) => par.$2.id == itemId, orElse: () => throw Exception('Item $itemId não encontrado'));
    final documento = entrada.$1;
    final itemConcluido = entrada.$2.copyWith(
      status: SeiItemPendenciaStatus.concluido,
      movimentacaoId: () => movimentacaoId,
    );
    final novoDocumento = documento.copyWith(
      versao: documento.versao + 1,
      itens: [
        for (final i in documento.itens)
          if (i.id == itemId) itemConcluido else i,
      ],
    );
    _documentos[documento.id] = novoDocumento;
    _registrarEvento(
      documentoId: documento.id,
      itemId: itemId,
      tipo: SeiTipoEventoDocumento.itemConcluido,
      descricao: 'Conclusão simulada em teste — movimentação $movimentacaoId',
    );
    return novoDocumento;
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
  }) async {
    var lista = _documentos.values.toList()..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

    if (tipo != null) {
      lista = lista.where((d) => d.tipoOperacaoPretendida == tipo).toList();
    }
    if (numeroDocumentoSei != null && numeroDocumentoSei.trim().isNotEmpty) {
      final termo = numeroDocumentoSei.trim().toLowerCase();
      lista = lista.where((d) => (d.numeroDocumentoSei ?? '').toLowerCase().contains(termo)).toList();
    }
    if (numeroProcesso != null && numeroProcesso.trim().isNotEmpty) {
      final termo = numeroProcesso.trim().toLowerCase();
      lista = lista.where((d) => (d.numeroProcesso ?? '').toLowerCase().contains(termo)).toList();
    }
    if (numeroPatrimonio != null && numeroPatrimonio.trim().isNotEmpty) {
      final termo = numeroPatrimonio.trim().toLowerCase();
      lista = lista.where((d) => d.itens.any((i) => (i.patrimonioNumero ?? '').toLowerCase().contains(termo))).toList();
    }
    if (situacaoContemStatus != null) {
      lista = lista
          .where(
            (d) => switch (situacaoContemStatus) {
              SeiItemPendenciaStatus.pendente => d.totalPendentes > 0,
              SeiItemPendenciaStatus.concluido => d.totalConcluidos > 0,
              SeiItemPendenciaStatus.cancelado => d.totalCancelados > 0,
            },
          )
          .toList();
    }

    final total = lista.length;
    final pagina = lista.skip(offset).take(limit).toList();
    return DocumentosSeiResultado(itens: pagina, total: total);
  }

  @override
  Future<SeiDocumentoPendente> obterPorId(String documentoId) async {
    final doc = _documentos[documentoId];
    if (doc == null) throw Exception('Documento SEI pendente $documentoId não encontrado');
    return doc;
  }

  @override
  Future<List<SeiEventoDocumento>> listarEventos(String documentoId) async {
    return List.unmodifiable((_eventos[documentoId] ?? const []).reversed);
  }

  @override
  Future<List<SeiDocumentoPendente>> buscarPossivelDuplicata({
    required String numeroDocumentoSei,
    String? numeroProcesso,
  }) async {
    return _documentos.values
        .where((d) => d.numeroDocumentoSei == numeroDocumentoSei)
        .where((d) => numeroProcesso == null || numeroProcesso.trim().isEmpty || d.numeroProcesso == numeroProcesso)
        .toList();
  }

  @override
  Future<SeiDocumentoPendente> salvarRascunho(
    SeiDocumentoPendenteRascunho rascunho, {
    bool confirmarDuplicata = false,
  }) async {
    // PROMPT 11.3.1, seção 8 — mesma checagem feita por
    // `criar_documento_sei_pendente` no banco: um documento ATIVO (nenhum
    // item cancelado sozinho não conta) com o mesmo número já existente
    // bloqueia a criação, a menos que o chamador confirme explicitamente.
    //
    // PROMPT 11.3.3, seção 3 — auditoria encontrou: a comparação de
    // processo era assimétrica — exigia `d.numeroProcesso ==
    // rascunho.numeroProcesso` sempre que ESTE rascunho tinha processo
    // informado, mesmo quando o documento existente `d` não tinha processo
    // nenhum (null). Isso deixava passar sem aviso o par "documento A sem
    // processo, depois documento B com processo, mesmo número SEI".
    // Corrigido para SIMÉTRICO: considera o mesmo documento quando QUALQUER
    // um dos dois lados não tem processo informado, ou quando os dois
    // processos batem — mesma regra agora usada em
    // `criar_documento_sei_pendente` no SQL.
    final numero = rascunho.numeroDocumentoSei;
    if (!confirmarDuplicata && numero != null && numero.trim().isNotEmpty) {
      final jaExisteAtivo = _documentos.values.any(
        (d) =>
            d.numeroDocumentoSei == numero &&
            (rascunho.numeroProcesso == null ||
                d.numeroProcesso == null ||
                d.numeroProcesso == rascunho.numeroProcesso) &&
            d.situacao != SeiDocumentoSituacao.cancelado,
      );
      if (jaExisteAtivo) throw const SeiDocumentoDuplicadoException();
    }

    criarCallCount++;
    final documentoId = 'doc-${_proximoIdDocumento++}';
    final agora = DateTime.now();

    final itens = [
      for (final item in rascunho.itens)
        SeiItemPendente(
          id: 'item-${_proximoIdItem++}',
          documentoId: documentoId,
          linha: item.linha,
          patrimonioId: item.patrimonioId,
          numeroPatrimonio: SeiValorCorrigivel(original: item.numeroPatrimonioOriginal),
          origemTexto: SeiValorCorrigivel(original: item.origemTextoOriginal),
          origemSetorId: item.origemSetorId,
          destinoTexto: SeiValorCorrigivel(original: item.destinoTextoOriginal),
          destinoSetorId: item.destinoSetorId,
          numeroChamado: SeiValorCorrigivel(original: item.numeroChamadoOriginal),
          equipamentoTexto: SeiValorCorrigivel(original: item.equipamentoTextoOriginal),
          localizacaoDestinoId: item.localizacaoDestinoId,
          localizacaoDestinoNome: item.localizacaoDestinoNome,
          decisaoLocalizacao: item.decisaoLocalizacao,
          responsavelDestino: item.responsavelDestino,
          decisaoResponsavel: item.decisaoResponsavel,
          status: SeiItemPendenciaStatus.pendente,
          criadoEm: agora,
        ),
    ];

    final documento = SeiDocumentoPendente.fromItens(
      id: documentoId,
      numeroDocumentoSei: rascunho.numeroDocumentoSei,
      numeroProcesso: rascunho.numeroProcesso,
      numeroDocumentoFormatado: rascunho.numeroDocumentoFormatado,
      assunto: rascunho.assunto,
      tipoOperacaoPretendida: rascunho.tipoOperacaoPretendida,
      nomeArquivo: rascunho.nomeArquivo,
      hashSha256: rascunho.hashSha256,
      versao: 1,
      criadoEm: agora,
      criadoPorId: autorId,
      criadoPorNome: autorNome,
      itens: itens,
    );

    _documentos[documentoId] = documento;
    _registrarEvento(
      documentoId: documentoId,
      tipo: SeiTipoEventoDocumento.criacao,
      descricao: 'Documento SEI pendente criado com ${itens.length} item(ns)',
    );
    return documento;
  }

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
    editarCallCount++;
    final atual = _documentos[documentoId];
    if (atual == null) throw Exception('Documento SEI pendente $documentoId não encontrado');

    if (atual.versao != versaoEsperada) {
      throw SeiEdicaoConflitoException(versaoEsperada: versaoEsperada, versaoAtual: atual.versao);
    }

    // PROMPT 11.3.2, seção 3 — auditoria encontrou: gravar um evento
    // 'tentativaBloqueada' aqui era enganoso — o SQL equivalente gravava
    // esse evento imediatamente antes de um `raise exception`, que desfaz
    // a transação inteira (o evento nunca era commitado). O fake agora
    // espelha o comportamento corrigido: nenhuma gravação, só a exceção.
    if (!atual.podeSerEditado) {
      throw SeiDocumentoBloqueadoParaEdicaoException(documentoId);
    }
    // PROMPT 11.3.12 — espelha a proteção PROPOSTA para
    // `editar_documento_sei_pendente` (ainda não aplicada no banco): um
    // documento sem nenhum item PENDENTE está encerrado e não pode mais ser
    // editado.
    if (atual.encerrado) {
      throw SeiDocumentoBloqueadoParaEdicaoException(documentoId);
    }

    // PROMPT 11.3.2, seção 4 — auditoria encontrou: o fake aplicava
    // correções item a item sem checar se o item realmente existia neste
    // documento ou continuava PENDENTE — um item_id de outro documento, ou
    // já cancelado, era simplesmente ignorado (nenhuma correção aplicada,
    // nenhum erro), e a edição ainda "tinha sucesso". Corrigido com uma
    // validação PRÉVIA que rejeita a operação INTEIRA (documento continua
    // com os dados anteriores) se qualquer item do payload for inválido.
    final itensPorId = {for (final item in atual.itens) item.id: item};
    for (final entrada in itensAlterados.entries) {
      if (entrada.value.vazia) continue;
      final item = itensPorId[entrada.key];
      if (item == null) {
        throw SeiItemEdicaoInvalidaException(entrada.key, 'não pertence ao documento $documentoId');
      }
      if (item.status != SeiItemPendenciaStatus.pendente) {
        throw SeiItemEdicaoInvalidaException(entrada.key, 'não está PENDENTE (está ${item.status.value})');
      }
    }

    final agora = DateTime.now();
    final idsAlterados = [
      for (final entrada in itensAlterados.entries)
        if (!entrada.value.vazia) entrada.key,
    ];
    // PROMPT 11.3.8 — retrato ANTES da correção, no mesmo formato bruto que
    // a RPC real grava (`to_jsonb(i.*)`), para o histórico de alterações
    // poder ser testado com dados_antes/dados_depois realistas — sem isto,
    // o fake produzia um evento EDICAO sem NENHUM dado estruturado,
    // divergindo do que `editar_documento_sei_pendente` de fato grava.
    final itensAntesJson = [for (final id in idsAlterados) _itemParaJsonBruto(itensPorId[id]!)];
    final dadosAntesDocumento = {
      'numero_documento_sei': atual.numeroDocumentoSei,
      'numero_processo': atual.numeroProcesso,
      'numero_documento_formatado': atual.numeroDocumentoFormatado,
      'assunto': atual.assunto,
    };

    final novosItens = [
      for (final item in atual.itens)
        if (itensAlterados.containsKey(item.id) && !itensAlterados[item.id]!.vazia)
          _aplicarCorrecao(item, itensAlterados[item.id]!, agora)
        else
          item,
    ];

    final editado = atual.copyWith(versao: atual.versao + 1, atualizadoEm: agora, itens: novosItens);
    final documentoEditado = _substituirCamposPrincipais(
      editado,
      numeroDocumentoSei: numeroDocumentoSei,
      numeroProcesso: numeroProcesso,
      numeroDocumentoFormatado: numeroDocumentoFormatado,
      assunto: assunto,
    );
    _documentos[documentoId] = documentoEditado;

    final itensDepoisPorId = {for (final item in documentoEditado.itens) item.id: item};
    final itensDepoisJson = [for (final id in idsAlterados) _itemParaJsonBruto(itensDepoisPorId[id]!)];
    final dadosDepoisDocumento = {
      'numero_documento_sei': documentoEditado.numeroDocumentoSei,
      'numero_processo': documentoEditado.numeroProcesso,
      'numero_documento_formatado': documentoEditado.numeroDocumentoFormatado,
      'assunto': documentoEditado.assunto,
    };

    _registrarEvento(
      documentoId: documentoId,
      tipo: SeiTipoEventoDocumento.edicao,
      descricao: motivo,
      dadosAntes: {'documento': dadosAntesDocumento, 'itens': itensAntesJson},
      dadosDepois: {'documento': dadosDepoisDocumento, 'itens': itensDepoisJson},
    );
    return _documentos[documentoId]!;
  }

  /// Mesmo formato bruto que `to_jsonb(i.*)` produziria para uma linha de
  /// `documentos_sei_itens` — só os campos que o histórico de alterações
  /// (PROMPT 11.3.8) de fato usa (identidade + os editáveis).
  Map<String, Object?> _itemParaJsonBruto(SeiItemPendente item) => {
    'id': item.id,
    'linha': item.linha,
    'numero_patrimonio_original': item.numeroPatrimonio.original,
    'numero_patrimonio_corrigido': item.numeroPatrimonio.corrigido,
    'destino_texto_original': item.destinoTexto.original,
    'destino_texto_corrigido': item.destinoTexto.corrigido,
    'numero_chamado_original': item.numeroChamado.original,
    'numero_chamado_corrigido': item.numeroChamado.corrigido,
    'equipamento_texto_original': item.equipamentoTexto.original,
    'equipamento_texto_corrigido': item.equipamentoTexto.corrigido,
    'destino_setor_id': item.destinoSetorId,
    'localizacao_destino_id': item.localizacaoDestinoId,
    'decisao_localizacao': item.decisaoLocalizacao.value,
    'responsavel_destino': item.responsavelDestino,
    'decisao_responsavel': item.decisaoResponsavel.value,
  };

  @override
  Future<SeiDocumentoPendente> cancelarItem({required String itemId, required String motivo}) async {
    cancelarItemCallCount++;
    final falhaInjetada = falhaNaEscrita;
    if (falhaInjetada != null) throw falhaInjetada;
    final entrada = _documentos.values
        .expand((d) => d.itens.map((i) => (d, i)))
        .firstWhere((par) => par.$2.id == itemId, orElse: () => throw Exception('Item $itemId não encontrado'));
    final documento = entrada.$1;
    final item = entrada.$2;

    if (item.status != SeiItemPendenciaStatus.pendente) {
      throw SeiItemNaoElegivelException(itemId, item.status.value);
    }

    final itemCancelado = item.copyWith(status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: () => motivo);
    final novoDocumento = documento.copyWith(
      versao: documento.versao + 1,
      itens: [
        for (final i in documento.itens)
          if (i.id == itemId) itemCancelado else i,
      ],
    );
    _documentos[documento.id] = novoDocumento;

    _registrarEvento(
      documentoId: documento.id,
      itemId: itemId,
      tipo: SeiTipoEventoDocumento.itemCancelado,
      descricao: motivo,
    );
    if (falharRecargaAposEscrita) {
      throw SeiEscritaConcluidaRecargaFalhouException(
        operacao: 'cancelar_item_sei_pendente',
        documentoId: documento.id,
      );
    }
    return novoDocumento;
  }

  @override
  Future<SeiDocumentoPendente> cancelarPendentesDoDocumento({
    required String documentoId,
    required String motivo,
  }) async {
    cancelarPendentesCallCount++;
    final falhaInjetada = falhaNaEscrita;
    if (falhaInjetada != null) throw falhaInjetada;
    final atual = _documentos[documentoId];
    if (atual == null) throw Exception('Documento SEI pendente $documentoId não encontrado');

    final qtdPendentes = atual.totalPendentes;
    final novosItens = [
      for (final item in atual.itens)
        if (item.status == SeiItemPendenciaStatus.pendente)
          item.copyWith(status: SeiItemPendenciaStatus.cancelado, motivoCancelamento: () => motivo)
        else
          item,
    ];

    final novoDocumento = qtdPendentes == 0 ? atual : atual.copyWith(versao: atual.versao + 1, itens: novosItens);
    _documentos[documentoId] = novoDocumento;

    if (qtdPendentes > 0) {
      _registrarEvento(
        documentoId: documentoId,
        tipo: SeiTipoEventoDocumento.documentoCancelado,
        descricao: '$qtdPendentes item(ns) pendente(s) cancelado(s): $motivo',
      );
    }
    if (falharRecargaAposEscrita) {
      throw SeiEscritaConcluidaRecargaFalhouException(
        operacao: 'cancelar_pendentes_documento_sei',
        documentoId: documentoId,
      );
    }
    return novoDocumento;
  }

  @override
  Future<SeiConclusaoItemResultado> concluirItem({
    required String documentoId,
    required String itemId,
    required int versaoEsperada,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  }) async {
    concluirCallCount++;
    conclusoes.add({
      'documentoId': documentoId,
      'itemId': itemId,
      'versaoEsperada': versaoEsperada,
      'observacao': observacao,
      'confirmarLimpezaDestino': confirmarLimpezaDestino,
    });
    final espera = aguardarConclusao;
    if (espera != null) await espera.future;
    final falhaInjetada = falhaNaConclusao;
    if (falhaInjetada != null) throw falhaInjetada;

    final documento = _documentos[documentoId];
    if (documento == null) {
      throw falhaDeConclusaoSei(
        codigo: 'P0002',
        mensagemDoServidor: 'Documento SEI pendente $documentoId não encontrado',
      );
    }
    final item = documento.itens.where((i) => i.id == itemId).firstOrNull;
    if (item == null) {
      throw falhaDeConclusaoSei(codigo: 'P0002', mensagemDoServidor: 'Item $itemId não encontrado');
    }

    // Idempotência: item já concluído devolve o estado existente (sem nova
    // movimentação, sem checar a versão).
    if (item.status == SeiItemPendenciaStatus.concluido && item.movimentacaoId != null) {
      final existente = _movimentacoesPorItem[itemId] ?? _movimentacaoDoItem(item, id: item.movimentacaoId!);
      return SeiConclusaoItemResultado(
        jaConcluido: true,
        documentoId: documentoId,
        documentoVersao: documento.versao,
        item: item,
        movimentacao: existente,
      );
    }
    if (item.status != SeiItemPendenciaStatus.pendente) {
      throw falhaDeConclusaoSei(
        codigo: 'P0001',
        mensagemDoServidor: 'Item $itemId não está PENDENTE (está ${item.status.value}) — não pode ser concluído',
      );
    }
    if (documento.versao != versaoEsperada) {
      throw falhaDeConclusaoSei(
        codigo: 'P0010',
        mensagemDoServidor:
            'Conflito de edição: versão $versaoEsperada informada, versão atual ${documento.versao} — releia o documento',
      );
    }

    final movimentacao = _movimentacaoDoItem(item, id: 'mov-${_proximoIdMovimentacao++}', observacao: observacao);
    _movimentacoesPorItem[itemId] = movimentacao;
    final itemConcluido = item.copyWith(
      status: SeiItemPendenciaStatus.concluido,
      movimentacaoId: () => movimentacao.id,
    );
    final novoDocumento = documento.copyWith(
      versao: documento.versao + 1,
      itens: [
        for (final i in documento.itens)
          if (i.id == itemId) itemConcluido else i,
      ],
    );
    _documentos[documentoId] = novoDocumento;

    // Mesmo formato do evento gravado por `concluir_item_documento_sei`.
    _registrarEvento(
      documentoId: documentoId,
      itemId: itemId,
      tipo: SeiTipoEventoDocumento.itemConcluido,
      descricao:
          'Entrega concluída: patrimônio ${item.numeroPatrimonio.valorEfetivo} transferido '
          '(movimentação ${movimentacao.id})${observacao != null && observacao.trim().isNotEmpty ? ' — ${observacao.trim()}' : ''}',
      dadosAntes: {
        'item': _itemParaJsonBruto(item),
        'patrimonio': {'setor_atual_id': item.origemSetorId},
      },
      dadosDepois: {
        'movimentacao_id': movimentacao.id,
        'numero_patrimonio_efetivo': item.numeroPatrimonio.valorEfetivo,
        'limpeza_confirmada': confirmarLimpezaDestino,
        'item': {'status': 'CONCLUIDO', 'movimentacao_id': movimentacao.id},
        'movimentacao': {
          'tipo': 'TRANSFERENCIA',
          'origem_id': item.origemSetorId,
          'destino_id': item.destinoSetorId,
          'localizacao_destino_id': item.localizacaoDestinoId,
          'responsavel_destino': item.responsavelDestino,
        },
      },
    );

    await _sincronizarPatrimonioAposConclusao(item);

    return SeiConclusaoItemResultado(
      jaConcluido: false,
      documentoId: documentoId,
      documentoVersao: novoDocumento.versao,
      item: itemConcluido,
      movimentacao: movimentacao,
    );
  }

  /// PROMPT 11.5.9.2 — sem efeito quando [patrimonioRepository] não foi
  /// informado, ou quando [item] não tem `patrimonioId`/ainda não existe
  /// nesse fake de patrimônios (mesma tolerância — nunca lança: uma
  /// conclusão SEI em teste não precisa necessariamente de um patrimônio
  /// fictício totalmente montado). Espelha EXATAMENTE a fórmula da RPC real
  /// para `TRANSFERENCIA` (`registrar_movimentacao`, migration
  /// `20260914140000_add_localizacoes.sql`, branch `TRANSFERENCIA` do
  /// `case p_tipo`, com os parâmetros calculados por
  /// `concluir_item_documento_sei`, migration
  /// `20260925140000_add_concluir_item_documento_sei.sql`, seção 18):
  ///  * `setor_atual_id` := `item.destinoSetorId` (sempre — é uma
  ///    transferência);
  ///  * `localizacao_atual_id` := `item.localizacaoDestinoId` quando
  ///    `decisaoLocalizacao == DEFINIDO`, senão `null` (limpa —
  ///    CONFIRMADO_SEM_INFORMACAO grava null DE PROPÓSITO, exatamente como
  ///    a RPC real);
  ///  * `responsavel_atual` := `item.responsavelDestino` quando
  ///    `decisaoResponsavel == DEFINIDO` (com texto não vazio), senão
  ///    `null`;
  ///  * `status` := `DISPONIVEL` quando o novo responsável ficou `null`,
  ///    senão `EM_USO` — mesma regra do `v_novo_status` da RPC real.
  /// Nenhuma regra de negócio nova: só a mesma fórmula já usada por
  /// `planejarConclusaoEntrega`/`concluir_item_documento_sei`, replicada
  /// aqui para o cadastro fictício acompanhar a conclusão, como a RPC real
  /// faz na mesma transação.
  Future<void> _sincronizarPatrimonioAposConclusao(SeiItemPendente item) async {
    final repoPatrimonios = patrimonioRepository;
    final patrimonioId = item.patrimonioId;
    if (repoPatrimonios == null || patrimonioId == null) return;

    final atual = await repoPatrimonios.buscarDetalhePorId(patrimonioId);
    if (atual == null) return;

    final novoResponsavel = item.decisaoResponsavel == SeiDecisaoCampo.definido
        ? (item.responsavelDestino?.trim().isNotEmpty ?? false ? item.responsavelDestino!.trim() : null)
        : null;
    final novaLocalizacaoId = item.decisaoLocalizacao == SeiDecisaoCampo.definido ? item.localizacaoDestinoId : null;

    final patrimonioAtualizado = Patrimonio(
      id: atual.patrimonio.id,
      numeroPatrimonio: atual.patrimonio.numeroPatrimonio,
      numeroSerie: atual.patrimonio.numeroSerie,
      tipoId: atual.patrimonio.tipoId,
      marca: atual.patrimonio.marca,
      modelo: atual.patrimonio.modelo,
      descricao: atual.patrimonio.descricao,
      observacao: atual.patrimonio.observacao,
      status: novoResponsavel == null ? PatrimonioStatus.disponivel : PatrimonioStatus.emUso,
      setorAtualId: item.destinoSetorId ?? atual.patrimonio.setorAtualId,
      localizacaoAtualId: novaLocalizacaoId,
      responsavelAtual: novoResponsavel,
      dataAquisicao: atual.patrimonio.dataAquisicao,
      dataCadastro: atual.patrimonio.dataCadastro,
      criadoPor: atual.patrimonio.criadoPor,
      atualizadoEm: DateTime.now(),
    );

    repoPatrimonios.substituirDetalhe(
      PatrimonioDetalhe(
        patrimonio: patrimonioAtualizado,
        tipoNome: atual.tipoNome,
        // Nomes de exibição resolvidos a partir do próprio item SEI (o
        // fake de patrimônios não tem uma tabela de setores/localizações
        // para "ressolver" por id) — mesma informação que o app real
        // mostraria após reler o patrimônio (embed de `setores`).
        setorNome: item.destinoSetorNome ?? atual.setorNome,
        setorSigla: atual.setorSigla,
        localizacaoNome: novaLocalizacaoId == null ? null : (item.localizacaoDestinoNome ?? atual.localizacaoNome),
        criadoPorNome: atual.criadoPorNome,
      ),
    );
  }

  @override
  Future<SeiConclusaoLoteResultado> concluirItensLote({
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    required String loteId,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  }) async {
    concluirLoteCallCount++;
    conclusoesLote.add({
      'documentoId': documentoId,
      'itemIds': itemIds,
      'versaoEsperada': versaoEsperada,
      'loteId': loteId,
      'observacao': observacao,
      'confirmarLimpezaDestino': confirmarLimpezaDestino,
    });
    final espera = aguardarConclusao;
    if (espera != null) await espera.future;
    final falhaInjetada = falhaNaConclusao;
    if (falhaInjetada != null) throw falhaInjetada;

    if (itemIds.isEmpty) {
      throw falhaDeConclusaoSei(
        codigo: 'P0001',
        mensagemDoServidor: 'p_item_ids não pode ser vazio',
        operacao: operacaoConcluirItensSeiLote,
      );
    }
    if (itemIds.length > 200) {
      throw falhaDeConclusaoSei(
        codigo: 'P0001',
        mensagemDoServidor: 'O lote excede o limite de 200 itens (recebeu ${itemIds.length})',
        operacao: operacaoConcluirItensSeiLote,
      );
    }
    // Canonicaliza (distinto + ordenado) e recusa duplicata explícita —
    // mesma regra da RPC real: nunca deduplica silenciosamente.
    final canonico = itemIds.toSet().toList()..sort();
    if (canonico.length != itemIds.length) {
      throw falhaDeConclusaoSei(
        codigo: 'P0001',
        mensagemDoServidor: 'p_item_ids não pode conter o mesmo item repetido',
        operacao: operacaoConcluirItensSeiLote,
      );
    }

    // Observação normalizada é o que entra na comparação de retry — mesma
    // regra de `public.normalize_text` aplicada pela RPC real (aparar +
    // ""/só-espaço vira null).
    final observacaoNormalizada = nullIfBlank(observacao);

    final loteExistente = _lotes[loteId];
    if (loteExistente != null) {
      final identico =
          loteExistente.documentoId == documentoId &&
          _mesmaListaDeIds(loteExistente.itemIds, canonico) &&
          loteExistente.versaoEsperada == versaoEsperada &&
          loteExistente.observacao == observacaoNormalizada &&
          loteExistente.confirmarLimpezaDestino == confirmarLimpezaDestino &&
          loteExistente.criadoPor == autorId;
      if (identico) {
        // RETRY IDÊNTICO: devolve o resultado já registrado, com
        // `jaExecutado` sobrescrito para `true` — mesmo comportamento da RPC
        // real (`v_lote.resultado || jsonb_build_object('ja_executado',
        // true)`). Nenhuma nova conclusão, nenhuma nova movimentação,
        // nenhum novo evento.
        final registrado = loteExistente.resultado;
        return SeiConclusaoLoteResultado(
          jaExecutado: true,
          documentoId: registrado.documentoId,
          documentoVersao: registrado.documentoVersao,
          itens: registrado.itens,
        );
      }
      throw falhaDeConclusaoSei(
        codigo: 'P0037',
        mensagemDoServidor:
            'lote_id $loteId já foi usado para uma operação com parâmetros diferentes '
            '(documento, itens, versão esperada, observação, confirmação de limpeza ou usuário)',
        operacao: operacaoConcluirItensSeiLote,
      );
    }

    final documento = _documentos[documentoId];
    if (documento == null) {
      throw falhaDeConclusaoSei(
        codigo: 'P0002',
        mensagemDoServidor: 'Documento SEI pendente $documentoId não encontrado',
        operacao: operacaoConcluirItensSeiLote,
      );
    }

    final itensPorId = {for (final item in documento.itens) item.id: item};
    final naoEncontrados = canonico.where((id) => !itensPorId.containsKey(id)).toList();
    if (naoEncontrados.isNotEmpty) {
      throw falhaDeConclusaoSei(
        codigo: 'P0002',
        mensagemDoServidor: 'Um ou mais itens do lote não existem ou não pertencem ao documento $documentoId',
        operacao: operacaoConcluirItensSeiLote,
      );
    }

    final naoPendentes = canonico.where((id) => itensPorId[id]!.status != SeiItemPendenciaStatus.pendente).toList();
    if (naoPendentes.isNotEmpty) {
      throw falhaDeConclusaoSei(
        codigo: 'P0036',
        mensagemDoServidor: 'Um ou mais itens do lote não estão PENDENTE: ${naoPendentes.join(', ')}',
        operacao: operacaoConcluirItensSeiLote,
      );
    }

    final patrimoniosVistos = <String>{};
    for (final id in canonico) {
      final patrimonioId = itensPorId[id]!.patrimonioId;
      if (patrimonioId != null && !patrimoniosVistos.add(patrimonioId)) {
        throw falhaDeConclusaoSei(
          codigo: 'P0001',
          mensagemDoServidor: 'Dois ou mais itens deste lote apontam para o mesmo patrimônio',
          operacao: operacaoConcluirItensSeiLote,
        );
      }
    }

    if (documento.versao != versaoEsperada) {
      throw falhaDeConclusaoSei(
        codigo: 'P0010',
        mensagemDoServidor:
            'Conflito de edição: versão $versaoEsperada informada, versão atual ${documento.versao} — releia o documento',
        operacao: operacaoConcluirItensSeiLote,
      );
    }

    // Mesma ordem de processamento da RPC real: por patrimônio, depois por
    // id — não pela ordem recebida do cliente.
    final ordenados = [...canonico]
      ..sort((a, b) {
        final pa = itensPorId[a]!.patrimonioId ?? '';
        final pb = itensPorId[b]!.patrimonioId ?? '';
        final cmp = pa.compareTo(pb);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

    var versaoAtual = versaoEsperada;
    final itensResultado = <SeiConclusaoLoteItemResultado>[];
    for (final itemId in ordenados) {
      // Reaproveita a MESMA simulação de `concluir_item_documento_sei`
      // (nenhuma regra duplicada aqui) — qualquer exceção lançada por
      // `concluirItem` propaga sem alteração, encerrando o lote inteiro
      // (nenhum registro parcial fica em `_lotes`).
      final resultadoItem = await concluirItem(
        documentoId: documentoId,
        itemId: itemId,
        versaoEsperada: versaoAtual,
        observacao: observacao,
        confirmarLimpezaDestino: confirmarLimpezaDestino,
      );
      versaoAtual = resultadoItem.documentoVersao;
      itensResultado.add(SeiConclusaoLoteItemResultado(itemId: itemId, resultado: resultadoItem));
    }

    final resultado = SeiConclusaoLoteResultado(
      jaExecutado: false,
      documentoId: documentoId,
      documentoVersao: versaoAtual,
      itens: itensResultado,
    );

    // Registro do lote SÓ depois que TODOS os itens concluíram — mesmo
    // ponto da RPC real (passo 12): uma tentativa fracassada nunca deixa
    // resíduo aqui.
    _lotes[loteId] = _LoteFake(
      documentoId: documentoId,
      itemIds: canonico,
      versaoEsperada: versaoEsperada,
      observacao: observacaoNormalizada,
      confirmarLimpezaDestino: confirmarLimpezaDestino,
      criadoPor: autorId,
      resultado: resultado,
    );

    return resultado;
  }

  @override
  Future<SeiConclusaoLoteResultado?> buscarLotePorId({
    required String loteId,
    required String documentoId,
    required List<String> itemIds,
    required int versaoEsperada,
    String? observacao,
    required bool confirmarLimpezaDestino,
  }) async {
    buscarLotePorIdCallCount++;
    final falhaInjetada = falhaAoBuscarLote;
    if (falhaInjetada != null) throw falhaInjetada;

    final registrado = _lotes[loteId];
    if (registrado == null) return null;

    // PROMPT 11.5.6.1 — mesma checagem de identidade completa da
    // implementação real: o `loteId` bater sozinho nunca basta.
    final itemIdsEsperados = {...itemIds}.toList()..sort();
    final observacaoEsperadaNormalizada = nullIfBlank(observacao);
    final identico =
        registrado.documentoId == documentoId &&
        _mesmaListaDeIds(registrado.itemIds, itemIdsEsperados) &&
        registrado.versaoEsperada == versaoEsperada &&
        registrado.observacao == observacaoEsperadaNormalizada &&
        registrado.confirmarLimpezaDestino == confirmarLimpezaDestino &&
        registrado.criadoPor == (usuarioAtualParaTeste ?? autorId);

    if (!identico) {
      throw SeiReconciliacaoDivergenteException(
        loteId,
        'o registro encontrado para este lote_id tem parâmetros diferentes dos que esta decisão enviaria '
        '(documento, itens, versão esperada, observação, confirmação de limpeza ou usuário responsável) — '
        'nunca aceito como resultado desta operação.',
      );
    }

    return registrado.resultado;
  }

  Movimentacao _movimentacaoDoItem(SeiItemPendente item, {required String id, String? observacao}) {
    final agora = DateTime.now();
    return Movimentacao(
      id: id,
      patrimonioId: item.patrimonioId ?? 'patrimonio-desconhecido',
      tipo: MovimentacaoTipo.transferencia,
      origemId: item.origemSetorId,
      destinoId: item.destinoSetorId,
      localizacaoDestinoId: item.localizacaoDestinoId,
      responsavelDestino: item.responsavelDestino,
      observacao: observacao,
      numeroChamado: item.numeroChamado.valorEfetivo,
      dataMovimentacao: agora,
      criadoEm: agora,
    );
  }

  SeiItemPendente _aplicarCorrecao(SeiItemPendente item, SeiItemPendenteEdicao edicao, DateTime agora) {
    return item.copyWith(
      numeroPatrimonio: edicao.numeroPatrimonioCorrigido == null
          ? item.numeroPatrimonio
          : item.numeroPatrimonio.corrigir(
              novoValor: edicao.numeroPatrimonioCorrigido!,
              corrigidoPorId: autorId,
              corrigidoPorNome: autorNome,
              corrigidoEm: agora,
              motivo: 'Correção manual',
            ),
      destinoTexto: edicao.destinoTextoCorrigido == null
          ? item.destinoTexto
          : item.destinoTexto.corrigir(
              novoValor: edicao.destinoTextoCorrigido!,
              corrigidoPorId: autorId,
              corrigidoPorNome: autorNome,
              corrigidoEm: agora,
              motivo: 'Correção manual',
            ),
      numeroChamado: edicao.numeroChamadoCorrigido == null
          ? item.numeroChamado
          : item.numeroChamado.corrigir(
              novoValor: edicao.numeroChamadoCorrigido!,
              corrigidoPorId: autorId,
              corrigidoPorNome: autorNome,
              corrigidoEm: agora,
              motivo: 'Correção manual',
            ),
      equipamentoTexto: edicao.equipamentoTextoCorrigido == null
          ? item.equipamentoTexto
          : item.equipamentoTexto.corrigir(
              novoValor: edicao.equipamentoTextoCorrigido!,
              corrigidoPorId: autorId,
              corrigidoPorNome: autorNome,
              corrigidoEm: agora,
              motivo: 'Correção manual',
            ),
      destinoSetorId: edicao.destinoSetorId,
      // O fake não tem um "join" real para resolver o nome do novo setor —
      // limpa o nome exibido (fica só com o id) até a próxima releitura.
      destinoSetorNome: edicao.destinoSetorId == null ? null : () => null,
      localizacaoDestinoId: edicao.localizacaoDestinoId,
      localizacaoDestinoNome: edicao.localizacaoDestinoId == null ? null : () => null,
      decisaoLocalizacao: edicao.decisaoLocalizacao,
      responsavelDestino: edicao.responsavelDestino,
      decisaoResponsavel: edicao.decisaoResponsavel,
    );
  }

  SeiDocumentoPendente _substituirCamposPrincipais(
    SeiDocumentoPendente documento, {
    String? Function()? numeroDocumentoSei,
    String? Function()? numeroProcesso,
    String? Function()? numeroDocumentoFormatado,
    String? Function()? assunto,
  }) {
    return SeiDocumentoPendente.fromItens(
      id: documento.id,
      numeroDocumentoSei: numeroDocumentoSei != null ? numeroDocumentoSei() : documento.numeroDocumentoSei,
      numeroProcesso: numeroProcesso != null ? numeroProcesso() : documento.numeroProcesso,
      numeroDocumentoFormatado: numeroDocumentoFormatado != null
          ? numeroDocumentoFormatado()
          : documento.numeroDocumentoFormatado,
      assunto: assunto != null ? assunto() : documento.assunto,
      tipoOperacaoPretendida: documento.tipoOperacaoPretendida,
      nomeArquivo: documento.nomeArquivo,
      hashSha256: documento.hashSha256,
      versao: documento.versao,
      criadoEm: documento.criadoEm,
      criadoPorId: documento.criadoPorId,
      criadoPorNome: documento.criadoPorNome,
      atualizadoEm: documento.atualizadoEm,
      itens: documento.itens,
    );
  }

  void _registrarEvento({
    required String documentoId,
    String? itemId,
    required SeiTipoEventoDocumento tipo,
    required String descricao,
    Map<String, Object?>? dadosAntes,
    Map<String, Object?>? dadosDepois,
  }) {
    final lista = _eventos.putIfAbsent(documentoId, () => []);
    lista.add(
      SeiEventoDocumento(
        id: 'evento-${_proximoIdEvento++}',
        documentoId: documentoId,
        itemId: itemId,
        tipo: tipo,
        descricao: descricao,
        dadosAntes: dadosAntes,
        dadosDepois: dadosDepois,
        autorId: autorId,
        autorNome: autorNome,
        criadoEm: DateTime.now(),
      ),
    );
  }
}

/// PROMPT 11.5.5 — `itemIds` de [FakeDocumentosSeiRepository] já chega
/// CANÔNICO (distinto + ordenado) dos dois lados desta comparação; uma
/// checagem elemento a elemento evita depender de `package:collection`
/// (não é dependência direta deste projeto) só para isto.
bool _mesmaListaDeIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// PROMPT 11.5.5 — os 6 campos de IDENTIDADE de um lote já registrado
/// (mesmo conjunto comparado por `documentos_sei_lotes_conclusao` na RPC
/// real), mais o `resultado` a devolver num retry idêntico.
class _LoteFake {
  const _LoteFake({
    required this.documentoId,
    required this.itemIds,
    required this.versaoEsperada,
    required this.observacao,
    required this.confirmarLimpezaDestino,
    required this.criadoPor,
    required this.resultado,
  });

  final String documentoId;
  final List<String> itemIds;
  final int versaoEsperada;
  final String? observacao;
  final bool confirmarLimpezaDestino;
  final String criadoPor;
  final SeiConclusaoLoteResultado resultado;
}
