import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_pendencia_regras.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';

SeiItemPendente _item({
  String id = 'item-1',
  SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente,
  String? patrimonioId = 'pat-1',
  String? destinoSetorId = 'setor-1',
  SeiDecisaoCampo decisaoLocalizacao = SeiDecisaoCampo.confirmadoSemInformacao,
  SeiDecisaoCampo decisaoResponsavel = SeiDecisaoCampo.confirmadoSemInformacao,
}) {
  return SeiItemPendente(
    id: id,
    documentoId: 'doc-1',
    linha: 1,
    patrimonioId: patrimonioId,
    numeroPatrimonio: const SeiValorCorrigivel(original: '123'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    destinoTexto: const SeiValorCorrigivel(original: 'GEASI'),
    destinoSetorId: destinoSetorId,
    numeroChamado: const SeiValorCorrigivel(original: '4556'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Monitor'),
    decisaoLocalizacao: decisaoLocalizacao,
    decisaoResponsavel: decisaoResponsavel,
    status: status,
    criadoEm: DateTime(2026, 1, 1),
  );
}

SeiDocumentoPendente _documento(List<SeiItemPendente> itens) {
  return SeiDocumentoPendente.fromItens(
    id: 'doc-1',
    numeroDocumentoSei: '95955192',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'doc.pdf',
    hashSha256: 'h',
    versao: 1,
    criadoEm: DateTime(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Fulano',
    itens: itens,
  );
}

void main() {
  group('PROMPT 11.3, seção 9 — itemPodeSerCancelado', () {
    test('item PENDENTE pode ser cancelado', () {
      expect(itemPodeSerCancelado(_item(status: SeiItemPendenciaStatus.pendente)), isTrue);
    });
    test('item CONCLUIDO não pode ser cancelado', () {
      expect(itemPodeSerCancelado(_item(status: SeiItemPendenciaStatus.concluido)), isFalse);
    });
    test('item já CANCELADO não pode ser cancelado de novo', () {
      expect(itemPodeSerCancelado(_item(status: SeiItemPendenciaStatus.cancelado)), isFalse);
    });
  });

  group('PROMPT 11.3, seção 11 — itemElegivelParaConclusaoFutura', () {
    test('PENDENTE + patrimônio resolvido + destino resolvido + decisões tomadas → elegível', () {
      expect(itemElegivelParaConclusaoFutura(_item()), isTrue);
    });

    test('sem patrimônio resolvido → não elegível', () {
      expect(itemElegivelParaConclusaoFutura(_item(patrimonioId: null)), isFalse);
    });

    test('sem destino resolvido → não elegível', () {
      expect(itemElegivelParaConclusaoFutura(_item(destinoSetorId: null)), isFalse);
    });

    test('decisão de localização pendente → não elegível', () {
      expect(
        itemElegivelParaConclusaoFutura(_item(decisaoLocalizacao: SeiDecisaoCampo.pendente)),
        isFalse,
      );
    });

    test('decisão de responsável pendente → não elegível', () {
      expect(
        itemElegivelParaConclusaoFutura(_item(decisaoResponsavel: SeiDecisaoCampo.pendente)),
        isFalse,
      );
    });

    test('item já concluído não é "elegível para concluir de novo"', () {
      expect(itemElegivelParaConclusaoFutura(_item(status: SeiItemPendenciaStatus.concluido)), isFalse);
    });

    test('"concluir todos elegíveis" nunca inclui cancelados nem bloqueados', () {
      final itens = [
        _item(id: 'a', status: SeiItemPendenciaStatus.pendente),
        _item(id: 'b', status: SeiItemPendenciaStatus.cancelado),
        _item(id: 'c', status: SeiItemPendenciaStatus.pendente, patrimonioId: null),
      ];
      final elegiveis = itensElegiveisParaConclusaoFutura(itens);
      expect(elegiveis.map((i) => i.id), ['a']);
    });
  });

  group('PROMPT 11.3, seção 8 — documentoPodeSerEditado', () {
    test('nenhum item concluído → editável', () {
      final doc = _documento([_item(status: SeiItemPendenciaStatus.pendente)]);
      expect(documentoPodeSerEditado(doc), isTrue);
    });

    test('ao menos um item concluído → bloqueado para sempre, mesmo com outros pendentes', () {
      final doc = _documento([
        _item(id: 'a', status: SeiItemPendenciaStatus.concluido),
        _item(id: 'b', status: SeiItemPendenciaStatus.pendente),
      ]);
      expect(documentoPodeSerEditado(doc), isFalse);
    });
  });
}
