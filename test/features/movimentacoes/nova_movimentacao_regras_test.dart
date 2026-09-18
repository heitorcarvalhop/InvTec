import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/presentation/nova_movimentacao_regras.dart';
import 'package:invtec/features/movimentacoes/presentation/widgets/nova_movimentacao/nova_movimentacao_rascunho.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';

Patrimonio _patrimonio({
  PatrimonioStatus status = PatrimonioStatus.disponivel,
  String setorAtualId = 'setor-atual',
  String? responsavelAtual,
}) {
  return Patrimonio(
    id: 'patrimonio-1',
    tipoId: 'tipo-1',
    status: status,
    setorAtualId: setorAtualId,
    responsavelAtual: responsavelAtual,
    dataCadastro: DateTime(2026, 1, 1),
    atualizadoEm: DateTime(2026, 1, 1),
  );
}

void main() {
  group('PROMPT 10.2 — tiposCompativeisComStatus (matriz de transição, só UX)', () {
    test('DISPONIVEL e EM_USO oferecem os mesmos 8 tipos', () {
      expect(tiposCompativeisComStatus(PatrimonioStatus.disponivel), tiposCompativeisComStatus(PatrimonioStatus.emUso));
      expect(tiposCompativeisComStatus(PatrimonioStatus.disponivel), isNot(contains(MovimentacaoTipo.devolucao)));
      expect(tiposCompativeisComStatus(PatrimonioStatus.disponivel), isNot(contains(MovimentacaoTipo.retornoManutencao)));
    });

    test('EMPRESTADO só oferece Devolução, Ajuste e Baixa', () {
      expect(
        tiposCompativeisComStatus(PatrimonioStatus.emprestado),
        [MovimentacaoTipo.devolucao, MovimentacaoTipo.ajusteInventario, MovimentacaoTipo.baixa],
      );
    });

    test('EM_MANUTENCAO só oferece Retorno de manutenção, Ajuste e Baixa', () {
      expect(
        tiposCompativeisComStatus(PatrimonioStatus.emManutencao),
        [MovimentacaoTipo.retornoManutencao, MovimentacaoTipo.ajusteInventario, MovimentacaoTipo.baixa],
      );
    });

    test('BAIXADO só oferece Ajuste de inventário', () {
      expect(tiposCompativeisComStatus(PatrimonioStatus.baixado), [MovimentacaoTipo.ajusteInventario]);
    });
  });

  group('PROMPT 10.2 — regras por tipo (docs/database.md, "Regras por tipo")', () {
    test('destino obrigatório: ENTRADA/SAIDA/TRANSFERENCIA/EMPRESTIMO/DEVOLUCAO/MANUTENCAO/RETORNO_MANUTENCAO', () {
      for (final tipo in [
        MovimentacaoTipo.entrada,
        MovimentacaoTipo.saida,
        MovimentacaoTipo.transferencia,
        MovimentacaoTipo.emprestimo,
        MovimentacaoTipo.devolucao,
        MovimentacaoTipo.manutencao,
        MovimentacaoTipo.retornoManutencao,
      ]) {
        expect(tipoExigeDestino(tipo), isTrue, reason: '$tipo');
        expect(tipoProibeDestino(tipo), isFalse, reason: '$tipo');
      }
    });

    test('destino proibido: BAIXA e ALTERACAO_RESPONSAVEL', () {
      for (final tipo in [MovimentacaoTipo.baixa, MovimentacaoTipo.alteracaoResponsavel]) {
        expect(tipoExigeDestino(tipo), isFalse, reason: '$tipo');
        expect(tipoProibeDestino(tipo), isTrue, reason: '$tipo');
      }
    });

    test('destino opcional: só AJUSTE_INVENTARIO', () {
      expect(tipoDestinoOpcional(MovimentacaoTipo.ajusteInventario), isTrue);
      expect(tipoExigeDestino(MovimentacaoTipo.ajusteInventario), isFalse);
      expect(tipoProibeDestino(MovimentacaoTipo.ajusteInventario), isFalse);
    });

    test('responsável obrigatório: EMPRESTIMO e ALTERACAO_RESPONSAVEL', () {
      expect(tipoExigeResponsavel(MovimentacaoTipo.emprestimo), isTrue);
      expect(tipoExigeResponsavel(MovimentacaoTipo.alteracaoResponsavel), isTrue);
      expect(tipoExigeResponsavel(MovimentacaoTipo.transferencia), isFalse);
    });

    test('responsável proibido: BAIXA e AJUSTE_INVENTARIO', () {
      expect(tipoProibeResponsavel(MovimentacaoTipo.baixa), isTrue);
      expect(tipoProibeResponsavel(MovimentacaoTipo.ajusteInventario), isTrue);
      expect(tipoProibeResponsavel(MovimentacaoTipo.transferencia), isFalse);
    });

    test('localização permitida para todos exceto BAIXA e ALTERACAO_RESPONSAVEL', () {
      for (final tipo in MovimentacaoTipo.values) {
        final permite = tipo != MovimentacaoTipo.baixa && tipo != MovimentacaoTipo.alteracaoResponsavel;
        expect(tipoPermiteLocalizacao(tipo), permite, reason: '$tipo');
      }
    });

    test('limpar localização só é permitido em AJUSTE_INVENTARIO', () {
      for (final tipo in MovimentacaoTipo.values) {
        expect(tipoPermiteLimparLocalizacao(tipo), tipo == MovimentacaoTipo.ajusteInventario, reason: '$tipo');
      }
    });
  });

  group('PROMPT 10.2.2 — tipoExigeDestinoDiferente (RPC real auditada em produção)', () {
    test('ENTRADA permanece disponível para DISPONIVEL', () {
      expect(tiposCompativeisComStatus(PatrimonioStatus.disponivel), contains(MovimentacaoTipo.entrada));
    });

    test('ENTRADA permanece disponível para EM_USO', () {
      expect(tiposCompativeisComStatus(PatrimonioStatus.emUso), contains(MovimentacaoTipo.entrada));
    });

    test('tipos físicos não aceitam setor atual como destino', () {
      for (final tipo in [
        MovimentacaoTipo.entrada,
        MovimentacaoTipo.saida,
        MovimentacaoTipo.emprestimo,
        MovimentacaoTipo.devolucao,
        MovimentacaoTipo.manutencao,
        MovimentacaoTipo.retornoManutencao,
      ]) {
        expect(tipoExigeDestinoDiferente(tipo), isTrue, reason: '$tipo');
      }
    });

    test('TRANSFERENCIA é a única exceção — mesmo setor é "movimentação interna", não erro', () {
      expect(tipoExigeDestinoDiferente(MovimentacaoTipo.transferencia), isFalse);
    });

    test('BAIXA/AJUSTE_INVENTARIO/ALTERACAO_RESPONSAVEL não exigem (nem aceitam) destino_id', () {
      for (final tipo in [
        MovimentacaoTipo.baixa,
        MovimentacaoTipo.ajusteInventario,
        MovimentacaoTipo.alteracaoResponsavel,
      ]) {
        expect(tipoExigeDestinoDiferente(tipo), isFalse, reason: '$tipo');
      }
    });
  });

  group('PROMPT 10.2.2 — ajusteInventarioTrocouSetor', () {
    test('destino nulo ("Manter o setor atual"): não trocou', () {
      expect(ajusteInventarioTrocouSetor(destinoId: null, setorAtualId: 'setor-a'), isFalse);
    });

    test('destino explicitamente igual ao atual: não trocou', () {
      expect(ajusteInventarioTrocouSetor(destinoId: 'setor-a', setorAtualId: 'setor-a'), isFalse);
    });

    test('destino diferente do atual: trocou', () {
      expect(ajusteInventarioTrocouSetor(destinoId: 'setor-b', setorAtualId: 'setor-a'), isTrue);
    });
  });

  group('PROMPT 10.2 — ehTransferenciaInterna (TRANSFERENCIA sem novo enum)', () {
    test('destino igual ao setor atual em TRANSFERENCIA é interna', () {
      expect(
        ehTransferenciaInterna(tipo: MovimentacaoTipo.transferencia, destinoId: 'setor-a', setorAtualId: 'setor-a'),
        isTrue,
      );
    });

    test('destino diferente do setor atual em TRANSFERENCIA não é interna', () {
      expect(
        ehTransferenciaInterna(tipo: MovimentacaoTipo.transferencia, destinoId: 'setor-b', setorAtualId: 'setor-a'),
        isFalse,
      );
    });

    test('destino nulo nunca é interna (ainda não escolhido)', () {
      expect(
        ehTransferenciaInterna(tipo: MovimentacaoTipo.transferencia, destinoId: null, setorAtualId: 'setor-a'),
        isFalse,
      );
    });

    test('outros tipos nunca são "interna", mesmo com destino igual ao atual', () {
      expect(
        ehTransferenciaInterna(tipo: MovimentacaoTipo.manutencao, destinoId: 'setor-a', setorAtualId: 'setor-a'),
        isFalse,
      );
    });
  });

  group('PROMPT 10.2 — detalhesValidos (seção 15: nunca confundir null/vazio/false)', () {
    test('sem tipo escolhido: inválido', () {
      final r = NovaMovimentacaoRascunho();
      expect(detalhesValidos(r, _patrimonio()), isFalse);
    });

    test('MANUTENCAO sem destino: inválido; com destino: válido', () {
      final r = NovaMovimentacaoRascunho()..tipo = MovimentacaoTipo.manutencao;
      expect(detalhesValidos(r, _patrimonio()), isFalse);
      r.destinoSetorId = 'setor-b';
      expect(detalhesValidos(r, _patrimonio()), isTrue);
    });

    test('TRANSFERENCIA interna sem localização de destino: inválido', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.transferencia
        ..destinoSetorId = 'setor-atual';
      expect(detalhesValidos(r, _patrimonio(setorAtualId: 'setor-atual')), isFalse);
    });

    test('TRANSFERENCIA interna com localização "manter" (não "definir"): ainda inválido', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.transferencia
        ..destinoSetorId = 'setor-atual'
        ..localizacaoEscolha = LocalizacaoEscolha.manter
        ..localizacaoDestinoId = 'localizacao-x'; // mesmo com um id presente, a ESCOLHA não é "definir"
      expect(detalhesValidos(r, _patrimonio(setorAtualId: 'setor-atual')), isFalse);
    });

    test('MANUTENCAO com destino igual ao setor atual: inválido (PROMPT 10.2.2, seção 3)', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.manutencao
        ..destinoSetorId = 'setor-atual';
      expect(detalhesValidos(r, _patrimonio(setorAtualId: 'setor-atual')), isFalse);
      r.destinoSetorId = 'setor-b';
      expect(detalhesValidos(r, _patrimonio(setorAtualId: 'setor-atual')), isTrue);
    });

    test('TRANSFERENCIA interna com a MESMA localização atual: inválido (PROMPT 10.2.2, seção 4)', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.transferencia
        ..destinoSetorId = 'setor-atual'
        ..localizacaoEscolha = LocalizacaoEscolha.definir
        ..localizacaoDestinoId = 'localizacao-atual';
      expect(
        detalhesValidos(
          r,
          Patrimonio(
            id: 'p1',
            tipoId: 'tipo-1',
            status: PatrimonioStatus.disponivel,
            setorAtualId: 'setor-atual',
            localizacaoAtualId: 'localizacao-atual',
            dataCadastro: DateTime(2026, 1, 1),
            atualizadoEm: DateTime(2026, 1, 1),
          ),
        ),
        isFalse,
      );
    });

    test('TRANSFERENCIA interna com localização definida: válido', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.transferencia
        ..destinoSetorId = 'setor-atual'
        ..localizacaoEscolha = LocalizacaoEscolha.definir
        ..localizacaoDestinoId = 'localizacao-x';
      expect(detalhesValidos(r, _patrimonio(setorAtualId: 'setor-atual')), isTrue);
    });

    test('AJUSTE_INVENTARIO "Definir nova" sem escolher localização: inválido', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.ajusteInventario
        ..localizacaoEscolha = LocalizacaoEscolha.definir
        ..localizacaoDestinoId = null;
      expect(detalhesValidos(r, _patrimonio()), isFalse);
    });

    test('AJUSTE_INVENTARIO "Manter" (padrão): válido mesmo sem nada escolhido', () {
      final r = NovaMovimentacaoRascunho()..tipo = MovimentacaoTipo.ajusteInventario;
      expect(r.localizacaoEscolha, LocalizacaoEscolha.manter);
      expect(detalhesValidos(r, _patrimonio()), isTrue);
    });

    test('AJUSTE_INVENTARIO "Limpar": válido sem nenhuma localização escolhida', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.ajusteInventario
        ..localizacaoEscolha = LocalizacaoEscolha.limpar;
      expect(detalhesValidos(r, _patrimonio()), isTrue);
    });

    test('AJUSTE_INVENTARIO em BAIXADO: válido sem nada (padrão)', () {
      final r = NovaMovimentacaoRascunho()..tipo = MovimentacaoTipo.ajusteInventario;
      expect(detalhesValidos(r, _patrimonio(status: PatrimonioStatus.baixado)), isTrue);
    });

    test('AJUSTE_INVENTARIO em BAIXADO: destino diferente do atual é inválido, mesmo que o campo esteja escondido', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.ajusteInventario
        ..destinoSetorId = 'outro-setor';
      expect(
        detalhesValidos(r, _patrimonio(status: PatrimonioStatus.baixado, setorAtualId: 'setor-atual')),
        isFalse,
      );
    });

    test('AJUSTE_INVENTARIO em BAIXADO: escolha "Definir"/"Limpar" localização é inválida', () {
      final definir = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.ajusteInventario
        ..localizacaoEscolha = LocalizacaoEscolha.definir
        ..localizacaoDestinoId = 'loc-1';
      expect(detalhesValidos(definir, _patrimonio(status: PatrimonioStatus.baixado)), isFalse);

      final limpar = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.ajusteInventario
        ..localizacaoEscolha = LocalizacaoEscolha.limpar;
      expect(detalhesValidos(limpar, _patrimonio(status: PatrimonioStatus.baixado)), isFalse);
    });

    test('EMPRESTIMO exige responsável, mesmo com destino preenchido', () {
      final r = NovaMovimentacaoRascunho()
        ..tipo = MovimentacaoTipo.emprestimo
        ..destinoSetorId = 'setor-b';
      expect(detalhesValidos(r, _patrimonio()), isFalse);
      r.responsavelController.text = 'Maria Souza';
      expect(detalhesValidos(r, _patrimonio()), isTrue);
      r.dispose();
    });

    test('ALTERACAO_RESPONSAVEL: novo responsável igual ao atual é inválido', () {
      final r = NovaMovimentacaoRascunho()..tipo = MovimentacaoTipo.alteracaoResponsavel;
      r.responsavelController.text = 'João Silva';
      expect(detalhesValidos(r, _patrimonio(responsavelAtual: 'João Silva')), isFalse);
      r.responsavelController.text = 'Maria Souza';
      expect(detalhesValidos(r, _patrimonio(responsavelAtual: 'João Silva')), isTrue);
      r.dispose();
    });

    test('BAIXA: válido sem nenhum campo adicional (destino/localização/responsável nem existem para ela)', () {
      final r = NovaMovimentacaoRascunho()..tipo = MovimentacaoTipo.baixa;
      expect(detalhesValidos(r, _patrimonio()), isTrue);
    });
  });
}
