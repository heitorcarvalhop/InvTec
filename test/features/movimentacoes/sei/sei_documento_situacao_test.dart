import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_situacao.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';

const _p = SeiItemPendenciaStatus.pendente;
const _c = SeiItemPendenciaStatus.concluido;
const _x = SeiItemPendenciaStatus.cancelado;

void main() {
  group('calcularSituacaoDocumento (derivada, sem estado contraditório)', () {
    test('lista vazia é tratada como PENDENTE', () {
      expect(calcularSituacaoDocumento(const []), SeiDocumentoSituacao.pendente);
    });

    test('todos pendentes → PENDENTE', () {
      expect(calcularSituacaoDocumento([_p, _p, _p]), SeiDocumentoSituacao.pendente);
    });

    test('parte concluída, ainda há pendências → PARCIALMENTE_CONCLUIDO', () {
      expect(calcularSituacaoDocumento([_c, _p, _p]), SeiDocumentoSituacao.parcialmenteConcluido);
    });

    // Esta combinação (0 concluídos, itens pendentes, itens cancelados)
    // continua PENDENTE: nenhuma movimentação foi concluída, então o
    // documento não vira PARCIALMENTE_CONCLUIDO só por ter itens já
    // cancelados.
    test('0 concluídos + pendentes + cancelados, sem nenhuma conclusão → PENDENTE', () {
      expect(calcularSituacaoDocumento([_x, _p, _p]), SeiDocumentoSituacao.pendente);
      expect(calcularSituacaoDocumento([_x, _x, _p]), SeiDocumentoSituacao.pendente);
    });

    test('todos concluídos → CONCLUIDO', () {
      expect(calcularSituacaoDocumento([_c, _c, _c]), SeiDocumentoSituacao.concluido);
    });

    test('todos cancelados, nenhuma conclusão → CANCELADO', () {
      expect(calcularSituacaoDocumento([_x, _x]), SeiDocumentoSituacao.cancelado);
    });

    test('parte concluída e restante cancelada, sem pendências → ENCERRADO_PARCIALMENTE', () {
      expect(calcularSituacaoDocumento([_c, _x, _c, _x]), SeiDocumentoSituacao.encerradoParcialmente);
    });

    test('concluído + pendente + cancelado juntos, ainda há pendência → PARCIALMENTE_CONCLUIDO', () {
      expect(calcularSituacaoDocumento([_c, _p, _x]), SeiDocumentoSituacao.parcialmenteConcluido);
    });
  });

  group('paridade Dart/SQL com as combinações exatas da view', () {
    // Sem PostgreSQL disponível neste ambiente (ver relatório), a
    // "paridade" é verificada comparando `calcularSituacaoDocumento`
    // (Dart) contra uma tradução literal, linha a linha, do `case` da view
    // `documentos_sei_com_situacao` (SQL) — mesma ordem de ramos, mesmas
    // condições. Qualquer mudança em um dos dois lados que não seja
    // replicada no outro quebra este teste. NÃO substitui rodar contra o
    // banco real (a view pode ter, por exemplo, um erro de tipo ou de
    // agregação que só aparece em execução — ver seção 10 do relatório).
    SeiDocumentoSituacao viewSql({required int concluidos, required int pendentes, required int cancelados}) {
      final total = concluidos + pendentes + cancelados;
      if (total == 0) return SeiDocumentoSituacao.pendente;
      if (concluidos == 0 && pendentes > 0) return SeiDocumentoSituacao.pendente;
      if (concluidos == total) return SeiDocumentoSituacao.concluido;
      if (cancelados == total) return SeiDocumentoSituacao.cancelado;
      if (pendentes == 0) return SeiDocumentoSituacao.encerradoParcialmente;
      return SeiDocumentoSituacao.parcialmenteConcluido;
    }

    void verificarParidade(String descricao, {required int concluidos, required int pendentes, required int cancelados}) {
      test(descricao, () {
        final itens = [
          ...List.filled(concluidos, _c),
          ...List.filled(pendentes, _p),
          ...List.filled(cancelados, _x),
        ];
        final resultadoDart = calcularSituacaoDocumento(itens);
        final resultadoSql = viewSql(concluidos: concluidos, pendentes: pendentes, cancelados: cancelados);
        expect(
          resultadoDart,
          resultadoSql,
          reason: 'Dart ($resultadoDart) diverge da tradução do CASE SQL ($resultadoSql)',
        );
      });
    }

    verificarParidade('33 pendentes', concluidos: 0, pendentes: 33, cancelados: 0);
    verificarParidade('10 concluídos + 23 pendentes', concluidos: 10, pendentes: 23, cancelados: 0);
    verificarParidade('10 concluídos + 23 cancelados', concluidos: 10, pendentes: 0, cancelados: 23);
    verificarParidade('33 concluídos', concluidos: 33, pendentes: 0, cancelados: 0);
    verificarParidade('33 cancelados', concluidos: 0, pendentes: 0, cancelados: 33);
    verificarParidade('10 pendentes + 23 cancelados', concluidos: 0, pendentes: 10, cancelados: 23);

    test('as 6 combinações resolvem para situações esperadas explicitamente', () {
      expect(viewSql(concluidos: 0, pendentes: 33, cancelados: 0), SeiDocumentoSituacao.pendente);
      expect(viewSql(concluidos: 10, pendentes: 23, cancelados: 0), SeiDocumentoSituacao.parcialmenteConcluido);
      expect(viewSql(concluidos: 10, pendentes: 0, cancelados: 23), SeiDocumentoSituacao.encerradoParcialmente);
      expect(viewSql(concluidos: 33, pendentes: 0, cancelados: 0), SeiDocumentoSituacao.concluido);
      expect(viewSql(concluidos: 0, pendentes: 0, cancelados: 33), SeiDocumentoSituacao.cancelado);
      expect(viewSql(concluidos: 0, pendentes: 10, cancelados: 23), SeiDocumentoSituacao.pendente);
    });
  });
}
