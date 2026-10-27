import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_comparacao.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_csv_linha.dart';
import 'package:invtec/features/setores/domain/setor.dart';

Setor _setor({required String id, required String nome, String? sigla, bool ativo = true}) => Setor(
  id: id,
  nome: nome,
  sigla: sigla,
  ativo: ativo,
  criadoEm: DateTime(2026, 1, 1),
);

final _getec = _setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC');
final _cimehgo = _setor(id: 'setor-cimehgo', nome: 'Centro de Informações Meteorológicas', sigla: 'CIMEHGO');
final _gecad = _setor(id: 'setor-gecad', nome: 'Gerência do Contencioso Administrativo', sigla: 'GECAD');
final _gevecInativo = _setor(id: 'setor-gevec', nome: 'Gerência de Economia Verde', sigla: 'GEVEC', ativo: false);

final _setores = [_getec, _cimehgo, _gecad, _gevecInativo];

PatrimonioDetalhe _patrimonio({
  required String id,
  required String numero,
  required String setorAtualId,
  DateTime? atualizadoEm,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.emUso,
      setorAtualId: setorAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: atualizadoEm ?? DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'GETEC',
  );
}

RetificacaoCsvLinha _linha({
  int numeroLinha = 2,
  required String patrimonioId,
  required String tombamentoAtual,
  String setorAtualTexto = 'GETEC',
  required String siglaDestino,
  String nomeDestino = '',
}) {
  return RetificacaoCsvLinha(
    numeroLinha: numeroLinha,
    patrimonioId: patrimonioId,
    tombamentoOficial: tombamentoAtual,
    tombamentoAtualInvtec: tombamentoAtual,
    descricaoOficial: 'Descrição',
    setorAtualTexto: setorAtualTexto,
    unidadeCorretaSigla: siglaDestino,
    unidadeCorretaNome: nomeDestino,
  );
}

