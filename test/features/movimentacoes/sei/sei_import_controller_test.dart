import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/data/movimentacao_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao_listagem_item.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_parser.dart';
import 'package:invtec/features/movimentacoes/sei/data/sei_pdf_text_extractor.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_duplicidade.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_estagio_preparacao.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_import_controller.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../patrimonios/fake_patrimonio_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_movimentacao_repository.dart';

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

PatrimonioDetalhe _patrimonio(
  String numero, {
  String setorAtualId = 'setor-getec',
  PatrimonioStatus status = PatrimonioStatus.disponivel,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'id-$numero',
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: setorAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'Gerencia de Tecnologia',
  );
}

SeiDocumentoExtraido _documentoComDoisItens({SeiConfianca confiancaSegundoItem = SeiConfianca.alta}) {
  return SeiDocumentoExtraido(
    nomeArquivo: 'despacho.pdf',
    tamanhoBytes: 500,
    quantidadePaginas: 1,
    hashSha256: 'hash-fake',
    numeroDocumentoSei: '95955192',
    numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
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
        confiancaPatrimonio: confiancaSegundoItem,
      ),
    ],
  );
}

// `Override` (o tipo esperado por `ProviderContainer(overrides: ...)`) não é
// exportado publicamente pelo barril de `flutter_riverpod` nesta versão —
// só pode ser usado por inferência, nunca escrito explicitamente aqui.
// ignore: strict_top_level_inference
_overridesPadrao({
  required FakePatrimonioRepository patrimonioRepo,
  FakeMovimentacaoRepository? movimentacaoRepo,
  SeiPdfLido? pdfLido,
  SeiDocumentoExtraido? documento,
}) {
  return [
    seiPdfTextExtractorProvider.overrideWithValue(
      _FakeExtractor(resultado: pdfLido ?? const SeiPdfLido(textoPorPagina: ['texto'], quantidadePaginas: 1, hashSha256: 'hash')),
    ),
    if (documento != null) seiDocumentoParserProvider.overrideWithValue(_FakeParser(documento)),
    patrimonioRepositoryProvider.overrideWithValue(patrimonioRepo),
    setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_setorGetec, _setorGeasi])),
    movimentacaoRepositoryProvider.overrideWithValue(movimentacaoRepo ?? FakeMovimentacaoRepository()),
  ];
}

