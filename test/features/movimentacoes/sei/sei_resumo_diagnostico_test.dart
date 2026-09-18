import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_analyzer.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_resumo_diagnostico.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/domain/setor.dart';

/// PROMPT 11.1.1, seção 10: o resumo de diagnóstico é só para
/// auditoria/debug — precisa ser JSON válido, conter os campos relevantes e
/// nunca disparar nenhuma leitura/escrita (a função é pura, recebe o
/// resultado já calculado).
void main() {
  test('construirResumoDiagnosticoSei produz JSON válido com metadados, contadores e itens', () {
    final setorGetec = Setor(id: 's1', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
    final documento = SeiDocumentoExtraido(
      nomeArquivo: 'despacho.pdf',
      tamanhoBytes: 1234,
      quantidadePaginas: 1,
      hashSha256: 'abc123',
      numeroProcesso: '202600017000011',
      numeroDocumentoSei: '95955192',
      numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
      assunto: 'Transferência de patrimônio',
      tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
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

    final patrimonio = PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: 'p1',
        numeroPatrimonio: '4157090',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.disponivel,
        setorAtualId: 's1',
        dataCadastro: DateTime(2026, 1, 1),
        atualizadoEm: DateTime(2026, 1, 1),
      ),
      tipoNome: 'Monitor',
      setorNome: 'Gerencia de Tecnologia',
    );

    final resultado = const SeiDocumentoAnalyzer().analisar(
      documento: documento,
      patrimoniosPorNumero: {'4157090': patrimonio},
      setoresAtivos: [setorGetec],
    );

    final texto = construirResumoDiagnosticoSei(resultado);
    final json = jsonDecode(texto) as Map<String, Object?>;

    expect((json['documento'] as Map)['numeroProcesso'], '202600017000011');
    expect((json['documento'] as Map)['hashSha256'], 'abc123');
    expect((json['contadores'] as Map)['totalItens'], 1);
    final itens = json['itens'] as List;
    expect(itens, hasLength(1));
    expect((itens.single as Map)['numeroPatrimonio'], '4157090');
  });
}