void main() {
  group('RetificacaoComparador', () {
    test('linha válida com destino diferente do atual: pronto', () {
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _getec.id);
      final linha = _linha(patrimonioId: 'p1', tombamentoAtual: '3636982', siglaDestino: 'CIMEHGO');

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      expect(lote.resumo.prontos, 1);
      expect(lote.resumo.totalLinhas, 1);
      final item = lote.itens.single;
      expect(item.classificacao, ClassificacaoRetificacao.pronto);
      expect(item.setorDestinoId, _cimehgo.id);
      expect(lote.itensProntos, hasLength(1));
    });

    test('zeros à esquerda no tombamento esperado não bloqueiam (equivalência normalizada)', () {
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _getec.id);
      // CSV traz com zero à esquerda, InvTec guarda sem — mesma identidade.
      final linha = _linha(patrimonioId: 'p1', tombamentoAtual: '03636982', siglaDestino: 'CIMEHGO');

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      expect(lote.itens.single.classificacao, ClassificacaoRetificacao.pronto);
    });

    test('patrimônio não encontrado pelo UUID: bloqueado, nunca presumido como inexistente no mundo real', () {
      final linha = _linha(patrimonioId: 'nao-existe', tombamentoAtual: '123', siglaDestino: 'CIMEHGO');

      final lote = RetificacaoComparador.comparar(linhas: [linha], patrimoniosPorId: const {}, setores: _setores);

      final item = lote.itens.single;
      expect(item.classificacao, ClassificacaoRetificacao.patrimonioNaoEncontrado);
      expect(item.motivoBloqueio, contains('nao-existe'));
      expect(lote.resumo.totalBloqueados, 1);
      expect(lote.itensProntos, isEmpty);
    });

    test('tombamento real divergente do snapshot exportado: bloqueado, nunca presumido igual', () {
      final detalhe = _patrimonio(id: 'p1', numero: '9999999', setorAtualId: _getec.id);
      final linha = _linha(patrimonioId: 'p1', tombamentoAtual: '3636982', siglaDestino: 'CIMEHGO');

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      final item = lote.itens.single;
      expect(item.classificacao, ClassificacaoRetificacao.tombamentoDivergente);
      expect(item.motivoBloqueio, contains('3636982'));
      expect(item.motivoBloqueio, contains('9999999'));
    });

    test('unidade atual divergente do texto da planilha: bloqueado (snapshot de setor desatualizado)', () {
      // patrimônio real já está em CIMEHGO, mas a planilha ainda acha que
      // está em GETEC — sinal de que o plano está desatualizado para esta
      // linha específica.
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _cimehgo.id);
      final linha = _linha(
        patrimonioId: 'p1',
        tombamentoAtual: '3636982',
        setorAtualTexto: 'GETEC',
        siglaDestino: 'GECAD',
      );

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      expect(lote.itens.single.classificacao, ClassificacaoRetificacao.setorAtualDivergente);
    });

    test('unidade de destino não cadastrada: bloqueada, nunca resolvida por aproximação', () {
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _getec.id);
      final linha = _linha(
        patrimonioId: 'p1',
        tombamentoAtual: '3636982',
        siglaDestino: 'UNIDADE-INEXISTENTE',
      );

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      final item = lote.itens.single;
      expect(item.classificacao, ClassificacaoRetificacao.unidadeDestinoNaoCadastrada);
      expect(item.setorDestinoId, isNull);
    });

    test('unidade de destino cadastrada mas inativa: bloqueada', () {
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _getec.id);
      final linha = _linha(patrimonioId: 'p1', tombamentoAtual: '3636982', siglaDestino: 'GEVEC');

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      expect(lote.itens.single.classificacao, ClassificacaoRetificacao.unidadeDestinoInativa);
    });

    test('patrimônio já pertence à unidade correta: informativo, nunca um bloqueio nem um "pronto"', () {
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _cimehgo.id);
      final linha = _linha(
        patrimonioId: 'p1',
        tombamentoAtual: '3636982',
        setorAtualTexto: 'CIMEHGO',
        siglaDestino: 'CIMEHGO',
      );

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: _setores,
      );

      final item = lote.itens.single;
      expect(item.classificacao, ClassificacaoRetificacao.jaNaUnidadeCorreta);
      expect(item.classificacao.ehBloqueio, isFalse);
      expect(lote.resumo.jaNaUnidadeCorreta, 1);
      expect(lote.resumo.totalBloqueados, 0);
      expect(lote.itensProntos, isEmpty);
    });

    test('resolve a unidade de destino pelo NOME quando a sigla não bate com nenhum setor', () {
      final setorSemSigla = _setor(id: 'setor-sem-sigla', nome: 'Gerência Sem Sigla');
      final detalhe = _patrimonio(id: 'p1', numero: '3636982', setorAtualId: _getec.id);
      final linha = RetificacaoCsvLinha(
        numeroLinha: 2,
        patrimonioId: 'p1',
        tombamentoOficial: '3636982',
        tombamentoAtualInvtec: '3636982',
        descricaoOficial: 'Descrição',
        setorAtualTexto: 'GETEC',
        unidadeCorretaSigla: '', // sem sigla na planilha para esta unidade
        unidadeCorretaNome: 'Gerência Sem Sigla',
      );

      final lote = RetificacaoComparador.comparar(
        linhas: [linha],
        patrimoniosPorId: {'p1': detalhe},
        setores: [..._setores, setorSemSigla],
      );

      final item = lote.itens.single;
      expect(item.classificacao, ClassificacaoRetificacao.pronto);
      expect(item.setorDestinoId, setorSemSigla.id);
    });

    test('resumo agrega corretamente um lote misto', () {
      final detalhePronto = _patrimonio(id: 'p1', numero: '1', setorAtualId: _getec.id);
      final detalheCorreto = _patrimonio(id: 'p2', numero: '2', setorAtualId: _cimehgo.id);

      final lote = RetificacaoComparador.comparar(
        linhas: [
          _linha(patrimonioId: 'p1', tombamentoAtual: '1', siglaDestino: 'CIMEHGO'),
          _linha(
            patrimonioId: 'p2',
            tombamentoAtual: '2',
            setorAtualTexto: 'CIMEHGO',
            siglaDestino: 'CIMEHGO',
          ),
          _linha(patrimonioId: 'nao-existe', tombamentoAtual: '3', siglaDestino: 'CIMEHGO'),
        ],
        patrimoniosPorId: {'p1': detalhePronto, 'p2': detalheCorreto},
        setores: _setores,
      );

      expect(lote.resumo.totalLinhas, 3);
      expect(lote.resumo.prontos, 1);
      expect(lote.resumo.jaNaUnidadeCorreta, 1);
      expect(lote.resumo.totalBloqueados, 1);
      expect(
        lote.resumo.bloqueadosPorMotivo[ClassificacaoRetificacao.patrimonioNaoEncontrado],
        1,
      );
    });
  });
}
