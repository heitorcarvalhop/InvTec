import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_analyzer.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_pendencia_builder.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_execucao_estado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/domain/setor.dart';

final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorGeasi = Setor(id: 'setor-geasi', nome: 'Gerência de Licenciamento', sigla: 'GEASI', ativo: true, criadoEm: DateTime(2026, 1, 1));

PatrimonioDetalhe _patrimonio() {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'id-4157090',
      numeroPatrimonio: '4157090',
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-getec',
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'Gerencia de Tecnologia',
  );
}

SeiDocumentoExtraido _documento({MovimentacaoTipo? tipo = MovimentacaoTipo.transferencia}) {
  return SeiDocumentoExtraido(
    nomeArquivo: 'doc.pdf',
    tamanhoBytes: 100,
    quantidadePaginas: 1,
    hashSha256: 'hash-abc',
    numeroDocumentoSei: '95955192',
    numeroProcesso: '202600017000011',
    numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
    assunto: 'Transferência de bens',
    tipoMovimentacaoInferido: tipo,
    itens: [
      SeiItemExtraido(
        linha: 1,
        paginaOrigem: 1,
        numeroPatrimonio: '4157090',
        equipamento: 'Monitor Positivo',
        unidadeOrigemTexto: 'GETEC - Gerencia de Tecnologia',
        unidadeDestinoTexto: 'Gerência de Licenciamento – GEASI',
        numeroChamado: '4556',
      ),
    ],
  );
}

void main() {
  group('construirDocumentoPendenteRascunho', () {
    test('tipo de movimentação não inferido → retorna null (nunca inventa o tipo)', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(tipo: null),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final rascunho = construirDocumentoPendenteRascunho(resultado: resultado, execucao: const {});
      expect(rascunho, isNull);
    });

    test('mapeia metadados do documento e do item, incluindo decisões já tomadas na análise', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final rascunho = construirDocumentoPendenteRascunho(
        resultado: resultado,
        execucao: {
          1: const SeiItemExecucaoEstado(
            decisaoLocalizacao: SeiDecisaoCampo.definido,
            localizacaoDestinoId: 'loc-1',
            localizacaoDestinoNome: 'Datacenter',
            decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
          ),
        },
      );

      expect(rascunho, isNotNull);
      expect(rascunho!.numeroDocumentoSei, '95955192');
      expect(rascunho.numeroProcesso, '202600017000011');
      expect(rascunho.numeroDocumentoFormatado, '577/2026/SEMAD/GETEC-12014');
      expect(rascunho.assunto, 'Transferência de bens');
      expect(rascunho.tipoOperacaoPretendida, MovimentacaoTipo.transferencia);
      expect(rascunho.hashSha256, 'hash-abc');
      expect(rascunho.itens, hasLength(1));

      final item = rascunho.itens.single;
      expect(item.linha, 1);
      expect(item.patrimonioId, 'id-4157090');
      expect(item.numeroPatrimonioOriginal, '4157090');
      expect(item.destinoSetorId, 'setor-geasi');
      expect(item.numeroChamadoOriginal, '4556');
      expect(item.decisaoLocalizacao, SeiDecisaoCampo.definido);
      expect(item.localizacaoDestinoId, 'loc-1');
      expect(item.decisaoResponsavel, SeiDecisaoCampo.confirmadoSemInformacao);
    });

    test('item sem entrada em execucao usa decisões PENDENTE por padrão (nunca inventa uma decisão)', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final rascunho = construirDocumentoPendenteRascunho(resultado: resultado, execucao: const {});

      final item = rascunho!.itens.single;
      expect(item.decisaoLocalizacao, SeiDecisaoCampo.pendente);
      expect(item.decisaoResponsavel, SeiDecisaoCampo.pendente);
    });

    test('item cujo patrimônio não foi encontrado no InvTec ainda vira item da pendência (patrimonioId null)', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: const {},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final rascunho = construirDocumentoPendenteRascunho(resultado: resultado, execucao: const {});
      expect(rascunho!.itens, hasLength(1));
      expect(rascunho.itens.single.patrimonioId, isNull);
      expect(rascunho.itens.single.numeroPatrimonioOriginal, '4157090');
    });
  });
}
