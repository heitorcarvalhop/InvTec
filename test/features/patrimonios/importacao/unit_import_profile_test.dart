import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_preflight.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/unit_import_profile.dart';
import 'package:invtec/features/setores/domain/setor.dart';

/// Configuração FICTÍCIA, só para este teste — nunca usada como dado real
/// do app: prova que [UnitImportProfile] funciona com uma unidade diferente
/// da GETEC, sem depender de nenhuma regra hardcoded específica dela.
UnitImportProfile _perfilFicticio() => UnitImportProfile(
  sigla: 'ZZZ',
  nomeCompleto: 'Unidade Fictícia Completa',
  cabecalhosAlvo: const {
    ImportColumnField.numeroPatrimonio: 'codigo',
    ImportColumnField.descricao: 'item',
    ImportColumnField.marca: 'fabricante',
  },
  cabecalhosObrigatoriosDeteccao: const {'codigo', 'item'},
  minimoCamposReconhecidosDeteccao: 2,
  camposComSentinelaAusencia: const {ImportColumnField.numeroPatrimonio},
  ehSentinelaAusencia: (valor) => valor is String && valor.trim() == 'N/A',
  nomesLocalizacoesOficiais: const ['DEPÓSITO FICTÍCIO', 'SALA FICTÍCIA 2'],
  apelidosLocalizacao: const {'SALA 2': 'SALA FICTÍCIA 2'},
  valoresSemLocalizacaoConhecidos: const ['NÃO SE APLICA'],
  motivoPadraoSugerido: 'Carga fictícia de teste.',
  mensagemDeteccao: 'Formato fictício reconhecido.',
);

