import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_parser.dart';
import 'package:invtec/features/movimentacoes/sei/data/sei_pdf_text_extractor.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_import_controller.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../patrimonios/fake_patrimonio_repository.dart';
import '../../setores/fake_setor_repository.dart';

class _FakeExtractor implements SeiPdfTextExtractor {
  _FakeExtractor({this.resultado, this.erro});
  final SeiPdfLido? resultado;
  final Object? erro;
  int chamadas = 0;

  @override
  Future<SeiPdfLido> extrair(Uint8List bytes) async {
    chamadas++;
    if (erro != null) throw erro!;
    return resultado!;
  }
}

class _FakeParser implements SeiDocumentoParser {
  _FakeParser(this.documento);
  final SeiDocumentoExtraido documento;

  @override
  Future<SeiDocumentoExtraido> analisar({
    required String nomeArquivo,
    required int tamanhoBytes,
    required String hashSha256,
    required List<String> textoPorPagina,
  }) async => documento;
}

final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorGeasi = Setor(id: 'setor-geasi', nome: 'Gerência de Licenciamento', sigla: 'GEASI', ativo: true, criadoEm: DateTime(2026, 1, 1));

PatrimonioDetalhe _patrimonio(String numero, {String setorAtualId = 'setor-getec'}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'id-$numero',
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: setorAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'Gerencia de Tecnologia',
  );
}

SeiDocumentoExtraido _documentoComDoisItens() {
  return SeiDocumentoExtraido(
    nomeArquivo: 'despacho.pdf',
    tamanhoBytes: 500,
    quantidadePaginas: 1,
    hashSha256: 'hash-fake',
    numeroProcesso: '202600017000011',
    numeroDocumentoSei: '95955192',
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
      SeiItemExtraido(
        linha: 2,
        paginaOrigem: 1,
        numeroPatrimonio: '9999999',
        equipamento: 'Notebook Dell',
        unidadeOrigemTexto: 'GETEC - Gerencia de Tecnologia',
        unidadeDestinoTexto: 'Gerência de Licenciamento – GEASI',
        numeroChamado: '4496',
      ),
    ],
  );
}

void main() {
  group('PROMPT 11.1 — SeiImportController (nunca escreve, sempre leitura em lote)', () {
    test('fluxo completo: lê, extrai, cruza em lote e termina em revisão', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final extrator = _FakeExtractor(
        resultado: const SeiPdfLido(textoPorPagina: ['texto'], quantidadePaginas: 1, hashSha256: 'hash'),
      );
      final container = ProviderContainer(
        overrides: [
          seiPdfTextExtractorProvider.overrideWithValue(extrator),
          seiDocumentoParserProvider.overrideWithValue(_FakeParser(_documentoComDoisItens())),
          patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGeasi])),
          // Deliberadamente SEM override de `movimentacaoRepositoryProvider`
          // (seção 31): se o controller alguma vez lesse esse provider, o
          // provider padrão tentaria `Supabase.instance.client` e este
          // teste quebraria — a ausência de erro aqui É a prova de que o
          // caminho nunca toca a RPC de escrita.
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1, 2, 3]));

      final state = container.read(seiImportControllerProvider);
      expect(state.step, SeiImportStep.revisao);
      expect(state.resultado, isNotNull);
      expect(state.resultado!.totalItens, 2);
      // item 4157090: existe no InvTec, origem/destino conferem, tipo
      // compatível -> PRONTO. item 9999999: não encontrado -> BLOQUEADO.
      expect(state.resultado!.totalProntos, 1);
      expect(state.resultado!.totalBloqueados, 1);

      // seção 16: uma única consulta em lote, nunca uma por item.
      expect(patrimonioRepo.buscarPorNumerosPatrimonioCallCount, 1);
    });

    test('erro de leitura do PDF mantém o usuário no passo de seleção, com mensagem amigável', () async {
      final extrator = _FakeExtractor(erro: const SeiPdfLeituraException('O arquivo selecionado está vazio.'));
      final container = ProviderContainer(
        overrides: [
          seiPdfTextExtractorProvider.overrideWithValue(extrator),
          patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'vazio.pdf', bytes: Uint8List.fromList([]));

      final state = container.read(seiImportControllerProvider);
      expect(state.step, SeiImportStep.selecionarArquivo);
      expect(state.mensagemErro, 'O arquivo selecionado está vazio.');
      expect(state.resultado, isNull);
    });

    test('reiniciar() volta ao estado inicial, descartando o resultado anterior', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final container = ProviderContainer(
        overrides: [
          seiPdfTextExtractorProvider.overrideWithValue(
            _FakeExtractor(resultado: const SeiPdfLido(textoPorPagina: ['x'], quantidadePaginas: 1, hashSha256: 'h')),
          ),
          seiDocumentoParserProvider.overrideWithValue(_FakeParser(_documentoComDoisItens())),
          patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGeasi])),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));
      expect(container.read(seiImportControllerProvider).step, SeiImportStep.revisao);

      container.read(seiImportControllerProvider.notifier).reiniciar();

      final state = container.read(seiImportControllerProvider);
      expect(state.step, SeiImportStep.selecionarArquivo);
      expect(state.resultado, isNull);
    });

    test('filtrar() muda o filtro sem tocar no resultado já calculado', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final container = ProviderContainer(
        overrides: [
          seiPdfTextExtractorProvider.overrideWithValue(
            _FakeExtractor(resultado: const SeiPdfLido(textoPorPagina: ['x'], quantidadePaginas: 1, hashSha256: 'h')),
          ),
          seiDocumentoParserProvider.overrideWithValue(_FakeParser(_documentoComDoisItens())),
          patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGeasi])),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));
      final resultadoAntes = container.read(seiImportControllerProvider).resultado;

      container.read(seiImportControllerProvider.notifier).filtrar(SeiFiltroRevisao.bloqueados);

      final state = container.read(seiImportControllerProvider);
      expect(state.filtro, SeiFiltroRevisao.bloqueados);
      expect(state.resultado, same(resultadoAntes));
    });
  });
}
