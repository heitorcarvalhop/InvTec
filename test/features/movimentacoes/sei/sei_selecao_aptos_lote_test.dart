import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_selecao_aptos_lote.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';

/// PROMPT 11.5.10/11.5.10.1 — [selecionarAptosParaLoteComPatrimonios] (PURA,
/// sem I/O): combina a triagem preliminar por item com a reavaliação
/// contra o patrimônio ATUAL de cada candidato (via `planejarConclusaoLote`,
/// nenhuma regra de elegibilidade nova/duplicada aqui) e aplica o limite de
/// 200 itens por lote à contagem FINAL, nunca à preliminar. Nenhum teste
/// aqui fala com o Supabase, usa o Despacho 577 ou toca a conclusão
/// individual.
void main() {
  const docId = 'doc-1';

  SeiDocumentoPendente documento(List<SeiItemPendente> itens) {
    return SeiDocumentoPendente.fromItens(
      id: docId,
      numeroDocumentoSei: 'SEI-teste',
      tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
      nomeArquivo: 'despacho.pdf',
      hashSha256: 'hash',
      versao: 1,
      criadoEm: DateTime.utc(2026, 1, 1),
      criadoPorId: 'user-1',
      criadoPorNome: 'Usuária de Teste',
      itens: itens,
    );
  }

  // Item PENDENTE, tecnicamente elegível pela triagem por item (origem/
  // destino/decisões resolvidas) — a única coisa que varia entre os testes
  // é se o patrimônio correspondente, na consulta, está coerente ou não.
  SeiItemPendente itemElegivel(int n) {
    return SeiItemPendente(
      id: 'item-$n',
      documentoId: docId,
      linha: n,
      patrimonioId: 'pat-$n',
      numeroPatrimonio: SeiValorCorrigivel(original: 'PAT-$n'),
      origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
      origemSetorId: 'setor-getec',
      destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
      destinoSetorId: 'setor-ntat',
      numeroChamado: const SeiValorCorrigivel(original: null),
      equipamentoTexto: const SeiValorCorrigivel(original: 'Notebook'),
      decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
      decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
      status: SeiItemPendenciaStatus.pendente,
      criadoEm: DateTime.utc(2026, 1, 1),
    );
  }

  PatrimonioDetalhe patrimonioCoerente(int n) {
    return PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: 'pat-$n',
        numeroPatrimonio: 'PAT-$n',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.disponivel,
        setorAtualId: 'setor-getec', // igual à origem do item — elegível.
        dataCadastro: DateTime.utc(2026, 1, 1),
        atualizadoEm: DateTime.utc(2026, 1, 1),
      ),
      tipoNome: 'Notebook',
      setorNome: 'Gerência de Tecnologia',
    );
  }

  PatrimonioDetalhe patrimonioDivergente(int n) {
    return PatrimonioDetalhe(
      patrimonio: Patrimonio(
        id: 'pat-$n',
        numeroPatrimonio: 'PAT-$n',
        tipoId: 'tipo-1',
        status: PatrimonioStatus.disponivel,
        setorAtualId: 'setor-almox', // DIFERENTE da origem do item.
        dataCadastro: DateTime.utc(2026, 1, 1),
        atualizadoEm: DateTime.utc(2026, 1, 1),
      ),
      tipoNome: 'Notebook',
      setorNome: 'Almoxarifado',
    );
  }

  group('PROMPT 11.5.10.1 — limite de 200 aplicado à seleção FINAL, nunca à preliminar', () {
    test('201 preliminares, 1 bloqueado na reavaliação (origem divergente): 200 aptos, operação permitida', () {
      final itens = [for (var i = 1; i <= 201; i++) itemElegivel(i)];
      final doc = documento(itens);
      final patrimonios = {
        for (var i = 1; i <= 201; i++) 'item-$i': i == 1 ? patrimonioDivergente(i) : patrimonioCoerente(i),
      };

      // Confirma a premissa: a triagem preliminar sozinha vê 201 aptos.
      expect(selecionarAptosParaLote(itens).aptos.length, 201);

      final selecao = selecionarAptosParaLoteComPatrimonios(documento: doc, patrimoniosPorItemId: patrimonios);

      expect(selecao.aptos.length, 200);
      expect(selecao.excedeLimite, isFalse, reason: 'a contagem FINAL (200) não excede o limite');
      expect(selecao.aptos.any((i) => i.linha == 1), isFalse);
      expect(selecao.naoIncluidos.any((n) => n.item.linha == 1), isTrue);
      expect(
        selecao.naoIncluidos.firstWhere((n) => n.item.linha == 1).motivos.any((m) => m.contains('Origem divergente')),
        isTrue,
      );
    });

    test('201 preliminares, todos elegíveis: operação BLOQUEADA (excede o limite de 200)', () {
      final itens = [for (var i = 1; i <= 201; i++) itemElegivel(i)];
      final doc = documento(itens);
      final patrimonios = {for (var i = 1; i <= 201; i++) 'item-$i': patrimonioCoerente(i)};

      final selecao = selecionarAptosParaLoteComPatrimonios(documento: doc, patrimoniosPorItemId: patrimonios);

      expect(selecao.aptos.length, 201);
      expect(selecao.excedeLimite, isTrue);
      // Nunca trunca sozinho: os 201 continuam em `aptos`, cabe à tela
      // recusar a ação automática e pedir seleção manual — nunca aqui.
    });

    test('205 preliminares, 10 bloqueados na reavaliação: 195 aptos, operação permitida', () {
      final itens = [for (var i = 1; i <= 205; i++) itemElegivel(i)];
      final doc = documento(itens);
      final patrimonios = {
        for (var i = 1; i <= 205; i++) 'item-$i': i <= 10 ? patrimonioDivergente(i) : patrimonioCoerente(i),
      };

      final selecao = selecionarAptosParaLoteComPatrimonios(documento: doc, patrimoniosPorItemId: patrimonios);

      expect(selecao.aptos.length, 195);
      expect(selecao.excedeLimite, isFalse);
      for (var i = 1; i <= 10; i++) {
        expect(selecao.aptos.any((it) => it.linha == i), isFalse);
        expect(selecao.naoIncluidos.any((n) => n.item.linha == i), isTrue);
      }
    });

    test('falha de consulta patrimonial (item ausente do mapa): item excluído com motivo, NUNCA presumido elegível', () {
      final itens = [itemElegivel(1), itemElegivel(2)];
      final doc = documento(itens);
      // item-1 "falhou" na busca (mesmo padrão de `_buscarPatrimoniosAtuais`:
      // uma exceção captada vira `null` no mapa — aqui, simplesmente ausente,
      // que `patrimoniosPorItemId[...]` resolve como `null` do mesmo jeito).
      final patrimonios = {'item-2': patrimonioCoerente(2)};

      final selecao = selecionarAptosParaLoteComPatrimonios(documento: doc, patrimoniosPorItemId: patrimonios);

      expect(selecao.aptos.length, 1);
      expect(selecao.aptos.single.linha, 2);
      expect(selecao.naoIncluidos, hasLength(1));
      expect(selecao.naoIncluidos.single.item.linha, 1);
      expect(
        selecao.naoIncluidos.single.motivos.any((m) => m.contains('Não foi possível carregar a situação atual')),
        isTrue,
        reason: selecao.naoIncluidos.single.motivos.join('; '),
      );
    });

    test('seleção vazia na triagem preliminar: devolve a triagem sem consultar nada (nenhum patrimônio necessário)', () {
      final itens = [
        SeiItemPendente(
          id: 'item-1',
          documentoId: docId,
          linha: 1,
          patrimonioId: null, // não elegível na triagem por item
          numeroPatrimonio: const SeiValorCorrigivel(original: 'PAT-1'),
          origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
          origemSetorId: 'setor-getec',
          destinoTexto: const SeiValorCorrigivel(original: 'NTAT'),
          destinoSetorId: 'setor-ntat',
          numeroChamado: const SeiValorCorrigivel(original: null),
          equipamentoTexto: const SeiValorCorrigivel(original: 'Notebook'),
          decisaoLocalizacao: SeiDecisaoCampo.confirmadoSemInformacao,
          decisaoResponsavel: SeiDecisaoCampo.confirmadoSemInformacao,
          status: SeiItemPendenciaStatus.pendente,
          criadoEm: DateTime.utc(2026, 1, 1),
        ),
      ];
      final doc = documento(itens);

      final selecao = selecionarAptosParaLoteComPatrimonios(documento: doc, patrimoniosPorItemId: const {});

      expect(selecao.aptos, isEmpty);
      expect(selecao.naoIncluidos, hasLength(1));
      expect(selecao.excedeLimite, isFalse);
    });
  });
}
