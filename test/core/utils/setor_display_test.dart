import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/utils/setor_display.dart';

/// PROMPT 11.3.5.3 — `siglaOuNomeSetor` é a ÚNICA função que decide como um
/// setor aparece em contexto compacto (tabelas/dropdowns/detalhamentos):
/// nunca um mapa fixo por setor conhecido (GETEC/GEASI/GESOL/CIMEHGO) e
/// nunca uma sigla inventada a partir das iniciais do nome.
void main() {
  group('PROMPT 11.3.5.3 — siglaOuNomeSetor', () {
    test('GETEC apresentado como GETEC', () {
      expect(siglaOuNomeSetor(sigla: 'GETEC', nome: 'Gerencia de Tecnologia'), 'GETEC');
    });

    test('GEASI apresentado como GEASI', () {
      expect(
        siglaOuNomeSetor(
          sigla: 'GEASI',
          nome: 'Gerência de Licenciamento de Atividades Estratégicas e de Significativo Impacto',
        ),
        'GEASI',
      );
    });

    test('GESOL apresentado como GESOL', () {
      expect(
        siglaOuNomeSetor(
          sigla: 'GESOL',
          nome: 'Gerência de Licenciamento de Atividades Agropecuárias e de Conversão do Uso do Solo',
        ),
        'GESOL',
      );
    });

    test('CIMEHGO apresentado como CIMEHGO', () {
      expect(
        siglaOuNomeSetor(
          sigla: 'CIMEHGO',
          nome: 'Centro de Informações Meteorológicas e Hidrológicas de Goiás',
        ),
        'CIMEHGO',
      );
    });

    test('outro setor qualquer, nunca visto antes, usa a sigla cadastrada — sem depender de lista fixa', () {
      // GEPOS não existe em nenhum mapa/switch — se a função funcionar por
      // uma lista fixa de setores conhecidos, este teste falharia.
      expect(siglaOuNomeSetor(sigla: 'GEPOS', nome: 'Gerência de Posturas'), 'GEPOS');
      expect(siglaOuNomeSetor(sigla: 'QUALQUER-SIGLA-123', nome: 'Um Setor Fictício de Teste'), 'QUALQUER-SIGLA-123');
    });

    test('setor sem sigla conhecida usa o nome completo como fallback seguro', () {
      expect(
        siglaOuNomeSetor(sigla: null, nome: 'Setor Sem Sigla Cadastrada'),
        'Setor Sem Sigla Cadastrada',
      );
      expect(siglaOuNomeSetor(sigla: '', nome: 'Setor Com Sigla Vazia'), 'Setor Com Sigla Vazia');
      expect(siglaOuNomeSetor(sigla: '   ', nome: 'Setor Com Sigla Só Espaços'), 'Setor Com Sigla Só Espaços');
    });

    test('nunca inventa uma sigla a partir das iniciais do nome quando não há sigla nem nome', () {
      expect(siglaOuNomeSetor(sigla: null, nome: null), isNull);
      expect(siglaOuNomeSetor(sigla: '', nome: ''), isNull);
    });

    test('sigla com espaços ao redor é aparada', () {
      expect(siglaOuNomeSetor(sigla: '  GETEC  ', nome: 'Gerencia de Tecnologia'), 'GETEC');
    });
  });
}
