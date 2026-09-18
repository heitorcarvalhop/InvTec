import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_analyzer.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_validacao_item.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/domain/setor.dart';

final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorGeasi = Setor(id: 'setor-geasi', nome: 'Gerência de Licenciamento', sigla: 'GEASI', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setoresPadrao = [_setorGetec, _setorGeasi];

PatrimonioDetalhe _patrimonio({
  String id = 'p1',
  String numero = '4157090',
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  String setorAtualId = 'setor-getec',
  String tipoNome = 'Monitor',
  String? marca = 'Positivo',
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: setorAtualId,
      marca: marca,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: tipoNome,
    setorNome: 'Gerencia de Tecnologia',
  );
}

SeiItemExtraido _item({
  int linha = 1,
  String? numeroPatrimonio = '4157090',
  String? equipamento = 'Monitor Positivo',
  String? origem = 'GETEC - Gerencia de Tecnologia',
  String? destino = 'Gerência de Licenciamento – GEASI',
  String? chamado = '4556',
  SeiConfianca confiancaPatrimonio = SeiConfianca.alta,
  SeiConfianca confiancaDestino = SeiConfianca.alta,
}) {
  return SeiItemExtraido(
    linha: linha,
    paginaOrigem: 1,
    numeroPatrimonio: numeroPatrimonio,
    equipamento: equipamento,
    unidadeOrigemTexto: origem,
    unidadeDestinoTexto: destino,
    numeroChamado: chamado,
    confiancaPatrimonio: confiancaPatrimonio,
    confiancaDestino: confiancaDestino,
  );
}

SeiDocumentoExtraido _documento({
  List<SeiItemExtraido>? itens,
  MovimentacaoTipo? tipo = MovimentacaoTipo.transferencia,
}) {
  return SeiDocumentoExtraido(
    nomeArquivo: 'doc.pdf',
    tamanhoBytes: 1000,
    quantidadePaginas: 1,
    hashSha256: 'hash',
    tipoMovimentacaoInferido: tipo,
    itens: itens ?? [_item()],
  );
}

void main() {
  group('PROMPT 11.1 — SeiDocumentoAnalyzer (cruzamento READ-ONLY)', () {
    test('patrimônio existente + origem confere + destino identificado + tipo compatível: PRONTO', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.itens.single.status, SeiStatusLinha.pronto);
      expect(resultado.totalProntos, 1);
      expect(resultado.itens.single.origem.entidadeEncontrada, _setorGetec);
      expect(resultado.itens.single.destino.entidadeEncontrada, _setorGeasi);
    });

    test('patrimônio não encontrado no InvTec: BLOQUEADO', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: const {},
        setoresAtivos: _setoresPadrao,
      );

      final item = resultado.itens.single;
      expect(item.status, SeiStatusLinha.bloqueado);
      expect(item.bloqueios, contains(contains('não encontrado no InvTec')));
    });

    test('origem do documento diverge do setor atual: BLOQUEADO', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: {'4157090': _patrimonio(setorAtualId: 'setor-geasi')},
        setoresAtivos: _setoresPadrao,
      );

      final item = resultado.itens.single;
      expect(item.status, SeiStatusLinha.bloqueado);
      expect(item.bloqueios, contains(contains('diverge do setor atual')));
    });

    test('destino não encontrado no InvTec: BLOQUEADO, nunca mapeado para outro setor', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(itens: [_item(destino: 'Unidade Desconhecida – XYZW')]),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: _setoresPadrao,
      );

      final item = resultado.itens.single;
      expect(item.status, SeiStatusLinha.bloqueado);
      expect(item.destino.entidadeEncontrada, isNull);
      expect(item.bloqueios, contains(contains('Destino não encontrado')));
    });

    test('patrimônio duplicado no documento: TODAS as ocorrências ficam BLOQUEADAS (nunca deduplicado)', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(itens: [_item(linha: 1), _item(linha: 2)]),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.itens, hasLength(2));
      expect(resultado.itens.every((i) => i.status == SeiStatusLinha.bloqueado), isTrue);
      expect(resultado.itens.every((i) => i.bloqueios.any((b) => b.contains('mais de uma vez'))), isTrue);
    });

    test('tipo de movimentação não identificado no documento: BLOQUEADO', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(tipo: null),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.itens.single.status, SeiStatusLinha.bloqueado);
    });

    test('tipo de movimentação incompatível com o status atual (ex.: BAIXADO): BLOQUEADO', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(),
        patrimoniosPorNumero: {'4157090': _patrimonio(status: PatrimonioStatus.baixado, setorAtualId: 'setor-getec')},
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.itens.single.status, SeiStatusLinha.bloqueado);
      expect(resultado.itens.single.bloqueios, contains(contains('não é uma movimentação válida')));
    });

    test('chamado ausente: AVISO, nunca bloqueante', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(itens: [_item(chamado: null)]),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.itens.single.status, SeiStatusLinha.aviso);
    });

    test('equipamento diferente do cadastrado: AVISO informativo, nunca bloqueante sozinho', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(itens: [_item(equipamento: 'Impressora Laser')]),
        patrimoniosPorNumero: {'4157090': _patrimonio(tipoNome: 'Monitor', marca: 'Positivo')},
        setoresAtivos: _setoresPadrao,
      );

      final item = resultado.itens.single;
      expect(item.status, SeiStatusLinha.aviso);
      expect(item.equipamentoCompativel, isFalse);
    });

    test(
      'PROMPT 11.1.1 — candidato de patrimônio (confiança baixa) ENCONTRADO no InvTec: AVISO, nunca bloqueado '
      'só pelo comprimento atípico',
      () {
        final resultado = const SeiDocumentoAnalyzer().analisar(
          documento: _documento(itens: [_item(confiancaPatrimonio: SeiConfianca.baixa)]),
          patrimoniosPorNumero: {'4157090': _patrimonio()},
          setoresAtivos: _setoresPadrao,
        );

        final item = resultado.itens.single;
        expect(item.status, SeiStatusLinha.aviso);
        expect(item.patrimonioEncontrado, isNotNull);
        expect(item.avisos, contains(contains('formato atípico')));
      },
    );

    test(
      'PROMPT 11.1.1 — candidato de patrimônio (confiança baixa) NÃO encontrado no InvTec: BLOQUEADO',
      () {
        final resultado = const SeiDocumentoAnalyzer().analisar(
          documento: _documento(itens: [_item(numeroPatrimonio: '12345', confiancaPatrimonio: SeiConfianca.baixa)]),
          patrimoniosPorNumero: {'4157090': _patrimonio()},
          setoresAtivos: _setoresPadrao,
        );

        final item = resultado.itens.single;
        expect(item.status, SeiStatusLinha.bloqueado);
        expect(item.bloqueios, contains(contains('não encontrado no InvTec')));
      },
    );

    test('número de patrimônio com confiança média (reconstruído): AVISO, não bloqueia sozinho', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(itens: [_item(confiancaPatrimonio: SeiConfianca.media)]),
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.itens.single.status, SeiStatusLinha.aviso);
    });

    test('contadores do SeiAnaliseResultado batem com os status individuais', () {
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: _documento(
          itens: [
            _item(linha: 1, numeroPatrimonio: '1111111'),
            _item(linha: 2, numeroPatrimonio: '2222222', chamado: null),
            _item(linha: 3, numeroPatrimonio: '3333333'),
          ],
        ),
        patrimoniosPorNumero: {
          '1111111': _patrimonio(numero: '1111111'),
          '2222222': _patrimonio(numero: '2222222'),
        },
        setoresAtivos: _setoresPadrao,
      );

      expect(resultado.totalItens, 3);
      expect(resultado.totalProntos, 1);
      expect(resultado.totalAvisos, 1);
      expect(resultado.totalBloqueados, 1);
    });
  });
}
