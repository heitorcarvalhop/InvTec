import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/domain/inventario_rapido.dart';
import 'package:invtec/features/patrimonios/domain/inventario_rapido_relatorio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_scanner.dart';

PatrimonioDetalhe _patrimonio({
  required String id,
  String? numero,
  String? localizacaoAtualId,
  String localizacaoNome = 'Datacenter',
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.disponivel,
      setorAtualId: 'setor-1',
      localizacaoAtualId: localizacaoAtualId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'GETEC',
    localizacaoNome: localizacaoNome,
  );
}

int _contador = 0;
String _gerarId() => 'leitura-${_contador++}';

void main() {
  setUp(() => _contador = 0);

  group('chaveDedupDeResultado', () {
    test('correspondência única usa o id do patrimônio', () {
      final resultado = ScannerResultado.encontradoAtual(
        '123',
        _patrimonio(id: 'abc', numero: '123'),
      );
      expect(chaveDedupDeResultado(resultado), 'patrimonio:abc');
    });

    test(
      'pendência usa a chave normalizada do código (zeros à esquerda '
      'equivalentes — "0123" e "123" nunca geram chaves diferentes)',
      () {
        final a = ScannerResultado.naoEncontrado('0123');
        final b = ScannerResultado.naoEncontrado('123');
        expect(chaveDedupDeResultado(a), chaveDedupDeResultado(b));
      },
    );
  });

  group('registrarLeitura', () {
    test('primeira leitura de um código novo é anexada', () {
      final resultado = ScannerResultado.naoEncontrado('42');
      final leituras = registrarLeitura(
        leituras: const [],
        resultado: resultado,
        agora: DateTime(2026, 1, 1, 10),
        gerarId: _gerarId,
      );
      expect(leituras, hasLength(1));
      expect(leituras.single.status, ScannerResultadoTipo.naoEncontrado);
    });

    test(
      'escanear o MESMO patrimônio duas vezes nunca duplica a linha — '
      'atualiza a já existente (mesmo id, novo lidoEm)',
      () {
        final p = _patrimonio(id: 'abc', numero: '123');
        final primeira = registrarLeitura(
          leituras: const [],
          resultado: ScannerResultado.encontradoAtual('123', p),
          agora: DateTime(2026, 1, 1, 10),
          gerarId: _gerarId,
        );
        final segunda = registrarLeitura(
          leituras: primeira,
          resultado: ScannerResultado.encontradoAtual('0123', p),
          agora: DateTime(2026, 1, 1, 10, 5),
          gerarId: _gerarId,
        );

        expect(segunda, hasLength(1));
        expect(segunda.single.id, primeira.single.id);
        expect(segunda.single.lidoEm, DateTime(2026, 1, 1, 10, 5));
      },
    );

    test(
      'escanear o MESMO código problemático duas vezes também nunca '
      'duplica a linha',
      () {
        final primeira = registrarLeitura(
          leituras: const [],
          resultado: ScannerResultado.naoEncontrado('999'),
          agora: DateTime(2026, 1, 1, 10),
          gerarId: _gerarId,
        );
        final segunda = registrarLeitura(
          leituras: primeira,
          resultado: ScannerResultado.falhaConsulta('999'),
          agora: DateTime(2026, 1, 1, 10, 5),
          gerarId: _gerarId,
        );

        expect(segunda, hasLength(1));
        expect(segunda.single.id, primeira.single.id);
        expect(segunda.single.status, ScannerResultadoTipo.falhaConsulta);
      },
    );

    test('códigos diferentes geram linhas diferentes, preservando ordem', () {
      var leituras = registrarLeitura(
        leituras: const [],
        resultado: ScannerResultado.naoEncontrado('111'),
        agora: DateTime(2026, 1, 1, 10),
        gerarId: _gerarId,
      );
      leituras = registrarLeitura(
        leituras: leituras,
        resultado: ScannerResultado.naoEncontrado('222'),
        agora: DateTime(2026, 1, 1, 10, 1),
        gerarId: _gerarId,
      );

      expect(leituras, hasLength(2));
      expect(leituras[0].codigoLido, '111');
      expect(leituras[1].codigoLido, '222');
    });
  });

  group('removerLeitura', () {
    test('remove a linha pelo id', () {
      final leituras = registrarLeitura(
        leituras: const [],
        resultado: ScannerResultado.naoEncontrado('42'),
        agora: DateTime(2026, 1, 1),
        gerarId: _gerarId,
      );
      final id = leituras.single.id;

      expect(removerLeituraPorId(leituras, id), isEmpty);
    });

    test('remover um id que não existe mais é um no-op', () {
      final leituras = registrarLeitura(
        leituras: const [],
        resultado: ScannerResultado.naoEncontrado('42'),
        agora: DateTime(2026, 1, 1),
        gerarId: _gerarId,
      );

      expect(removerLeituraPorId(leituras, 'inexistente'), leituras);
    });
  });

  group('atualizarLeitura ("tentar de novo"/corrigir)', () {
    test('atualiza a linha em lugar, mantendo o id', () {
      final leituras = registrarLeitura(
        leituras: const [],
        resultado: ScannerResultado.falhaConsulta('42'),
        agora: DateTime(2026, 1, 1, 10),
        gerarId: _gerarId,
      );
      final id = leituras.single.id;
      final p = _patrimonio(id: 'abc', numero: '42');

      final atualizada = atualizarLeitura(
        leituras: leituras,
        id: id,
        resultado: ScannerResultado.encontradoAtual('42', p),
        agora: DateTime(2026, 1, 1, 10, 1),
      );

      expect(atualizada, hasLength(1));
      expect(atualizada.single.id, id);
      expect(atualizada.single.status, ScannerResultadoTipo.encontradoAtual);
    });

    test(
      'quando a releitura colide com outra linha já existente, a linha '
      'de origem é removida — nunca duas linhas para o mesmo patrimônio',
      () {
        final p = _patrimonio(id: 'abc', numero: '42');
        var leituras = registrarLeitura(
          leituras: const [],
          resultado: ScannerResultado.encontradoAtual('42', p),
          agora: DateTime(2026, 1, 1, 10),
          gerarId: _gerarId,
        );
        leituras = registrarLeitura(
          leituras: leituras,
          resultado: ScannerResultado.naoEncontrado('999'),
          agora: DateTime(2026, 1, 1, 10, 1),
          gerarId: _gerarId,
        );
        final idPendencia = leituras
            .firstWhere((l) => l.codigoLido == '999')
            .id;

        // a "correção" da pendência "999" na verdade resolve para o
        // MESMO patrimônio "abc" já capturado pela primeira linha.
        final atualizada = atualizarLeitura(
          leituras: leituras,
          id: idPendencia,
          resultado: ScannerResultado.encontradoAtual('42', p),
          agora: DateTime(2026, 1, 1, 10, 2),
        );

        expect(atualizada, hasLength(1));
        expect(atualizada.single.patrimonioUnico?.patrimonio.id, 'abc');
        expect(atualizada.single.lidoEm, DateTime(2026, 1, 1, 10, 2));
      },
    );

    test('atualizar um id que não existe mais é um no-op', () {
      final leituras = registrarLeitura(
        leituras: const [],
        resultado: ScannerResultado.naoEncontrado('42'),
        agora: DateTime(2026, 1, 1),
        gerarId: _gerarId,
      );

      final resultado = atualizarLeitura(
        leituras: leituras,
        id: 'inexistente',
        resultado: ScannerResultado.naoEncontrado('42'),
        agora: DateTime(2026, 1, 1, 10),
      );

      expect(resultado, leituras);
    });
  });

  group('contagens (total/encontrados/pendências)', () {
    test('ePendencia classifica corretamente cada tipo', () {
      final p = _patrimonio(id: 'abc', numero: '1');
      final resultados = {
        ScannerResultado.encontradoAtual('1', p): false,
        ScannerResultado.encontradoAnterior('1', p): false,
        ScannerResultado.ambiguo('1', [p, p]): true,
        ScannerResultado.naoEncontrado('1'): true,
        ScannerResultado.codigoInvalido('1'): true,
        ScannerResultado.acessoInsuficiente('1'): true,
        ScannerResultado.falhaConsulta('1'): true,
      };

      for (final entry in resultados.entries) {
        final leitura = InventarioLeitura(
          id: 'x',
          chaveDedup: chaveDedupDeResultado(entry.key),
          resultado: entry.key,
          lidoEm: DateTime(2026, 1, 1),
        );
        expect(
          leitura.ePendencia,
          entry.value,
          reason: 'tipo ${entry.key.tipo}',
        );
      }
    });
  });

  group('leituraDivergeDaLocalizacao', () {
    test('diverge quando a localização cadastrada é diferente da selecionada', () {
      final p = _patrimonio(id: 'abc', numero: '1', localizacaoAtualId: 'loc-A');
      final leitura = InventarioLeitura(
        id: 'x',
        chaveDedup: 'patrimonio:abc',
        resultado: ScannerResultado.encontradoAtual('1', p),
        lidoEm: DateTime(2026, 1, 1),
      );

      expect(leituraDivergeDaLocalizacao(leitura, 'loc-B'), isTrue);
      expect(leituraDivergeDaLocalizacao(leitura, 'loc-A'), isFalse);
    });

    test('nunca diverge para uma pendência (sem patrimônio único)', () {
      final leitura = InventarioLeitura(
        id: 'x',
        chaveDedup: 'codigo:1',
        resultado: ScannerResultado.naoEncontrado('1'),
        lidoEm: DateTime(2026, 1, 1),
      );
      expect(leituraDivergeDaLocalizacao(leitura, 'loc-A'), isFalse);
    });
  });

  group('gerarCsvInventario', () {
    test('gera uma linha de cabeçalho e uma por leitura, nunca grava nada', () {
      final p = _patrimonio(
        id: 'abc',
        numero: '42',
        localizacaoAtualId: 'loc-A',
        localizacaoNome: 'Sala A',
      );
      final leituras = [
        InventarioLeitura(
          id: 'l1',
          chaveDedup: 'patrimonio:abc',
          resultado: ScannerResultado.encontradoAtual('42', p),
          lidoEm: DateTime(2026, 3, 1, 9, 30),
        ),
        InventarioLeitura(
          id: 'l2',
          chaveDedup: 'codigo:999',
          resultado: ScannerResultado.naoEncontrado('999'),
          lidoEm: DateTime(2026, 3, 1, 9, 31),
        ),
      ];

      final csv = gerarCsvInventario(
        localizacaoSelecionadaNome: 'Sala B',
        localizacaoSelecionadaId: 'loc-B',
        leituras: leituras,
      );

      final linhas = csv.trim().split('\r\n');
      expect(linhas, hasLength(3)); // cabeçalho + 2 leituras
      expect(linhas[0], contains('Código lido'));
      expect(linhas[1], contains('42'));
      expect(linhas[1], contains('Sala A'));
      expect(linhas[1], contains('Sala B'));
      expect(linhas[1], contains('SIM')); // loc-A != loc-B
      expect(linhas[2], contains('999'));
      expect(linhas[2], contains('Não encontrado'));
    });
  });
}
