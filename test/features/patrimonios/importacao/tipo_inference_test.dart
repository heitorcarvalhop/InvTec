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

  // Casos reais encontrados no diagnóstico offline com a planilha real da
  // GETEC (local_test_data/BENS DA GETEC.xlsx) — cada um corrige um falso
  // negativo/positivo confirmado, sem generalizar além do caso observado.
  group('inferirTipoPorDescricao — correções a partir de dados reais da GETEC', () {
    test('plural "SWITCHES" também resolve para Equipamento de Rede', () {
      final resultado = inferirTipoPorDescricao('SWITCHES DELL NETWORKING N3024 - N. de Série: 6VS1Y42');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Equipamento de Rede');
    });

    test('plural "ESTABILIZADORES" também resolve para Estabilizador', () {
      final resultado = inferirTipoPorDescricao('ESTABILIZADORES PROGRESSIVE III');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Estabilizador');
    });

    test('"SCANNER DE MESA" vira Outros, não Mobiliário (precedência sobre "mesa")', () {
      final resultado = inferirTipoPorDescricao('SCANNER DE MESA, COLOR, DUPLEX 35 PPM - ES-400');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Outros');
    });

    test('"TABLET"/"TECLADO"/"MOUSE"/"AR CONDICIONADO" continuam Outros mesmo perto de móveis', () {
      expect(inferirTipoPorDescricao('TABLET SOBRE A MESA DO ESTOQUE').nomeTipo, 'Outros');
      expect(inferirTipoPorDescricao('TECLADO GUARDADO NO ARMARIO').nomeTipo, 'Outros');
    });

    test('"OFFICE HOME AND BUSINESS" (sem "Microsoft") vira Software / Licença', () {
      final resultado = inferirTipoPorDescricao('OFFICE HOME AND BUSINESS 2019 T5D-03191 ESD EAN 889842822502');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Software / Licença');
    });

    test('"OFFICE 2019 PROFESSIONAL" (sem "Microsoft") vira Software / Licença', () {
      final resultado = inferirTipoPorDescricao('OFFICE 2019 PROFESSIONAL PTBR=PRO');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Software / Licença');
    });

    test('"OFFICE 365" vira Software / Licença', () {
      expect(inferirTipoPorDescricao('LICENÇA OFFICE 365 BUSINESS').nomeTipo, 'Software / Licença');
    });

    test('"LICENÇA OFFICE PARA NOTEBOOK" continua Software / Licença, não Notebook', () {
      final resultado = inferirTipoPorDescricao('LICENÇA OFFICE PARA NOTEBOOK');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Software / Licença');
    });

    test('"office" isolado sem contexto de licença não é classificado automaticamente', () {
      // Evita falso positivo com algo como "cadeira para home office" —
      // "office" sozinho nunca é palavra-chave.
      final resultado = inferirTipoPorDescricao('CADEIRA GIRATÓRIA PARA HOME OFFICE');
      expect(resultado.nomeTipo, 'Mobiliário');
    });

    test('"MICRO COMPUTADOR" (com espaço) vira Desktop', () {
      final resultado = inferirTipoPorDescricao('MICRO COMPUTADOR LENOVO');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Desktop');
    });

    test('"MICRO-COMPUTADOR" (com hífen) também vira Desktop', () {
      expect(inferirTipoPorDescricao('MICRO-COMPUTADOR HP').nomeTipo, 'Desktop');
    });

    test('"MICROCOMPUTADOR" (uma palavra só) continua Desktop', () {
      expect(inferirTipoPorDescricao('MICROCOMPUTADOR DELL').nomeTipo, 'Desktop');
    });

    test('"POLTRONA GIRATÓRIA" vira Mobiliário', () {
      final resultado = inferirTipoPorDescricao('POLTRONA GIRATÓRIA ESPALDAR EM TELA COM BRAÇOS');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Mobiliário');
    });

    test('kit de videoconferência (Logitech Group) vira Outros, sem criar tipo novo', () {
      final resultado = inferirTipoPorDescricao('LOGITECH GROUP VIDEOCONFERÊNCIA - EXPANSION MIC');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Outros');
    });

    test('"CÂMERA"/"MICROFONE" isolados, sem contexto de videoconferência, não são classificados', () {
      // Conservador de propósito: só frases explícitas de videoconferência
      // disparam a regra — uma câmera/microfone genérico não deve virar
      // "Outros" só por essas palavras isoladas.
      expect(inferirTipoPorDescricao('CÂMERA FOTOGRÁFICA DIGITAL').confianca, InferenciaTipoConfianca.naoIdentificada);
      expect(inferirTipoPorDescricao('MICROFONE DE LAPELA').confianca, InferenciaTipoConfianca.naoIdentificada);
    });

    test('descrições com "RACK" continuam Não identificado nesta rodada', () {
      final resultado = inferirTipoPorDescricao('RACK PADRAO PISO 19" PRETO 44U X 770MM - SEI: 202400017008282');
      expect(resultado.confianca, InferenciaTipoConfianca.naoIdentificada);
    });

    test('"GARANTIA ESTENDIDA" continua Não identificado nesta rodada', () {
      expect(inferirTipoPorDescricao('GARANTIA ESTENDIDA').confianca, InferenciaTipoConfianca.naoIdentificada);
    });

    test(
      'ESCADA continua Não identificado (fora das 26 regras seguras aprovadas no PROMPT 8.12)',
      () {
        expect(inferirTipoPorDescricao('ESCADA ALUMÍNIO 8 DEGRAUS').confianca, InferenciaTipoConfianca.naoIdentificada);
      },
    );

    test('MULTÍMETRO agora resolve para Outros (regra segura do PROMPT 8.12, auditoria 8.11)', () {
      final resultado = inferirTipoPorDescricao('MULTÍMETRO FLUKE 107');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Outros');
    });
  });

  group('inferirTipoPorDescricao — 26 regras seguras do PROMPT 8.12 (auditoria 8.11)', () {
    // Uma descrição real (ou representativa) da planilha por regra —
    // confirma exatamente os 13 grupos aprovados, cobrindo as duas
    // variantes de grafia quando existirem (typo real + forma correta).
    const casosConfirmados = <String, String>{
      // optiplex / optplex -> Desktop
      'OPTIPLEX SMALL FORM FACTOR 7020 - N. de Série: 8HDHCD4': 'Desktop',
      'COMPUTADOR OPTPLEX 780 (PAT. ANTERIOR: 2316757)': 'Desktop',
      // thinkcentre / thinkcenter -> Desktop
      'COMPUTADOR THINKCENTER M81 - N. de Série: L1C4TAD': 'Desktop',
      'COMPUTADOR THINKCENTRE M81': 'Desktop',
      // compaq pro -> Desktop
      'COMPUTADOR COMPAQ PRO 4300 - N. de Série: BRG306FDGP': 'Desktop',
      // estacao de trabalho / workstation -> Desktop
      'ESTAÇÃO DE TRABALHO DELL PRECISION T5820 - GABINETE - PERIFÉRICOS': 'Desktop',
      'WORKSTATION DELL PRECISION': 'Desktop',
      // mac mini -> Desktop
      'MAC MINI M18C SILV 256GB - N. de Série: MGNR3BZ/A': 'Desktop',
      // ponto de acesso -> Equipamento de Rede
      'PONTO DE ACESSO RUCKUS R610 - N. de Série: 422049001989': 'Equipamento de Rede',
      // televiisor (typo real) -> TV
      'TELEVIISOR LED SMARTV 55 POL - N. de Série: 102AZUJ5L918': 'TV',
      // arcondicionado (sem espaço) -> Outros
      'ARCONDICIONADO ELETROLUX': 'Outros',
      // frigobar -> Outros
      'FRIGOBAR ELECTROLUZ RE 120': 'Outros',
      // multimetro -> Outros
      'MULTÍMETRO FLUKE 107': 'Outros',
      // parafusadeira / furadeira -> Outros
      'PARAFUSADEIRA E FURADEIRA BOSCH GSR 1000 SMART 12V': 'Outros',
      // office home and bussines (typo real) -> Software / Licença
      'OFFICE HOME AND BUSSINES 2019 ESD': 'Software / Licença',
      // iphone -> Outros
      'IPHONE SE 2TH BLACK 64GB MHGP3BR/A APPLE': 'Outros',
    };

    for (final entry in casosConfirmados.entries) {
      test('"${entry.key}" -> ${entry.value}', () {
        final resultado = inferirTipoPorDescricao(entry.key);
        expect(resultado.confianca, InferenciaTipoConfianca.confirmada, reason: entry.key);
        expect(resultado.nomeTipo, entry.value, reason: entry.key);
      });
    }

    test('"ar condicionado" (com espaço, regra pré-existente) continua Outros — nova regra não a substitui', () {
      final resultado = inferirTipoPorDescricao('AR CONDICIONADO ELETROLUX');
      expect(resultado.confianca, InferenciaTipoConfianca.confirmada);
      expect(resultado.nomeTipo, 'Outros');
    });

    test('nenhuma regra nova é genérica demais: palavras soltas não relacionadas continuam sem match', () {
      // "pro" sozinho (fora de "compaq pro"), "trabalho" sozinho (fora de
      // "estacao de trabalho") e "ponto" sozinho (fora de "ponto de
      // acesso") não devem disparar nenhuma regra nova.
      expect(inferirTipoPorDescricao('CADEIRA PRO GAMER').nomeTipo, 'Mobiliário');
      expect(inferirTipoPorDescricao('RELATÓRIO DE TRABALHO MENSAL').confianca, InferenciaTipoConfianca.naoIdentificada);
      expect(inferirTipoPorDescricao('PONTO ELETRÔNICO BIOMÉTRICO').confianca, InferenciaTipoConfianca.naoIdentificada);
    });
  });
}