void main() {
  group('SeiImportController (nunca registra, só lê em lote)', () {
    test('fluxo completo: lê, extrai, cruza em lote, checa duplicidade e termina em revisão', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final movimentacaoRepo = FakeMovimentacaoRepository();
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          movimentacaoRepo: movimentacaoRepo,
          documento: _documentoComDoisItens(),
        ),
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

      // Uma única consulta em lote a patrimônios.
      expect(patrimonioRepo.buscarPorNumerosPatrimonioCallCount, 1);
      // Uma única LEITURA em lote, via filtro
      // exato no banco (nunca `.listar` com busca OR genérica) — nunca uma
      // por item.
      expect(movimentacaoRepo.listarPorNumeroDocumentoCallCount, 1);
      expect(movimentacaoRepo.listarCallCount, 0);
      // E, acima de tudo: NENHUMA escrita, em nenhum momento deste fluxo.
      expect(movimentacaoRepo.registrarCallCount, 0);
    });

    test(
      'documento com todos os itens PRONTO continua em estágio "patrimoniosConferidos"/'
      '"aptoParaExecucao" — NUNCA "autorizado" sem confirmação explícita do usuário',
      () async {
        final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090'), _patrimonio('9999999')]);
        final container = ProviderContainer(
          overrides: _overridesPadrao(patrimonioRepo: patrimonioRepo, documento: _documentoComDoisItens()),
        );
        addTearDown(container.dispose);

        await container
            .read(seiImportControllerProvider.notifier)
            .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

        final state = container.read(seiImportControllerProvider);
        expect(state.resultado!.totalBloqueados, 0);
        expect(state.autorizacaoConfirmada, isFalse);
        expect(state.estagio, isNot(SeiEstagioPreparacao.autorizado));

        container.read(seiImportControllerProvider.notifier).confirmarAutorizacao(true);
        expect(container.read(seiImportControllerProvider).estagio, SeiEstagioPreparacao.autorizado);
      },
    );

    test('histórico com movimentação idêntica é classificado como possível duplicidade/já registrada', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final movimentacaoRepo = FakeMovimentacaoRepository(
        itens: [
          MovimentacaoListagemItem(
            id: 'mov-1',
            tipo: MovimentacaoTipo.transferencia,
            patrimonioId: 'id-4157090',
            setorDestinoId: 'setor-geasi',
            numeroChamado: '4556',
            numeroDocumento: '95955192',
            dataMovimentacao: DateTime(2026, 1, 1),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          movimentacaoRepo: movimentacaoRepo,
          documento: SeiDocumentoExtraido(
            nomeArquivo: 'despacho.pdf',
            tamanhoBytes: 500,
            quantidadePaginas: 1,
            hashSha256: 'hash-fake',
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
            ],
          ),
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

      final state = container.read(seiImportControllerProvider);
      expect(state.execucao[1]?.duplicidade?.status, SeiDuplicidadeStatus.jaRegistrada);
    });

    test('erro de leitura do PDF mantém o usuário no passo de seleção, com mensagem amigável', () async {
      final extrator = _FakeExtractor(erro: const SeiPdfLeituraException('O arquivo selecionado está vazio.'));
      final container = ProviderContainer(
        overrides: [
          seiPdfTextExtractorProvider.overrideWithValue(extrator),
          patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository()),
          movimentacaoRepositoryProvider.overrideWithValue(FakeMovimentacaoRepository()),
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
        overrides: _overridesPadrao(patrimonioRepo: patrimonioRepo, documento: _documentoComDoisItens()),
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
        overrides: _overridesPadrao(patrimonioRepo: patrimonioRepo, documento: _documentoComDoisItens()),
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

    test('alternarSelecao nunca liga uma linha BLOQUEADA', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]); // 9999999 não existe -> bloqueado
      final container = ProviderContainer(
        overrides: _overridesPadrao(patrimonioRepo: patrimonioRepo, documento: _documentoComDoisItens()),
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

      final notifier = container.read(seiImportControllerProvider.notifier);
      // Localização/responsável de destino
      // continuam PENDENTES até decisão explícita — precisa resolver as
      // duas antes de a linha 1 (PRONTO) virar selecionável.
      notifier.confirmarSemLocalizacao(1);
      notifier.confirmarSemResponsavel(1);
      notifier.alternarSelecao(1); // PRONTO + decisões resolvidas -> pode selecionar
      notifier.alternarSelecao(2); // BLOQUEADO -> nunca liga, mesmo com decisões pendentes

      final state = container.read(seiImportControllerProvider);
      expect(state.execucao[1]?.selecionado, isTrue);
      expect(state.execucao[2]?.selecionado ?? false, isFalse);
    });

    test('linha de confiança MÉDIA só pode ser selecionada depois de confirmarAviso', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090'), _patrimonio('9999999')]);
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          documento: _documentoComDoisItens(confiancaSegundoItem: SeiConfianca.media),
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

      final notifier = container.read(seiImportControllerProvider.notifier);
      notifier.confirmarSemLocalizacao(2);
      notifier.confirmarSemResponsavel(2);

      notifier.alternarSelecao(2);
      expect(container.read(seiImportControllerProvider).execucao[2]?.selecionado ?? false, isFalse);

      notifier.confirmarAviso(2, true);
      notifier.alternarSelecao(2);
      expect(container.read(seiImportControllerProvider).execucao[2]?.selecionado, isTrue);

      // revogar a confirmação também tira da seleção (seção 7)
      notifier.confirmarAviso(2, false);
      expect(container.read(seiImportControllerProvider).execucao[2]?.selecionado, isFalse);
    });

    test('plano gerado a partir da seleção nunca chama registrarMovimentacao', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final movimentacaoRepo = FakeMovimentacaoRepository();
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          movimentacaoRepo: movimentacaoRepo,
          documento: SeiDocumentoExtraido(
            nomeArquivo: 'despacho.pdf',
            tamanhoBytes: 500,
            quantidadePaginas: 1,
            hashSha256: 'hash-fake',
            numeroDocumentoSei: '95955192',
            numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
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
          ),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(seiImportControllerProvider.notifier);
      await notifier.selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));
      notifier.confirmarSemLocalizacao(1);
      notifier.confirmarSemResponsavel(1);
      notifier.alternarSelecao(1);

      final plano = container.read(seiImportControllerProvider).plano;
      expect(plano.totalItens, 1);
      expect(plano.itens.single.numeroPatrimonio, '4157090');
      expect(movimentacaoRepo.registrarCallCount, 0);
    });

    test('revalidar() detecta mudança de status/setor e marca a linha desatualizada, sem selecioná-la', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          documento: SeiDocumentoExtraido(
            nomeArquivo: 'despacho.pdf',
            tamanhoBytes: 500,
            quantidadePaginas: 1,
            hashSha256: 'hash-fake',
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
            ],
          ),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(seiImportControllerProvider.notifier);
      await notifier.selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));
      notifier.confirmarSemLocalizacao(1);
      notifier.confirmarSemResponsavel(1);
      notifier.alternarSelecao(1);
      expect(container.read(seiImportControllerProvider).execucao[1]?.selecionado, isTrue);

      // Estado mudou no InvTec desde a análise (ex.: alguém já moveu o
      // patrimônio para EM_MANUTENCAO por fora deste fluxo).
      patrimonioRepo.substituirDetalhe(_patrimonio('4157090', status: PatrimonioStatus.emManutencao));

      await notifier.revalidar();

      final state = container.read(seiImportControllerProvider);
      expect(state.execucao[1]?.desatualizado, isTrue);
      expect(state.execucao[1]?.selecionado, isFalse);
    });

    test('ausência de dependência executável de escrita — nenhuma chamada a registrarMovimentacao em todo o fluxo', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final movimentacaoRepo = FakeMovimentacaoRepository();
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          movimentacaoRepo: movimentacaoRepo,
          documento: _documentoComDoisItens(),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(seiImportControllerProvider.notifier);
      await notifier.selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));
      notifier.alternarSelecao(1);
      notifier.confirmarAutorizacao(true);
      await notifier.revalidar();

      expect(movimentacaoRepo.registrarCallCount, 0);
    });

    test('busca exata por número SEI — não confunde com substring de outro documento', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      final movimentacaoRepo = FakeMovimentacaoRepository(
        itens: [
          // numero_documento contém o alvo como SUBSTRING, mas não é igual
          // — uma busca OR/ilike (a antiga implementação) o encontraria por
          // engano; a busca exata (seção 2) não pode.
          MovimentacaoListagemItem(
            id: 'mov-outro-doc',
            tipo: MovimentacaoTipo.transferencia,
            patrimonioId: 'id-4157090',
            numeroDocumento: '9595519299999',
            dataMovimentacao: DateTime(2026, 1, 1),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          movimentacaoRepo: movimentacaoRepo,
          documento: SeiDocumentoExtraido(
            nomeArquivo: 'despacho.pdf',
            tamanhoBytes: 500,
            quantidadePaginas: 1,
            hashSha256: 'hash-fake',
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
            ],
          ),
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

      final state = container.read(seiImportControllerProvider);
      expect(state.execucao[1]?.duplicidade?.status, SeiDuplicidadeStatus.semCorrespondencia);
    });

    test('mais de 200 movimentações vinculadas ao documento — todas consideradas, sem limite arbitrário', () async {
      final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
      // 250 movimentações "de ruído" (outro documento) + 1 movimentação
      // relevante posicionada DEPOIS delas (seção 8: "duplicidade fora da
      // primeira página") — nada pode ser descartado silenciosamente.
      final ruido = List.generate(
        250,
        (i) => MovimentacaoListagemItem(
          id: 'mov-ruido-$i',
          tipo: MovimentacaoTipo.transferencia,
          patrimonioId: 'id-4157090',
          numeroDocumento: 'outro-documento-$i',
          dataMovimentacao: DateTime(2026, 1, 1),
        ),
      );
      final movimentacaoRepo = FakeMovimentacaoRepository(
        itens: [
          ...ruido,
          MovimentacaoListagemItem(
            id: 'mov-relevante',
            tipo: MovimentacaoTipo.transferencia,
            patrimonioId: 'id-4157090',
            setorDestinoId: 'setor-geasi',
            numeroChamado: '4556',
            numeroDocumento: '95955192',
            dataMovimentacao: DateTime(2026, 1, 1),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: _overridesPadrao(
          patrimonioRepo: patrimonioRepo,
          movimentacaoRepo: movimentacaoRepo,
          documento: SeiDocumentoExtraido(
            nomeArquivo: 'despacho.pdf',
            tamanhoBytes: 500,
            quantidadePaginas: 1,
            hashSha256: 'hash-fake',
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
            ],
          ),
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(seiImportControllerProvider.notifier)
          .selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

      final state = container.read(seiImportControllerProvider);
      expect(state.execucao[1]?.duplicidade?.status, SeiDuplicidadeStatus.jaRegistrada);
    });

    test(
      'autorização geral do documento NÃO elimina pendências individuais (decisão de localização pendente)',
      () async {
        final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
        final container = ProviderContainer(
          overrides: _overridesPadrao(patrimonioRepo: patrimonioRepo, documento: _documentoComDoisItens()),
        );
        addTearDown(container.dispose);

        final notifier = container.read(seiImportControllerProvider.notifier);
        await notifier.selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));

        // Autoriza o documento inteiro SEM resolver nenhuma decisão
        // individual — o item 1 (PRONTO) continua tecnicamente inapto.
        notifier.confirmarAutorizacao(true);

        final state = container.read(seiImportControllerProvider);
        expect(state.autorizacaoConfirmada, isTrue);
        expect(state.itensAptos, isEmpty);
        // e, por decorrência, nem consegue ser selecionado:
        notifier.alternarSelecao(1);
        expect(container.read(seiImportControllerProvider).execucao[1]?.selecionado ?? false, isFalse);
      },
    );

    test(
      'revalidação identifica uma nova movimentação registrada por outro usuário entretanto',
      () async {
        final patrimonioRepo = FakePatrimonioRepository(itens: [_patrimonio('4157090')]);
        final movimentacaoRepo = FakeMovimentacaoRepository();
        final container = ProviderContainer(
          overrides: _overridesPadrao(
            patrimonioRepo: patrimonioRepo,
            movimentacaoRepo: movimentacaoRepo,
            documento: SeiDocumentoExtraido(
              nomeArquivo: 'despacho.pdf',
              tamanhoBytes: 500,
              quantidadePaginas: 1,
              hashSha256: 'hash-fake',
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
              ],
            ),
          ),
        );
        addTearDown(container.dispose);

        final notifier = container.read(seiImportControllerProvider.notifier);
        await notifier.selecionarArquivo(nomeArquivo: 'despacho.pdf', bytes: Uint8List.fromList([1]));
        expect(container.read(seiImportControllerProvider).execucao[1]?.duplicidade?.status, SeiDuplicidadeStatus.semCorrespondencia);

        notifier.confirmarSemLocalizacao(1);
        notifier.confirmarSemResponsavel(1);
        notifier.alternarSelecao(1);
        expect(container.read(seiImportControllerProvider).execucao[1]?.selecionado, isTrue);

        // Entre a análise original e a revalidação, OUTRO usuário registrou
        // a movimentação deste item para o mesmo documento — a revalidação
        // precisa repetir a consulta de duplicidade INTEIRA (nunca
        // reaproveitar o resultado anterior) e detectar isso.
        movimentacaoRepo.adicionarMovimentacao(
          MovimentacaoListagemItem(
            id: 'mov-outro-usuario',
            tipo: MovimentacaoTipo.transferencia,
            patrimonioId: 'id-4157090',
            setorDestinoId: 'setor-geasi',
            numeroChamado: '4556',
            numeroDocumento: '95955192',
            dataMovimentacao: DateTime(2026, 1, 1),
          ),
        );

        await notifier.revalidar();

        final state = container.read(seiImportControllerProvider);
        expect(state.execucao[1]?.duplicidade?.status, SeiDuplicidadeStatus.jaRegistrada);
        expect(state.execucao[1]?.desatualizado, isTrue);
        expect(state.execucao[1]?.selecionado, isFalse);
      },
    );
  });
}
