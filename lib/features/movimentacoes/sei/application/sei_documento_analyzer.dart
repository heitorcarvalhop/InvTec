import '../../../patrimonios/domain/patrimonio.dart';
import '../../../patrimonios/domain/patrimonio_detalhe.dart';
import '../../../patrimonios/importacao/domain/text_similarity.dart';
import '../../../setores/domain/setor.dart';
import '../../domain/movimentacao.dart';
import '../../presentation/nova_movimentacao_regras.dart';
import '../domain/sei_analise_resultado.dart';
import '../domain/sei_documento_extraido.dart';
import '../domain/sei_item_extraido.dart';
import '../domain/sei_validacao_item.dart';

/// Extrai a sigla de uma unidade a partir do texto do documento — no
/// INÍCIO ("GETEC - Gerencia de Tecnologia") ou no FIM ("Gerência de ... –
/// GEASI"), as duas convenções observadas no SEI (PROMPT 11.1, seção
/// 17/18). Nunca decide sozinha qual é a unidade real: só normaliza o
/// candidato para comparação contra `Setor.sigla`.
String? _extrairSigla(String? texto) {
  if (texto == null) return null;
  final noFim = RegExp(r'[–-]\s*([A-ZÀ-Ü]{2,12})\s*$').firstMatch(texto);
  if (noFim != null) return noFim.group(1);
  final noInicio = RegExp(r'^\s*([A-ZÀ-Ü]{2,12})\b').firstMatch(texto);
  return noInicio?.group(1);
}

/// Cruzamento READ-ONLY entre o que foi extraído do PDF e o que existe no
/// InvTec (PROMPT 11.1, seções 16-20) — recebe os dados já buscados EM LOTE
/// pelo controller (nunca faz I/O sozinho, nunca decide uma query aqui:
/// isso evita N+1 por construção, seção 16). Não altera nada; produz só o
/// veredito de cada linha.
class SeiDocumentoAnalyzer {
  const SeiDocumentoAnalyzer();

  SeiAnaliseResultado analisar({
    required SeiDocumentoExtraido documento,
    required Map<String, PatrimonioDetalhe> patrimoniosPorNumero,
    required List<Setor> setoresAtivos,
  }) {
    final contagemPorNumero = <String, int>{};
    for (final item in documento.itens) {
      final numero = item.numeroPatrimonio;
      if (numero != null) contagemPorNumero[numero] = (contagemPorNumero[numero] ?? 0) + 1;
    }

    final setorPorSigla = <String, Setor>{
      for (final setor in setoresAtivos)
        if (setor.sigla != null && setor.sigla!.trim().isNotEmpty)
          normalizarTextoComparacao(setor.sigla!): setor,
    };
    final setorPorId = {for (final setor in setoresAtivos) setor.id: setor};

    final itens = documento.itens.map((item) {
      final duplicado = item.numeroPatrimonio != null && (contagemPorNumero[item.numeroPatrimonio] ?? 0) > 1;
      return _validarItem(
        item: item,
        documento: documento,
        patrimoniosPorNumero: patrimoniosPorNumero,
        setorPorSigla: setorPorSigla,
        setorPorId: setorPorId,
        duplicadoNoDocumento: duplicado,
      );
    }).toList();

    return SeiAnaliseResultado(documento: documento, itens: itens);
  }

