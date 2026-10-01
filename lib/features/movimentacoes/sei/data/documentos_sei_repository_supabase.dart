import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/text_normalization.dart';
import '../../domain/movimentacao.dart';
import '../application/sei_conclusao_erros.dart';
import '../domain/documentos_sei_repository.dart';
import '../domain/documentos_sei_resultado.dart';
import '../domain/sei_conclusao_item_resultado.dart';
import '../domain/sei_conclusao_lote_resultado.dart';
import '../domain/sei_documento_pendente.dart';
import '../domain/sei_evento_documento.dart';
import '../domain/sei_item_pendencia_status.dart';
import '../domain/sei_item_pendente.dart';
import '../domain/sei_pendencia_exceptions.dart';

/// colunas + embeds de um documento COM seus itens: consulta
/// única, nunca uma por item (mesmo padrão de `_colunasListagem` em
/// `MovimentacaoRepositorySupabase`).
const _colunasDocumentoComItens =
    'id, numero_documento_sei, numero_processo, numero_documento_formatado, assunto, '
    'tipo_operacao_pretendida, nome_arquivo, hash_sha256, versao, criado_em, criado_por, atualizado_em, '
    'autor:profiles!criado_por(nome), '
    'itens:documentos_sei_itens('
    'id, documento_id, linha, patrimonio_id, '
    'numero_patrimonio_original, numero_patrimonio_corrigido, '
    'origem_texto_original, origem_setor_id, '
    'destino_texto_original, destino_texto_corrigido, destino_setor_id, '
    'numero_chamado_original, numero_chamado_corrigido, '
    'equipamento_texto_original, equipamento_texto_corrigido, '
    'localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel, '
    'status, motivo_cancelamento, movimentacao_id, corrigido_por, corrigido_em, motivo_correcao, '
    'criado_em, atualizado_em, '
    'patrimonio:patrimonios(numero_patrimonio), '
    'origem_setor:setores!origem_setor_id(nome, sigla), '
    'destino_setor:setores!destino_setor_id(nome, sigla), '
    'localizacao_destino:localizacoes!localizacao_destino_id(nome), '
    'corretor:profiles!corrigido_por(nome))';

/// Colunas da view derivada (situação sempre calculada no servidor), sem
/// embed de itens (a listagem não precisa do detalhe de cada item, só dos
/// totais já agregados pela view).
const _colunasListagem =
    'id, numero_documento_sei, numero_processo, numero_documento_formatado, assunto, '
    'tipo_operacao_pretendida, nome_arquivo, hash_sha256, versao, criado_em, criado_por, atualizado_em, '
    'total_itens, total_pendentes, total_concluidos, total_cancelados, situacao, '
    'autor:profiles!criado_por(nome)';

/// mesmo padrão de paginação de
/// `MovimentacaoRepositorySupabase.listarPorNumeroDocumento`: nunca um
/// limite fixo que descarte página.
const _tamanhoPaginaEventos = 500;

class DocumentosSeiRepositorySupabase implements DocumentosSeiRepository {
  DocumentosSeiRepositorySupabase(this._client);

