import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_scanner.dart';

import 'fake_patrimonio_repository.dart';

/// Mesmo fixture de `patrimonios_controller_test.dart` — mínimo necessário
/// para exercitar [resolverCodigoEscaneado], que só olha
/// `numeroPatrimonio`/`id`.
PatrimonioDetalhe _patrimonio({
  required String id,
  String? numero,
  DateTime? dataCadastro,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-1',
      dataCadastro: dataCadastro ?? DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Tipo',
    setorNome: 'Setor',
  );
}

void main() {
  group('resolverCodigoEscaneado', () {
    test(
      'tombamento atual: etiqueta com zeros à esquerda encontra o '
      'patrimônio cadastrado sem eles (exemplo SEMAD: 03583777 -> 3583777)',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'p1', numero: '3583777')],
        );

        final resultado = await resolverCodigoEscaneado(repo, '03583777');

        expect(resultado.tipo, ScannerResultadoTipo.encontradoAtual);
        expect(resultado.encontrados.single.patrimonio.id, 'p1');
        // o código lido (bruto, com zero) é preservado — nunca a chave
        // normalizada — para exibição fiel e para o fallback de cadastro.
        expect(resultado.codigoLido, '03583777');
      },
    );

    test('tombamento atual: correspondência exata direta', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '12345')],
      );

      final resultado = await resolverCodigoEscaneado(repo, '12345');

      expect(resultado.tipo, ScannerResultadoTipo.encontradoAtual);
      expect(resultado.encontrados.single.patrimonio.id, 'p1');
    });

    test(
      'nunca decide pela identidade por SUBSTRING: "3636" não deve '
      'confundir com "13636360" quando não há correspondência EXATA',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'p1', numero: '13636360')],
        );

        final resultado = await resolverCodigoEscaneado(repo, '3636');

        // a busca de candidatos (ILIKE) encontraria "13636360" por
        // substring, mas a igualdade normalizada rejeita -> não encontrado,
        // nunca "encontradoAtual" por engano.
        expect(resultado.tipo, ScannerResultadoTipo.naoEncontrado);
      },
    );

    test(
      'mais de um patrimônio com o MESMO tombamento atual (anomalia de '
      'dados) nunca escolhe um automaticamente',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [
            _patrimonio(id: 'p1', numero: '555'),
            _patrimonio(id: 'p2', numero: '0555'),
          ],
        );

        final resultado = await resolverCodigoEscaneado(repo, '555');

        expect(resultado.tipo, ScannerResultadoTipo.ambiguo);
        expect(resultado.encontrados.map((e) => e.patrimonio.id), {
          'p1',
          'p2',
        });
      },
    );

    test(
      'tombamento anterior: encontrado só depois de não achar nada no '
      'tombamento atual',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'p1', numero: '999')],
          historicoAnterior: {
            '0777': [('p1', 'MANUAL')],
          },
        );

        final resultado = await resolverCodigoEscaneado(repo, '777');

        expect(resultado.tipo, ScannerResultadoTipo.encontradoAnterior);
        expect(resultado.encontrados.single.patrimonio.id, 'p1');
      },
    );

    test('mais de um patrimônio pelo tombamento anterior é ambíguo', () async {
      final repo = FakePatrimonioRepository(
        itens: [
          _patrimonio(id: 'p1', numero: '111'),
          _patrimonio(id: 'p2', numero: '222'),
        ],
        historicoAnterior: {
          '777': [('p1', 'MANUAL'), ('p2', 'IMPORTACAO_PLANILHA')],
        },
      );

      final resultado = await resolverCodigoEscaneado(repo, '777');

      expect(resultado.tipo, ScannerResultadoTipo.ambiguo);
      expect(resultado.encontrados.length, 2);
    });

    test('nenhuma correspondência: candidato a cadastro novo', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '111')],
      );

      final resultado = await resolverCodigoEscaneado(repo, '222');

      expect(resultado.tipo, ScannerResultadoTipo.naoEncontrado);
      expect(resultado.codigoLido, '222');
    });

    test('código vazio é inválido e nunca consulta o repositório', () async {
      final repo = FakePatrimonioRepository();

      final resultado = await resolverCodigoEscaneado(repo, '   ');

      expect(resultado.tipo, ScannerResultadoTipo.codigoInvalido);
    });

    test('código só de zeros é inválido e nunca consulta o repositório', () async {
      final repo = FakePatrimonioRepository();

      final resultado = await resolverCodigoEscaneado(repo, '0000');

      expect(resultado.tipo, ScannerResultadoTipo.codigoInvalido);
    });

    test(
      'tombamento não-numérico (ex.: legado "TI-769") usa igualdade exata, '
      'nunca a regra de zeros à esquerda',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'p1', numero: 'TI-769')],
        );

        final resultado = await resolverCodigoEscaneado(repo, 'ti-769');

        expect(resultado.tipo, ScannerResultadoTipo.encontradoAtual);
        expect(resultado.encontrados.single.patrimonio.id, 'p1');
      },
    );

    test(
      'PAGINAÇÃO NUNCA produz um falso "não encontrado": o patrimônio '
      'verdadeiro é achado mesmo com 60 outros cadastros compartilhando a '
      'mesma sequência de dígitos como substring E cadastrados depois '
      'dele (a ordenação padrão de [PatrimonioRepository.listar] é '
      '"cadastro mais recente primeiro" — um `limit` de página o '
      'deixaria de fora; [buscarPorTombamentoAtualExato] nunca pagina, '
      'então nunca tem esse risco)',
      () async {
        final decoys = List.generate(
          60,
          (i) => _patrimonio(
            id: 'decoy-$i',
            numero: '13583777${i.toString().padLeft(2, '0')}',
            dataCadastro: DateTime(2026, 6, 1),
          ),
        );
        final real = _patrimonio(
          id: 'real',
          numero: '3583777',
          dataCadastro: DateTime(2020, 1, 1), // o mais antigo de todos
        );
        final repo = FakePatrimonioRepository(itens: [...decoys, real]);

        final resultado = await resolverCodigoEscaneado(repo, '03583777');

        expect(resultado.tipo, ScannerResultadoTipo.encontradoAtual);
        expect(resultado.encontrados.single.patrimonio.id, 'real');
      },
    );

    test(
      'acesso insuficiente na busca pelo tombamento ATUAL nunca é '
      'confundido com "não encontrado" (nunca oferece cadastro)',
      () async {
        final repo = FakePatrimonioRepository(
          erroBuscarTombamentoAtualExato: const AcessoInsuficienteException(
            'Você não possui permissão para realizar esta operação.',
          ),
        );

        final resultado = await resolverCodigoEscaneado(repo, '42');

        expect(resultado.tipo, ScannerResultadoTipo.acessoInsuficiente);
      },
    );

    test(
      'acesso insuficiente na busca pelo tombamento ANTERIOR (depois do '
      'atual não achar nada) também nunca é confundido com "não '
      'encontrado"',
      () async {
        final repo = FakePatrimonioRepository(
          erroHistoricoAnterior: const AcessoInsuficienteException(
            'Você não possui permissão para realizar esta operação.',
          ),
        );

        final resultado = await resolverCodigoEscaneado(repo, '42');

        expect(resultado.tipo, ScannerResultadoTipo.acessoInsuficiente);
      },
    );

    test(
      'falha de rede/consulta (qualquer outro erro) nunca é confundida '
      'com "não encontrado" — nunca oferece cadastro como consequência de '
      'uma falha',
      () async {
        final repo = FakePatrimonioRepository(
          erroBuscarTombamentoAtualExato: const AppException('Falha simulada de rede.'),
        );

        final resultado = await resolverCodigoEscaneado(repo, '42');

        expect(resultado.tipo, ScannerResultadoTipo.falhaConsulta);
      },
    );

    test(
      'falha de rede na busca pelo tombamento ANTERIOR também classifica '
      'como falhaConsulta, nunca como naoEncontrado',
      () async {
        final repo = FakePatrimonioRepository(
          erroHistoricoAnterior: const AppException('Falha simulada de rede.'),
        );

        final resultado = await resolverCodigoEscaneado(repo, '42');

        expect(resultado.tipo, ScannerResultadoTipo.falhaConsulta);
      },
    );
  });
}
