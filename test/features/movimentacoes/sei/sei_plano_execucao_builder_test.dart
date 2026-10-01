import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_documento_analyzer.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_plano_execucao_builder.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_extraido.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_duplicidade.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_execucao_estado.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_extraido.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/setores/domain/setor.dart';

final _setorGetec = Setor(id: 'setor-getec', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _setorGeasi = Setor(id: 'setor-geasi', nome: 'Gerência de Licenciamento', sigla: 'GEASI', ativo: true, criadoEm: DateTime(2026, 1, 1));

PatrimonioDetalhe _patrimonio({
  String numero = '4157090',
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  String? responsavelAtual,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: 'id-$numero',
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: status,
      setorAtualId: 'setor-getec',
      responsavelAtual: responsavelAtual,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'Gerencia de Tecnologia',
  );
}

SeiItemExtraido _item({
  int linha = 1,
  String numero = '4157090',
  SeiConfianca confianca = SeiConfianca.alta,
}) {
  return SeiItemExtraido(
    linha: linha,
    paginaOrigem: 1,
    numeroPatrimonio: numero,
    equipamento: 'Monitor Positivo',
    unidadeOrigemTexto: 'GETEC - Gerencia de Tecnologia',
    unidadeDestinoTexto: 'Gerência de Licenciamento – GEASI',
    numeroChamado: '4556',
    confiancaPatrimonio: confianca,
  );
}

/// Estado "pronto para seleção" padrão dos testes: as duas decisões da
/// seção 4 (PROMPT 11.2.1) já resolvidas como "confirmado sem informação"
/// — o cenário mais comum no documento SEI real, que nunca informa
/// localização nem responsável de destino.
const _estadoAptoBase = SeiItemExecucaoEstado(
  selecionado: true,
  decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
  decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
);

void main() {
  group('PROMPT 11.2/11.2.1 — construirPlanoExecucao (somente leitura)', () {
    test('item PRONTO, selecionado e com as duas decisões resolvidas entra no plano', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        numeroDocumentoSei: '95955192',
        numeroDocumentoFormatado: '577/2026/SEMAD/GETEC-12014',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(resultado: resultado, execucao: {1: _estadoAptoBase});

      expect(plano.totalItens, 1);
      final planoItem = plano.itens.single;
      expect(planoItem.numeroPatrimonio, '4157090');
      expect(planoItem.destinoNome, 'Gerência de Licenciamento');
      expect(planoItem.localizacaoDestinoId, isNull);
      expect(planoItem.responsavelDestino, isNull);
      expect(planoItem.pendenciasDecisao, isNotEmpty);
      expect(planoItem.pendenciasDecisao.any((p) => p.contains('Localização de destino: confirmado')), isTrue);
    });

    test('item não selecionado nunca entra no plano', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(resultado: resultado, execucao: const {});
      expect(plano.totalItens, 0);
    });

    test('item BLOQUEADO nunca entra no plano, mesmo marcado selecionado por engano', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      // patrimônio não encontrado -> BLOQUEADO
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: const {},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(resultado: resultado, execucao: {1: _estadoAptoBase});
      expect(plano.totalItens, 0);
    });

    test('item de confiança MÉDIA sem aviso confirmado nunca entra no plano', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item(confianca: SeiConfianca.media)],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final planoSemConfirmar = construirPlanoExecucao(resultado: resultado, execucao: {1: _estadoAptoBase});
      expect(planoSemConfirmar.totalItens, 0);

      final planoComConfirmar = construirPlanoExecucao(
        resultado: resultado,
        execucao: {
          1: SeiItemExecucaoEstado(
            selecionado: _estadoAptoBase.selecionado,
            decisaoLocalizacao: _estadoAptoBase.decisaoLocalizacao,
            decisaoResponsavel: _estadoAptoBase.decisaoResponsavel,
            avisoConfirmado: true,
          ),
        },
      );
      expect(planoComConfirmar.totalItens, 1);
    });

    test('item marcado desatualizado pela revalidação nunca entra no plano', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(
        resultado: resultado,
        execucao: {
          1: SeiItemExecucaoEstado(
            selecionado: _estadoAptoBase.selecionado,
            decisaoLocalizacao: _estadoAptoBase.decisaoLocalizacao,
            decisaoResponsavel: _estadoAptoBase.decisaoResponsavel,
            desatualizado: true,
          ),
        },
      );
      expect(plano.totalItens, 0);
    });

    test(
      'PROMPT 11.2, seção 10 (retomada parcial): item já classificado como jaRegistrada nunca entra no plano',
      () {
        final documento = SeiDocumentoExtraido(
          nomeArquivo: 'doc.pdf',
          tamanhoBytes: 100,
          quantidadePaginas: 1,
          hashSha256: 'h',
          tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
          itens: [_item(linha: 1, numero: '4157090'), _item(linha: 2, numero: '4157082')],
        );
        final resultado = const SeiDocumentoAnalyzer().analisar(
          documento: documento,
          patrimoniosPorNumero: {'4157090': _patrimonio(), '4157082': _patrimonio(numero: '4157082')},
          setoresAtivos: [_setorGetec, _setorGeasi],
        );

        final plano = construirPlanoExecucao(
          resultado: resultado,
          execucao: {
            1: SeiItemExecucaoEstado(
              selecionado: true,
              decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
              decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
              duplicidade: const SeiDuplicidadeResultado(status: SeiDuplicidadeStatus.jaRegistrada, detalhe: 'já feito'),
            ),
            2: _estadoAptoBase,
          },
        );

        // Item 1 (já registrado) fica de fora; item 2 (pendente) continua no plano.
        expect(plano.totalItens, 1);
        expect(plano.itens.single.numeroPatrimonio, '4157082');
      },
    );

    test(
      'PROMPT 11.2.1, seção 5: possível duplicidade (sem resolução) também bloqueia — não só "já registrada"',
      () {
        final documento = SeiDocumentoExtraido(
          nomeArquivo: 'doc.pdf',
          tamanhoBytes: 100,
          quantidadePaginas: 1,
          hashSha256: 'h',
          tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
          itens: [_item()],
        );
        final resultado = const SeiDocumentoAnalyzer().analisar(
          documento: documento,
          patrimoniosPorNumero: {'4157090': _patrimonio()},
          setoresAtivos: [_setorGetec, _setorGeasi],
        );

        final plano = construirPlanoExecucao(
          resultado: resultado,
          execucao: {
            1: SeiItemExecucaoEstado(
              selecionado: true,
              decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
              decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
              duplicidade: const SeiDuplicidadeResultado(
                status: SeiDuplicidadeStatus.possivelDuplicidade,
                detalhe: 'destino diferente',
              ),
            ),
          },
        );

        expect(plano.totalItens, 0);
      },
    );

    test('PROMPT 11.2.1, seção 5: decisão de localização PENDENTE bloqueia o item, mesmo selecionado', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(
        resultado: resultado,
        execucao: {
          1: const SeiItemExecucaoEstado(
            selecionado: true,
            decisaoLocalizacao: SeiDecisaoCampo.pendente,
            decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
          ),
        },
      );

      expect(plano.totalItens, 0);
    });

    test('PROMPT 11.2.1, seção 5: decisão de responsável PENDENTE bloqueia o item, mesmo selecionado', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio()},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(
        resultado: resultado,
        execucao: {
          1: const SeiItemExecucaoEstado(
            selecionado: true,
            decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
            decisaoResponsavel: SeiDecisaoCampo.pendente,
          ),
        },
      );

      expect(plano.totalItens, 0);
    });

    test(
      'PROMPT 11.2.1, seção 4: decisão DEFINIDA (localização/responsável escolhidos) aparece no plano com os valores exatos',
      () {
        final documento = SeiDocumentoExtraido(
          nomeArquivo: 'doc.pdf',
          tamanhoBytes: 100,
          quantidadePaginas: 1,
          hashSha256: 'h',
          tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
          itens: [_item()],
        );
        final resultado = const SeiDocumentoAnalyzer().analisar(
          documento: documento,
          patrimoniosPorNumero: {'4157090': _patrimonio()},
          setoresAtivos: [_setorGetec, _setorGeasi],
        );

        final plano = construirPlanoExecucao(
          resultado: resultado,
          execucao: {
            1: const SeiItemExecucaoEstado(
              selecionado: true,
              decisaoLocalizacao: SeiDecisaoCampo.definido,
              localizacaoDestinoId: 'loc-1',
              localizacaoDestinoNome: 'Datacenter',
              decisaoResponsavel: SeiDecisaoCampo.definido,
              responsavelDestino: 'Fulano de Tal',
            ),
          },
        );

        expect(plano.totalItens, 1);
        final item = plano.itens.single;
        expect(item.localizacaoDestinoId, 'loc-1');
        expect(item.localizacaoDestinoNome, 'Datacenter');
        expect(item.responsavelDestino, 'Fulano de Tal');
        expect(item.statusEsperadoAposOperacao, PatrimonioStatus.emUso);
        expect(item.pendenciasDecisao, isEmpty);
      },
    );

    test('responsável atual preenchido + decisão "sem informação" gera pendência de alerta específica', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item()],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio(status: PatrimonioStatus.emUso, responsavelAtual: 'Fulano')},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      final plano = construirPlanoExecucao(resultado: resultado, execucao: {1: _estadoAptoBase});

      expect(plano.itens.single.pendenciasDecisao.any((p) => p.contains('APAGAR o responsável')), isTrue);
      expect(plano.itens.single.statusEsperadoAposOperacao, PatrimonioStatus.disponivel);
    });
  });

  group('PROMPT 11.2.1, seção 5 — itensElegiveis (aptos, independente de seleção)', () {
    test('conta itens tecnicamente aptos mesmo sem terem sido selecionados ainda', () {
      final documento = SeiDocumentoExtraido(
        nomeArquivo: 'doc.pdf',
        tamanhoBytes: 100,
        quantidadePaginas: 1,
        hashSha256: 'h',
        tipoMovimentacaoInferido: MovimentacaoTipo.transferencia,
        itens: [_item(linha: 1, numero: '4157090'), _item(linha: 2, numero: '4157082')],
      );
      final resultado = const SeiDocumentoAnalyzer().analisar(
        documento: documento,
        patrimoniosPorNumero: {'4157090': _patrimonio(), '4157082': _patrimonio(numero: '4157082')},
        setoresAtivos: [_setorGetec, _setorGeasi],
      );

      // Nenhum selecionado — só o item 1 tem as decisões resolvidas.
      final aptos = itensElegiveis(
        resultado: resultado,
        execucao: {
          1: const SeiItemExecucaoEstado(
            decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
            decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
          ),
        },
      );

      expect(aptos, hasLength(1));
      expect(aptos.single.item.numeroPatrimonio, '4157090');
    });
  });
}