  final SupabaseClient _client;

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
    try {
      var query = _client.from('documentos_sei_com_situacao').select(_colunasListagem);

      if (tipo != null) {
        query = query.eq('tipo_operacao_pretendida', tipo.value);
      }
      final numeroDocumentoTermo = numeroDocumentoSei?.trim();
      if (numeroDocumentoTermo != null && numeroDocumentoTermo.isNotEmpty) {
        query = query.ilike('numero_documento_sei', '%$numeroDocumentoTermo%');
      }
      final numeroProcessoTermo = numeroProcesso?.trim();
      if (numeroProcessoTermo != null && numeroProcessoTermo.isNotEmpty) {
        query = query.ilike('numero_processo', '%$numeroProcessoTermo%');
      }
      final numeroPatrimonioTermo = numeroPatrimonio?.trim();
      if (numeroPatrimonioTermo != null && numeroPatrimonioTermo.isNotEmpty) {
        final documentoIds = await _idsDocumentosPorNumeroPatrimonio(numeroPatrimonioTermo);
        if (documentoIds.isEmpty) {
          return const DocumentosSeiResultado(itens: [], total: 0);
        }
        query = query.inFilter('id', documentoIds);
      }

      final response = await query
          .order('criado_em', ascending: false)
          .range(offset, offset + limit - 1)
          .count(CountOption.exact);

      var itens = response.data.map(SeiDocumentoPendente.fromJson).toList();
      if (situacaoContemStatus != null) {
        // Filtro por "contém item com este status" — não existe coluna
        // direta na view para isso (a view só tem os totais agregados), e
        // fazer isso no servidor exigiria uma segunda consulta por
        // documento; aplicado aqui pós-leitura, sobre a PÁGINA já buscada
        // (nunca sobre o total real — só usado pela UI para reduzir ruído
        // visual, nunca como garantia de completude de busca).
        itens = itens
            .where(
              (d) => switch (situacaoContemStatus) {
                SeiItemPendenciaStatus.pendente => d.totalPendentes > 0,
                SeiItemPendenciaStatus.concluido => d.totalConcluidos > 0,
                SeiItemPendenciaStatus.cancelado => d.totalCancelados > 0,
              },
            )
            .toList();
      }

      return DocumentosSeiResultado(itens: itens, total: response.count);
    } on PostgrestException catch (e) {
      throw AppException('Falha ao listar documentos SEI pendentes', cause: e);
    }
  }

  Future<List<String>> _idsDocumentosPorNumeroPatrimonio(String termo) async {
    final rows = await _client
        .from('documentos_sei_itens')
        .select('documento_id, patrimonio:patrimonios!inner(numero_patrimonio)')
        .ilike('patrimonio.numero_patrimonio', '%$termo%');
    return rows.map((row) => row['documento_id'] as String).toSet().toList();
  }

  @override
  Future<SeiDocumentoPendente> obterPorId(String documentoId) async {
    try {
      final row = await _client.from('documentos_sei').select(_colunasDocumentoComItens).eq('id', documentoId).single();
      return SeiDocumentoPendente.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException('Falha ao carregar o documento SEI pendente', cause: e);
    }
  }

  @override
  Future<List<SeiEventoDocumento>> listarEventos(String documentoId) async {
    try {
      final eventos = <SeiEventoDocumento>[];
      var offset = 0;
      while (true) {
        final response = await _client
            .from('documentos_sei_eventos')
            .select(
              'id, documento_id, item_id, tipo, descricao, dados_antes, dados_depois, autor_id, criado_em, '
              'autor:profiles!autor_id(nome)',
            )
            .eq('documento_id', documentoId)
            .order('criado_em', ascending: false)
            .range(offset, offset + _tamanhoPaginaEventos - 1)
            .count(CountOption.exact);

        eventos.addAll(response.data.map(SeiEventoDocumento.fromJson));
        offset += _tamanhoPaginaEventos;
        if (offset >= response.count || response.data.isEmpty) break;
      }
      return eventos;
    } on PostgrestException catch (e) {
      throw AppException('Falha ao carregar os eventos do documento SEI pendente', cause: e);
    }
  }

  @override
  Future<List<SeiDocumentoPendente>> buscarPossivelDuplicata({
    required String numeroDocumentoSei,
    String? numeroProcesso,
  }) async {
    try {
      var query = _client
          .from('documentos_sei')
          .select(_colunasDocumentoComItens)
          .eq('numero_documento_sei', numeroDocumentoSei);

      final processo = numeroProcesso?.trim();
      if (processo != null && processo.isNotEmpty) {
        query = query.eq('numero_processo', processo);
      }

      final rows = await query.order('criado_em', ascending: false);
      return rows.map(SeiDocumentoPendente.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException('Falha ao checar documentos SEI pendentes já existentes', cause: e);
    }
  }

  @override
  Future<SeiDocumentoPendente> salvarRascunho(
    SeiDocumentoPendenteRascunho rascunho, {
    bool confirmarDuplicata = false,
  }) async {
    try {
      final row = await _client.rpc(
        'criar_documento_sei_pendente',
        params: {
          'p_tipo_operacao_pretendida': rascunho.tipoOperacaoPretendida.value,
          'p_nome_arquivo': rascunho.nomeArquivo,
          'p_hash_sha256': rascunho.hashSha256,
          'p_itens': rascunho.itens.map(_itemRascunhoParaJson).toList(),
          'p_numero_documento_sei': rascunho.numeroDocumentoSei,
          'p_numero_processo': rascunho.numeroProcesso,
          'p_numero_documento_formatado': rascunho.numeroDocumentoFormatado,
          'p_assunto': rascunho.assunto,
          'p_confirmar_duplicata': confirmarDuplicata,
        },
      );
      final id = (row as Map<String, dynamic>)['id'] as String;
      return obterPorId(id);
    } on PostgrestException catch (e) {
      if (e.code == 'P0020') throw const SeiDocumentoDuplicadoException();
      throw AppException(_mapearErro(e), cause: e);
    }
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
    try {
      final alteracoes = <String, Object?>{
        if (numeroDocumentoSei != null) 'numero_documento_sei': numeroDocumentoSei(),
        if (numeroProcesso != null) 'numero_processo': numeroProcesso(),
        if (numeroDocumentoFormatado != null) 'numero_documento_formatado': numeroDocumentoFormatado(),
        if (assunto != null) 'assunto': assunto(),
      };

      final itens = <Map<String, Object?>>[
        for (final entrada in itensAlterados.entries)
          if (!entrada.value.vazia)
            {
              'item_id': entrada.key,
              if (entrada.value.numeroPatrimonioCorrigido != null)
                'numero_patrimonio_corrigido': entrada.value.numeroPatrimonioCorrigido,
              if (entrada.value.destinoTextoCorrigido != null)
                'destino_texto_corrigido': entrada.value.destinoTextoCorrigido,
              if (entrada.value.numeroChamadoCorrigido != null)
                'numero_chamado_corrigido': entrada.value.numeroChamadoCorrigido,
              if (entrada.value.equipamentoTextoCorrigido != null)
                'equipamento_texto_corrigido': entrada.value.equipamentoTextoCorrigido,
              if (entrada.value.destinoSetorId != null) 'destino_setor_id': entrada.value.destinoSetorId!(),
              if (entrada.value.localizacaoDestinoId != null)
                'localizacao_destino_id': entrada.value.localizacaoDestinoId!(),
              if (entrada.value.decisaoLocalizacao != null)
                'decisao_localizacao': entrada.value.decisaoLocalizacao!.value,
              if (entrada.value.responsavelDestino != null) 'responsavel_destino': entrada.value.responsavelDestino!(),
              if (entrada.value.decisaoResponsavel != null)
                'decisao_responsavel': entrada.value.decisaoResponsavel!.value,
            },
      ];

      await _client.rpc(
        'editar_documento_sei_pendente',
        params: {
          'p_documento_id': documentoId,
          'p_versao_esperada': versaoEsperada,
          'p_motivo': motivo,
          'p_alteracoes': alteracoes,
          'p_itens_alterados': itens,
        },
      );
      return obterPorId(documentoId);
    } on PostgrestException catch (e) {
      if (e.code == 'P0010') {
        final atual = await obterPorId(documentoId);
        throw SeiEdicaoConflitoException(versaoEsperada: versaoEsperada, versaoAtual: atual.versao);
      }
      final bloqueio = traduzirBloqueioDeEdicaoSei(e, documentoId);
      if (bloqueio != null) throw bloqueio;
      // A validação prévia de itens em `editar_documento_sei_pendente`
      // (item inexistente, de outro documento, não PENDENTE, id repetido
      // ou ausente) sempre lança P0001/P0002 com a palavra "item" na
      // mensagem — nenhuma outra mensagem desta função contém essa
      // palavra, então é um discriminador seguro. O id do item, quando
      // presente na mensagem, é extraído best-effort só para exibição.
      if ((e.code == 'P0001' || e.code == 'P0002') && e.message.toLowerCase().contains('item')) {
        final idExtraido = RegExp(r'[0-9a-fA-F-]{36}').firstMatch(e.message)?.group(0);
        throw SeiItemEdicaoInvalidaException(idExtraido ?? 'desconhecido', e.message);
      }
      throw AppException(_mapearErro(e), cause: e);
    }
  }

  @override
  Future<SeiDocumentoPendente> cancelarItem({required String itemId, required String motivo}) {
    return executarEscritaSeiComRecarga(
      operacao: 'cancelar_item_sei_pendente',
      escrever: () async {
        try {
          final row = await _client.rpc(
            'cancelar_item_sei_pendente',
            params: {'p_item_id': itemId, 'p_motivo': motivo},
          );
          return (row as Map<String, dynamic>)['documento_id'] as String;
        } on PostgrestException catch (e) {
          if (e.code == 'P0001' && e.message.toLowerCase().contains('não está pendente')) {
            throw SeiItemNaoElegivelException(itemId, 'não PENDENTE');
          }
          rethrow;
        }
      },
      recarregar: obterPorId,
    );
  }

  @override
  Future<SeiDocumentoPendente> cancelarPendentesDoDocumento({required String documentoId, required String motivo}) {
    return executarEscritaSeiComRecarga(
      operacao: 'cancelar_pendentes_documento_sei',
      escrever: () async {
        await _client.rpc(
          'cancelar_pendentes_documento_sei',
          params: {'p_documento_id': documentoId, 'p_motivo': motivo},
        );
        return documentoId;
      },
      recarregar: obterPorId,
    );
  }

  @override
  Future<SeiConclusaoItemResultado> concluirItem({
    required String documentoId,
    required String itemId,
    required int versaoEsperada,
    String? observacao,
    bool confirmarLimpezaDestino = false,
  }) async {
    try {
      // ÚNICA chamada: a RPC cria a movimentação (via registrar_movimentacao,
      // por dentro), atualiza o patrimônio e o item, e grava o evento — tudo
      // na mesma transação. Nenhuma outra escrita sai do cliente.
      final row = await _client.rpc(
        operacaoConcluirItemSei,
        params: {
          'p_documento_id': documentoId,
          'p_item_id': itemId,
          'p_versao_esperada': versaoEsperada,
          'p_observacao': nullIfBlank(observacao),
          'p_confirmar_limpeza_destino': confirmarLimpezaDestino,
        },
      );
      return SeiConclusaoItemResultado.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      final falha = falhaDeConclusaoSei(
        codigo: e.code,
        mensagemDoServidor: e.message,
        detalhes: e.details?.toString(),
        dica: e.hint,
        cause: e,
      );
      debugPrint('[SEI] ${falha.textoTecnico.replaceAll('\n', ' | ')}');
      throw falha;
    }
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
    try {
      // Única chamada: a RPC trava documento+itens, valida o conjunto
      // inteiro e só então chama `concluir_item_documento_sei` uma vez por
      // item — tudo na mesma transação, no servidor. O cliente nunca laça
      // chamadas à RPC individual (nenhum `for`/`await` em volta de `.rpc`
      // aqui).
      final row = await _client.rpc(
        operacaoConcluirItensSeiLote,
        params: paramsConclusaoLoteSei(
          documentoId: documentoId,
          itemIds: itemIds,
          versaoEsperada: versaoEsperada,
          loteId: loteId,
          observacao: observacao,
          confirmarLimpezaDestino: confirmarLimpezaDestino,
        ),
      );
      return SeiConclusaoLoteResultado.fromJson(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      // Mesmo tratamento de erro da conclusão individual: `P0036`/`P0037`
      // e todo o restante (P0030-P0035, P0010, P0002, P0001, 42501 —
      // propagados sem alteração pela RPC de lote) já viram mensagem
      // amigável em `mensagemErroConclusaoSei`. Uma falha de rede
      // (resultado desconhecido — a chamada pode ou não ter chegado ao
      // servidor) não cai aqui: não é um `PostgrestException`, então esta
      // função a deixa passar sem tratar como "não aconteceu" — quem chama
      // precisa preservar `loteId` e os mesmos parâmetros para um retry
      // idêntico depois.
      final falha = falhaDeConclusaoSei(
        codigo: e.code,
        mensagemDoServidor: e.message,
        detalhes: e.details?.toString(),
        dica: e.hint,
        cause: e,
        operacao: operacaoConcluirItensSeiLote,
      );
      debugPrint('[SEI] ${falha.textoTecnico.replaceAll('\n', ' | ')}');
      throw falha;
    }
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
    try {
      // SELECT direto — nunca uma RPC: a tabela só é escrita pela função
      // SECURITY DEFINER; esta leitura respeita a RLS já instalada
      // (`documentos_sei_lotes_conclusao_select`) e não precisa de nenhum
      // privilégio extra.
      final row = await _client
          .from('documentos_sei_lotes_conclusao')
          .select('documento_id, item_ids, versao_esperada, observacao, confirmar_limpeza_destino, criado_por, resultado')
          .eq('lote_id', loteId)
          .maybeSingle();
      if (row == null) return null;

      // O `lote_id` bater sozinho nunca basta: confere a identidade
      // completa contra os parâmetros que esta decisão local enviaria, com
      // a mesma normalização usada na escrita (`nullIfBlank` aqui espelha
      // `public.normalize_text` no servidor). O usuário responsável é
      // conferido contra a sessão autenticada atual (`auth.currentUser`),
      // nunca um valor vindo do cliente — mesmo papel de `auth.uid()` na
      // RPC.
      final itemIdsRegistrados = (row['item_ids'] as List<dynamic>).cast<String>();
      final itemIdsEsperados = {...itemIds}.toList()..sort();
      final observacaoEsperadaNormalizada = nullIfBlank(observacao);
      final usuarioAtualId = _client.auth.currentUser?.id;

      final identico =
          row['documento_id'] == documentoId &&
          _mesmaListaOrdenada(itemIdsRegistrados, itemIdsEsperados) &&
          (row['versao_esperada'] as num).toInt() == versaoEsperada &&
          row['observacao'] == observacaoEsperadaNormalizada &&
          row['confirmar_limpeza_destino'] == confirmarLimpezaDestino &&
          row['criado_por'] == usuarioAtualId;

      if (!identico) {
        throw SeiReconciliacaoDivergenteException(
          loteId,
          'o registro encontrado para este lote_id tem parâmetros diferentes dos que esta decisão enviaria '
          '(documento, itens, versão esperada, observação, confirmação de limpeza ou usuário responsável) — '
          'nunca aceito como resultado desta operação.',
        );
      }

      return SeiConclusaoLoteResultado.fromJson(row['resultado'] as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      // Falha de leitura (rede/permissão) — nunca convertida em `null`: o
      // chamador não pode confundir "não consegui perguntar" com "perguntei
      // e não achei nada".
      throw AppException('Falha ao consultar o registro do lote $loteId', cause: e);
    }
  }

  Map<String, Object?> _itemRascunhoParaJson(SeiItemPendenteRascunho item) => {
    'linha': item.linha,
    'patrimonio_id': item.patrimonioId,
    'numero_patrimonio_original': item.numeroPatrimonioOriginal,
    'origem_texto_original': item.origemTextoOriginal,
    'origem_setor_id': item.origemSetorId,
    'destino_texto_original': item.destinoTextoOriginal,
    'destino_setor_id': item.destinoSetorId,
    'numero_chamado_original': item.numeroChamadoOriginal,
    'equipamento_texto_original': item.equipamentoTextoOriginal,
    'localizacao_destino_id': item.localizacaoDestinoId,
    'decisao_localizacao': item.decisaoLocalizacao.value,
    'responsavel_destino': item.responsavelDestino,
    'decisao_responsavel': item.decisaoResponsavel.value,
  };
}

/// monta os SEIS parâmetros de `concluir_itens_documento_sei_lote`
/// nos nomes exatos que a RPC espera (ver `supabase/migrations/
/// 20260928100000_add_concluir_itens_documento_sei_lote.sql`, assinatura da
/// função). Extraída como função PURA (sem I/O) para poder ser testada
/// diretamente, sem depender de um `SupabaseClient` real — o mesmo padrão de
/// `traduzirBloqueioDeEdicaoSei`/`executarEscritaSeiComRecarga` já usado
/// nesta classe.
///
/// [observacao] passa por [nullIfBlank] — mesma normalização já aplicada à
/// observação da conclusão individual — antes de virar `p_observacao`.
@visibleForTesting
Map<String, Object?> paramsConclusaoLoteSei({
  required String documentoId,
  required List<String> itemIds,
  required int versaoEsperada,
  required String loteId,
  String? observacao,
  bool confirmarLimpezaDestino = false,
}) => {
  'p_documento_id': documentoId,
  'p_item_ids': itemIds,
  'p_versao_esperada': versaoEsperada,
  'p_lote_id': loteId,
  'p_observacao': nullIfBlank(observacao),
  'p_confirmar_limpeza_destino': confirmarLimpezaDestino,
};

/// `editar_documento_sei_pendente` recusa a edição com `42501` e uma mensagem
/// contendo "bloqueado" em dois casos: documento com item CONCLUÍDO
/// e documento ENCERRADO, sem nenhum item PENDENTE. Ambos viram
/// [SeiDocumentoBloqueadoParaEdicaoException]; qualquer outro erro devolve
/// `null` (segue o tratamento normal).
@visibleForTesting
SeiDocumentoBloqueadoParaEdicaoException? traduzirBloqueioDeEdicaoSei(PostgrestException e, String documentoId) {
  if (e.code == '42501' && e.message.toLowerCase().contains('bloqueado')) {
    return SeiDocumentoBloqueadoParaEdicaoException(documentoId);
  }
  return null;
}

/// executa uma escrita SEI em DUAS fases distintas, para a UI
/// nunca confundir "a RPC falhou" com "a RPC funcionou mas a releitura falhou":
///
///  1. [escrever] — a chamada da RPC (devolve o id do documento afetado). Uma
///     `PostgrestException` aqui significa que o servidor RECUSOU/falhou: a
///     transação foi desfeita e nada mudou. Vira [SeiEscritaFalhouException]
///     com o erro técnico original (código, mensagem, detalhes, dica), que
///     também é registrado no log. Qualquer OUTRA exceção (ex.: exceção de
///     negócio, falha de rede, cujo resultado é incerto) passa sem mudança.
///  2. [recarregar] — a releitura do documento. Se falhar, a RPC JÁ retornou
///     sucesso: vira [SeiEscritaConcluidaRecargaFalhouException] (a escrita
///     provavelmente foi aplicada; não repetir às cegas).
@visibleForTesting
Future<SeiDocumentoPendente> executarEscritaSeiComRecarga({
  required String operacao,
  required Future<String> Function() escrever,
  required Future<SeiDocumentoPendente> Function(String documentoId) recarregar,
}) async {
  final String documentoId;
  try {
    documentoId = await escrever();
  } on PostgrestException catch (e) {
    final falha = SeiEscritaFalhouException(
      operacao: operacao,
      mensagem: _mapearErro(e),
      codigo: e.code,
      detalhes: e.details?.toString(),
      dica: e.hint,
      cause: e,
    );
    debugPrint('[SEI] ${falha.textoTecnico.replaceAll('\n', ' | ')}');
    throw falha;
  }

  try {
    return await recarregar(documentoId);
  } catch (e) {
    debugPrint('[SEI] $operacao concluída, mas a releitura do documento $documentoId falhou: $e');
    throw SeiEscritaConcluidaRecargaFalhouException(operacao: operacao, documentoId: documentoId, cause: e);
  }
}

String _mapearErro(PostgrestException e) {
  if (e.code == '42501') return 'Você não tem permissão para esta ação.';
  if (e.code == 'P0002') return 'Registro não encontrado.';
  return e.message;
}

/// ambos os lados já chegam CANÔNICOS (distintos +
/// ordenados) nesta comparação; elemento a elemento evita depender de
/// `package:collection` (não é dependência direta deste projeto) só para
/// isto — mesmo padrão já usado em `fake_documentos_sei_repository.dart`.
bool _mesmaListaOrdenada(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final documentosSeiRepositoryProvider = Provider<DocumentosSeiRepository>((ref) {
  return DocumentosSeiRepositorySupabase(Supabase.instance.client);
});
