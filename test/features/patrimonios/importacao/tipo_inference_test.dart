import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/tipo_inference.dart';

void main() {
  group('inferirTipoPorDescricao', () {
    // Seção 32 da especificação do perfil GETEC: casos mínimos exigidos.
    const casosConfirmados = <String, String>{
      'NOTEBOOK LENOVO': 'Notebook',
      'MONITOR DELL': 'Monitor',
      'DESKTOP LENOVO': 'Desktop',
      'IMPRESSORA': 'Impressora',
      'NOBREAK APC': 'Nobreak',
      'SERVIDOR': 'Servidor',
      'TV': 'TV',
      'PROJETOR': 'Projetor',
      'SWITCH': 'Equipamento de Rede',
      'ACCESS POINT': 'Equipamento de Rede',
      'ESTABILIZADOR': 'Estabilizador',
      'ARMARIO': 'Mobiliário',
      'MESA': 'Mobiliário',
      'CERTIFICADO DIGITAL': 'Certificado Digital',
    };

    for (final entry in casosConfirmados.entries) {
      test('"${entry.key}" -> ${entry.value} (confirmado por regra)', () {
        final resultado = inferirTipoPorDescricao(entry.key);
        expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
        expect(resultado.nomeTipo, entry.value);
      });
    }

    test('precedência: licença de software não vira Notebook só por conter a palavra', () {
      final resultado = inferirTipoPorDescricao('LICENÇA MICROSOFT OFFICE PARA NOTEBOOK LENOVO');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Software / Licença');
    });

    // Seção 31: itens que o catálogo GETEC não quer como tipo próprio viram
    // "Outros" por regra explícita — nunca um tipo novo.
    const casosOutros = ['TECLADO', 'MOUSE', 'DOCK STATION', 'SCANNER', 'TABLET', 'AR CONDICIONADO'];
    for (final descricao in casosOutros) {
      test('"$descricao" -> Outros (nunca vira tipo próprio)', () {
        final resultado = inferirTipoPorDescricao(descricao);
        expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
        expect(resultado.nomeTipo, 'Outros');
      });
    }

    test('AR-CONDICIONADO (com hífen) também resolve para Outros', () {
      final resultado = inferirTipoPorDescricao('AR-CONDICIONADO SPLIT 9000 BTU');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Outros');
    });

    test('descrição desconhecida não é classificada automaticamente', () {
      final resultado = inferirTipoPorDescricao('ITEM SEM CATEGORIA CONHECIDA XPTO123');
      expect(resultado.confianca, InferenciaTipoConfianca.naoIdentificada);
      expect(resultado.nomeTipo, isNull);
    });

    test('descrição nula ou vazia não é classificada automaticamente', () {
      expect(inferirTipoPorDescricao(null).confianca, InferenciaTipoConfianca.naoIdentificada);
      expect(inferirTipoPorDescricao('   ').confianca, InferenciaTipoConfianca.naoIdentificada);
    });

    test('não bate por substring dentro de outra palavra (ex.: "monitor" dentro de "monitoramento")', () {
      final resultado = inferirTipoPorDescricao('SERVIÇO DE MONITORAMENTO DE REDE');
      expect(resultado.confianca, InferenciaTipoConfianca.naoIdentificada);
    });
  });
}