void main() {
  group('UnitImportProfile — configuração fictícia (prova de generalização)', () {
    test('detectar reconhece os cabeçalhos configurados, não os da GETEC', () {
      final perfil = _perfilFicticio();
      expect(perfil.detectar(['Código', 'Item', 'Fabricante']), isTrue);
      // cabeçalhos da GETEC não ativam este perfil fictício.
      expect(perfil.detectar(['Tombamento', 'Descrição', 'N Serie', 'Marca']), isFalse);
    });

    test('mapeamentoSugerido mapeia pelos cabeçalhos próprios', () {
      final perfil = _perfilFicticio();
      final mapeamento = perfil.mapeamentoSugerido(['Código', 'Item', 'Fabricante']);
      expect(mapeamento.colunaDe(ImportColumnField.numeroPatrimonio), 0);
      expect(mapeamento.colunaDe(ImportColumnField.descricao), 1);
      expect(mapeamento.colunaDe(ImportColumnField.marca), 2);
    });

    test('encontrarGerencia resolve pela sigla própria, nunca "GETEC"', () {
      final perfil = _perfilFicticio();
      final setores = [
        Setor(id: 'zzz-1', nome: 'Unidade Fictícia', sigla: 'ZZZ', ativo: true, criadoEm: DateTime(2026, 1, 1)),
        Setor(id: 'getec-1', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
      ];
      final gerencia = perfil.encontrarGerencia(setores);
      expect(gerencia?.id, 'zzz-1');
    });

    test('sentinela própria ("N/A") limpa o campo configurado', () {
      final perfil = _perfilFicticio();
      expect(perfil.limparSentinela('N/A'), isNull);
      expect(perfil.limparSentinela('123'), '123');
    });

    test('prepararLinhas aplica a sentinela só na coluna mapeada para o campo configurado', () {
      final perfil = _perfilFicticio();
      final mapeamento = perfil.mapeamentoSugerido(['Código', 'Item', 'Fabricante']);
      final preparo = perfil.prepararLinhas(
        linhas: [
          ['Código', 'Item', 'Fabricante'],
          ['N/A', 'Item fictício', 'N/A'],
        ],
        indiceCabecalho: 0,
        mapeamento: mapeamento,
      );
      expect(preparo.linhas[1][0], isNull); // coluna mapeada (numeroPatrimonio) -> limpa.
      expect(preparo.linhas[1][2], 'N/A'); // coluna não mapeada para sentinela -> preservada.
    });

    test('resolverLocalizacao resolve nome oficial e apelido fictícios', () {
      final perfil = _perfilFicticio();
      final localizacoes = [
        Localizacao(id: 'loc-1', setorId: 'zzz-1', nome: 'DEPÓSITO FICTÍCIO', ativo: true, criadoEm: DateTime(2026, 1, 1)),
        Localizacao(id: 'loc-2', setorId: 'zzz-1', nome: 'SALA FICTÍCIA 2', ativo: true, criadoEm: DateTime(2026, 1, 1)),
      ];
      expect(perfil.resolverLocalizacao('depósito fictício', localizacoes)?.id, 'loc-1');
      expect(perfil.resolverLocalizacao('Sala 2', localizacoes)?.id, 'loc-2');
      expect(perfil.resolverLocalizacao('inexistente', localizacoes), isNull);
    });

    test('ehValorSemLocalizacaoConhecido reconhece o valor configurado, não os da GETEC', () {
      final perfil = _perfilFicticio();
      expect(perfil.ehValorSemLocalizacaoConhecido('NÃO SE APLICA'), isTrue);
      expect(perfil.ehValorSemLocalizacaoConhecido('INTANGÍVEIS'), isFalse);
    });

    test('nomeOficialConhecido resolve apelido fictício para o nome oficial fictício', () {
      final perfil = _perfilFicticio();
      expect(perfil.nomeOficialConhecido('SALA 2'), 'SALA FICTÍCIA 2');
      expect(perfil.nomeOficialConhecido('DESCONHECIDO'), isNull);
    });
  });

  group('unidade sem sigla oficial (ex.: coordenações de unidade de '
      'conservação que usam só o nome completo) — resolução por nome completo', () {
    // Nomes aqui são FICTÍCIOS, só para o teste — nunca uma unidade real
    // da SEMAD, e nenhuma sigla é inventada em nenhum caso: quando a
    // unidade não tem sigla oficial, [sigla] fica `null` e a busca cai
    // automaticamente para [nomeCompleto] (comparação exata após
    // normalização, nunca fuzzy/parcial).
    const nomeCompletoFicticio = 'COORDENAÇÃO FICTÍCIA DE UNIDADE DE CONSERVAÇÃO SEM SIGLA';

    UnitImportProfile perfilSemSigla() => UnitImportProfile(
      sigla: null,
      nomeCompleto: nomeCompletoFicticio,
      cabecalhosAlvo: const {ImportColumnField.numeroPatrimonio: 'codigo'},
      cabecalhosObrigatoriosDeteccao: const {'codigo'},
      minimoCamposReconhecidosDeteccao: 1,
      motivoPadraoSugerido: 'Carga fictícia sem sigla.',
      mensagemDeteccao: 'Formato fictício sem sigla reconhecido.',
    );

    test('encontrarGerencia resolve pelo nome completo normalizado quando sigla é null', () {
      final setores = [
        Setor(
          id: 'setor-sem-sigla',
          nome: nomeCompletoFicticio,
          sigla: null, // unidade sem sigla cadastrada — caso real documentado.
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
      ];

      expect(perfilSemSigla().encontrarGerencia(setores)?.id, 'setor-sem-sigla');
    });

    test('encontrarGerencia por nome completo tolera variação de caixa/acento/espaço (mesma normalização do projeto)', () {
      final setores = [
        Setor(
          id: 'setor-sem-sigla',
          nome: '  coordenacao ficticia  de   unidade de conservacao sem sigla ',
          sigla: null,
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
      ];

      expect(perfilSemSigla().encontrarGerencia(setores)?.id, 'setor-sem-sigla');
    });

    test('encontrarGerencia por nome completo nunca faz correspondência parcial/fuzzy', () {
      final setores = [
        Setor(
          id: 'setor-parecido',
          nome: 'COORDENAÇÃO FICTÍCIA DE UNIDADE DE CONSERVAÇÃO SEM SIGLA — ANEXO',
          sigla: null,
          ativo: true,
          criadoEm: DateTime(2026, 1, 1),
        ),
      ];

      expect(perfilSemSigla().encontrarGerencia(setores), isNull);
    });

    test('encontrarGerencia continua usando a sigla quando ela está preenchida (sem regressão da GETEC)', () {
      final setores = [
        Setor(id: 'zzz-1', nome: 'Unidade Fictícia Completa', sigla: 'ZZZ', ativo: true, criadoEm: DateTime(2026, 1, 1)),
        Setor(id: 'getec-1', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
      ];
      expect(_perfilFicticio().encontrarGerencia(setores)?.id, 'zzz-1');
    });

    test(
      'ImportPreflight.validarGerenciaUnica resolve por nomeCompleto quando sigla não é informada',
      () {
        final setores = [
          Setor(id: 'setor-sem-sigla', nome: nomeCompletoFicticio, sigla: null, ativo: true, criadoEm: DateTime(2026, 1, 1)),
        ];

        final resultado = ImportPreflight.validarGerenciaUnica(
          setores: setores,
          nomeCompleto: nomeCompletoFicticio,
        );

        expect(resultado.ok, isTrue);
        expect(resultado.issues, isEmpty);
      },
    );

    test(
      'ImportPreflight.validarGerenciaUnica por nomeCompleto também bloqueia ambiguidade e inatividade',
      () {
        final setoresAmbiguos = [
          Setor(id: 'a', nome: nomeCompletoFicticio, sigla: null, ativo: true, criadoEm: DateTime(2026, 1, 1)),
          Setor(id: 'b', nome: nomeCompletoFicticio, sigla: null, ativo: true, criadoEm: DateTime(2026, 1, 1)),
        ];
        final resultadoAmbiguo = ImportPreflight.validarGerenciaUnica(
          setores: setoresAmbiguos,
          nomeCompleto: nomeCompletoFicticio,
        );
        expect(resultadoAmbiguo.ok, isFalse);
        expect(resultadoAmbiguo.issues.single.mensagem, contains('Encontradas 2'));

        final setorInativo = [
          Setor(id: 'a', nome: nomeCompletoFicticio, sigla: null, ativo: false, criadoEm: DateTime(2026, 1, 1)),
        ];
        final resultadoInativo = ImportPreflight.validarGerenciaUnica(
          setores: setorInativo,
          nomeCompleto: nomeCompletoFicticio,
        );
        expect(resultadoInativo.ok, isFalse);
        expect(resultadoInativo.issues.single.mensagem, contains('inativa'));
      },
    );

    test(
      'ImportPreflight.validarGerenciaUnica continua resolvendo por sigla quando ela está preenchida '
      '(sem regressão da GETEC)',
      () {
        final setores = [
          Setor(id: 'getec-1', nome: 'Gerencia de Tecnologia', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1)),
        ];
        final resultado = ImportPreflight.validarGerenciaUnica(setores: setores, sigla: 'GETEC');
        expect(resultado.ok, isTrue);
      },
    );
  });
}