  SeiValidacaoItem _validarItem({
    required SeiItemExtraido item,
    required SeiDocumentoExtraido documento,
    required Map<String, PatrimonioDetalhe> patrimoniosPorNumero,
    required Map<String, Setor> setorPorSigla,
    required Map<String, Setor> setorPorId,
    required bool duplicadoNoDocumento,
  }) {
    final checks = <String>[];
    final avisos = <String>[];
    final bloqueios = <String>[];

    // ---- patrimônio -------------------------------------------------
    // PROMPT 11.1.1, seção 4: um candidato de comprimento atípico
    // (confiancaPatrimonio == baixa, mas numeroPatrimonio != null) NUNCA é
    // bloqueado só por isso — é o cruzamento com o InvTec (já buscado em
    // lote pelo controller) que decide: se o candidato existe de fato,
    // vira apenas um aviso de revisão; se não existe, bloqueia com o
    // mesmo motivo de qualquer patrimônio não encontrado.
    PatrimonioDetalhe? patrimonio;
    if (item.numeroPatrimonio == null) {
      bloqueios.add('Número do patrimônio não identificado nesta linha.');
    } else {
      patrimonio = patrimoniosPorNumero[item.numeroPatrimonio];
      if (patrimonio == null) {
        bloqueios.add('Patrimônio ${item.numeroPatrimonio} não encontrado no InvTec.');
      } else {
        checks.add('Patrimônio ${item.numeroPatrimonio} encontrado no InvTec.');
        if (item.confiancaPatrimonio == SeiConfianca.baixa) {
          avisos.add(
            'Número do patrimônio (${item.numeroPatrimonio}) foi extraído com formato atípico nesta linha, mas '
            'corresponde a um patrimônio real no InvTec — confira contra o documento original.',
          );
        }
      }
    }

    if (duplicadoNoDocumento) {
      bloqueios.add('Patrimônio ${item.numeroPatrimonio} aparece mais de uma vez neste documento.');
    }

    // ---- origem -------------------------------------------------------
    final origemSigla = _extrairSigla(item.unidadeOrigemTexto);
    final origemEncontrada = origemSigla != null ? setorPorSigla[normalizarTextoComparacao(origemSigla)] : null;
    if (patrimonio != null) {
      if (origemEncontrada != null && origemEncontrada.id == patrimonio.patrimonio.setorAtualId) {
        checks.add('Origem do documento confere com o setor atual do patrimônio no InvTec.');
      } else {
        final setorAtual = setorPorId[patrimonio.patrimonio.setorAtualId];
        bloqueios.add(
          'Origem do documento (${item.unidadeOrigemTexto ?? "não identificada"}) diverge do setor atual '
          'no InvTec (${setorAtual?.nome ?? patrimonio.setorNome}).',
        );
      }
    }

    // ---- destino --------------------------------------------------------
    final destinoSigla = _extrairSigla(item.unidadeDestinoTexto);
    final destinoEncontrado = destinoSigla != null ? setorPorSigla[normalizarTextoComparacao(destinoSigla)] : null;
    if (item.unidadeDestinoTexto == null || destinoSigla == null) {
      bloqueios.add('Destino não encontrado no InvTec.');
    } else if (destinoEncontrado == null) {
      bloqueios.add('Destino não encontrado no InvTec: "${item.unidadeDestinoTexto}".');
    } else {
      checks.add('Destino identificado no InvTec: ${destinoEncontrado.nome}.');
    }

    // ---- tipo de movimentação -----------------------------------------
    if (documento.tipoMovimentacaoInferido == null) {
      bloqueios.add('Tipo de movimentação não identificado ou não suportado nesta versão.');
    } else if (patrimonio != null) {
      final tiposPermitidos = tiposCompativeisComStatus(patrimonio.patrimonio.status);
      if (!tiposPermitidos.contains(documento.tipoMovimentacaoInferido)) {
        bloqueios.add(
          '${documento.tipoMovimentacaoInferido!.label} não é uma movimentação válida para o status atual '
          '(${patrimonio.patrimonio.status.label}) deste patrimônio no InvTec.',
        );
      } else {
        checks.add('Tipo de movimentação compatível com o status atual do patrimônio.');
      }
    }

    // ---- equipamento (informativo, nunca bloqueante sozinho) -----------
    bool? equipamentoCompativel;
    if (patrimonio != null && item.equipamento != null && item.equipamento!.trim().isNotEmpty) {
      final textoCadastro = normalizarTextoComparacao(
        [patrimonio.tipoNome, patrimonio.patrimonio.marca, patrimonio.patrimonio.modelo, patrimonio.patrimonio.descricao]
            .whereType<String>()
            .join(' '),
      );
      final palavrasDocumento = normalizarTextoComparacao(item.equipamento!).split(' ');
      equipamentoCompativel = palavrasDocumento.any(
        (palavra) => palavra.length > 2 && contemFraseComoPalavra(textoCadastro, palavra),
      );
      if (!equipamentoCompativel) {
        avisos.add(
          'Equipamento do documento ("${item.equipamento}") parece diferente do cadastrado no InvTec '
          '(${patrimonio.tipoNome}).',
        );
      }
    }

    if (item.numeroChamado == null) {
      avisos.add('Chamado 4Biz/SEI não informado para este item.');
    }
    if (item.confiancaPatrimonio == SeiConfianca.media) {
      avisos.add(
        'Número do patrimônio foi reconstruído a partir de texto intercalado no PDF — confira contra o '
        'documento original.',
      );
    }
    if (item.confiancaDestino == SeiConfianca.baixa) {
      bloqueios.add('Não foi possível identificar o texto de destino com segurança nesta linha.');
    }

    final status = bloqueios.isNotEmpty
        ? SeiStatusLinha.bloqueado
        : avisos.isNotEmpty
        ? SeiStatusLinha.aviso
        : SeiStatusLinha.pronto;

    return SeiValidacaoItem(
      item: item,
      status: status,
      checks: checks,
      avisos: avisos,
      bloqueios: bloqueios,
      patrimonioEncontrado: patrimonio,
      origem: SeiComparacaoUnidade(
        valorOriginal: item.unidadeOrigemTexto,
        valorNormalizado: origemSigla,
        entidadeEncontrada: origemEncontrada,
      ),
      destino: SeiComparacaoUnidade(
        valorOriginal: item.unidadeDestinoTexto,
        valorNormalizado: destinoSigla,
        entidadeEncontrada: destinoEncontrado,
      ),
      equipamentoCompativel: equipamentoCompativel,
    );
  }
}
