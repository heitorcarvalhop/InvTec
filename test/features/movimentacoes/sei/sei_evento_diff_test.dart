import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_evento_diff.dart';

/// PROMPT 11.3.8 — testes PUROS (sem widgets, sem Flutter) da extração de
/// diffs de um evento EDICAO, a partir de `dados_antes`/`dados_depois` no
/// MESMO formato bruto que `editar_documento_sei_pendente` grava
/// (`{'documento': {...4 campos...}, 'itens': [linhas inteiras de
/// documentos_sei_itens]}`).
void main() {
  group('diffDocumentoDoEvento', () {
    test('lista só os campos do documento que realmente mudaram', () {
      final antes = {
        'documento': {
          'numero_documento_sei': '99999999',
          'numero_processo': '2026.0001',
          'numero_documento_formatado': '999999/2026/TESTE-PROMPT1137',
          'assunto': 'Assunto original',
        },
        'itens': <Object?>[],
      };
      final depois = {
        'documento': {
          'numero_documento_sei': '99999999',
          'numero_processo': '2026.9999',
          'numero_documento_formatado': '999999/2026/TESTE-PROMPT1137',
          'assunto': 'Assunto corrigido',
        },
        'itens': <Object?>[],
      };

      final campos = diffDocumentoDoEvento(antes, depois);

      expect(campos.map((c) => c.chave), containsAll(['numero_processo', 'assunto']));
      expect(campos.map((c) => c.chave), isNot(contains('numero_documento_sei')));
      expect(campos.map((c) => c.chave), isNot(contains('numero_documento_formatado')));

      final processo = campos.firstWhere((c) => c.chave == 'numero_processo');
      expect(processo.antes, '2026.0001');
      expect(processo.depois, '2026.9999');
    });

    test('dados_antes/dados_depois nulos (ex.: evento CRIACAO) não produzem campos', () {
      expect(diffDocumentoDoEvento(null, null), isEmpty);
      expect(diffDocumentoDoEvento(null, {'numero_documento_sei': '123'}), isEmpty);
    });
  });

  group('diffItensDoEvento', () {
    test('exemplo real do documento fictício: chamado do patrimônio 900000001 de 9999 para 9998', () {
      final antes = {
        'documento': {},
        'itens': [
          {
            'id': 'item-1',
            'linha': 1,
            'numero_patrimonio_original': '900000001',
            'numero_patrimonio_corrigido': null,
            'destino_texto_corrigido': null,
            'numero_chamado_original': '9999',
            'numero_chamado_corrigido': null,
            'equipamento_texto_corrigido': null,
            'destino_setor_id': null,
            'localizacao_destino_id': null,
            'decisao_localizacao': 'PENDENTE',
            'responsavel_destino': null,
            'decisao_responsavel': 'PENDENTE',
          },
        ],
      };
      final depois = {
        'documento': {},
        'itens': [
          {
            'id': 'item-1',
            'linha': 1,
            'numero_patrimonio_original': '900000001',
            'numero_patrimonio_corrigido': null,
            'destino_texto_corrigido': null,
            'numero_chamado_original': '9999',
            'numero_chamado_corrigido': '9998',
            'equipamento_texto_corrigido': null,
            'destino_setor_id': null,
            'localizacao_destino_id': null,
            'decisao_localizacao': 'PENDENTE',
            'responsavel_destino': null,
            'decisao_responsavel': 'PENDENTE',
          },
        ],
      };

      final itens = diffItensDoEvento(antes, depois);

      expect(itens, hasLength(1));
      expect(itens.single.numeroPatrimonio, '900000001');
      expect(itens.single.rotuloItem, 'Patrimônio 900000001');
      expect(itens.single.campos, hasLength(1));
      expect(itens.single.campos.single.chave, 'numero_chamado_corrigido');
      expect(itens.single.campos.single.antes, '9999');
      expect(itens.single.campos.single.depois, '9998');
    });

    test('campos fora da lista de editáveis (ex.: status/corrigido_por) nunca entram no diff', () {
      final antes = {
        'itens': [
          {
            'id': 'item-1',
            'linha': 1,
            'numero_patrimonio_original': '900000001',
            'numero_chamado_corrigido': null,
            'status': 'PENDENTE',
            'corrigido_por': null,
          },
        ],
      };
      final depois = {
        'itens': [
          {
            'id': 'item-1',
            'linha': 1,
            'numero_patrimonio_original': '900000001',
            'numero_chamado_corrigido': null,
            'status': 'CONCLUIDO',
            'corrigido_por': 'user-1',
          },
        ],
      };

      // "status" e "corrigido_por" mudaram no jsonb bruto, mas não fazem
      // parte da lista de campos que uma edição de fato altera — nunca
      // podem aparecer como "campo alterado" no histórico.
      expect(diffItensDoEvento(antes, depois), isEmpty);
    });

    test('nenhum campo "_original" aparece como chave de um campo alterado', () {
      final antes = {
        'itens': [
          {'id': 'item-1', 'linha': 1, 'numero_patrimonio_original': '900000001', 'equipamento_texto_corrigido': null},
        ],
      };
      final depois = {
        'itens': [
          {
            'id': 'item-1',
            'linha': 1,
            'numero_patrimonio_original': '900000001',
            'equipamento_texto_corrigido': 'Monitor corrigido',
          },
        ],
      };

      final campos = diffItensDoEvento(antes, depois).single.campos;
      expect(campos.map((c) => c.chave), everyElement(isNot(endsWith('_original'))));
    });

    test('itens são pareados por id, nunca por posição', () {
      final antes = {
        'itens': [
          {'id': 'item-B', 'linha': 2, 'numero_patrimonio_original': '900000002', 'equipamento_texto_corrigido': null},
          {'id': 'item-A', 'linha': 1, 'numero_patrimonio_original': '900000001', 'equipamento_texto_corrigido': null},
        ],
      };
      final depois = {
        'itens': [
          {
            'id': 'item-A',
            'linha': 1,
            'numero_patrimonio_original': '900000001',
            'equipamento_texto_corrigido': 'Monitor corrigido',
          },
          {'id': 'item-B', 'linha': 2, 'numero_patrimonio_original': '900000002', 'equipamento_texto_corrigido': null},
        ],
      };

      final itens = diffItensDoEvento(antes, depois);

      expect(itens, hasLength(1), reason: 'só item-A mudou de verdade');
      expect(itens.single.itemId, 'item-A');
      expect(itens.single.numeroPatrimonio, '900000001');
    });

    test('item sem nenhum campo alterado não aparece no resultado', () {
      final mesmoItem = {
        'id': 'item-1',
        'linha': 1,
        'numero_patrimonio_original': '900000001',
        'numero_chamado_corrigido': '9998',
      };
      expect(
        diffItensDoEvento(
          {'itens': [mesmoItem]},
          {'itens': [mesmoItem]},
        ),
        isEmpty,
      );
    });

    test('sem dados_antes/dados_depois (eventos que não são EDICAO), devolve lista vazia', () {
      expect(diffItensDoEvento(null, null), isEmpty);
    });
  });

  group('rotuloDecisaoBruta', () {
    test('mapeia os três estados e cai para "—" em nulo', () {
      expect(rotuloDecisaoBruta('PENDENTE'), contains('Pendente'));
      expect(rotuloDecisaoBruta('DEFINIDO'), 'Definida');
      expect(rotuloDecisaoBruta('CONFIRMADO_SEM_INFORMACAO'), 'Confirmado sem informação');
      expect(rotuloDecisaoBruta(null), '—');
    });
  });
}
