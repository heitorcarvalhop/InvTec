import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_scanner.dart';
import 'package:invtec/features/patrimonios/presentation/inventario_rapido_controller.dart';

import 'fake_patrimonio_repository.dart';

PatrimonioDetalhe _patrimonio({
  required String id,
  String? numero,
  String? localizacaoAtualId,
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
  );
}

ProviderContainer _criarContainer(FakePatrimonioRepository repo) {
  final container = ProviderContainer(
    overrides: [patrimonioRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(inventarioRapidoControllerProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('sessão', () {
    test('começa sem sessão ativa (null) até iniciarSessao', () {
      final container = _criarContainer(FakePatrimonioRepository());
      expect(container.read(inventarioRapidoControllerProvider), isNull);

      container
          .read(inventarioRapidoControllerProvider.notifier)
          .iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

      final estado = container.read(inventarioRapidoControllerProvider);
      expect(estado, isNotNull);
      expect(estado!.localizacaoId, 'loc-1');
      expect(estado.leituras, isEmpty);
      expect(estado.totalLeituras, 0);
    });

    test('encerrarSessao volta para null', () {
      final container = _criarContainer(FakePatrimonioRepository());
      final notifier = container.read(inventarioRapidoControllerProvider.notifier);
      notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');
      notifier.encerrarSessao();

      expect(container.read(inventarioRapidoControllerProvider), isNull);
    });
  });

  group('processarCodigo', () {
    test(
      'patrimônio encontrado entra na lista e conta como encontrado, '
      'nunca como pendência',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '3583777')],
        );
        final container = _criarContainer(repo);
        final notifier = container.read(inventarioRapidoControllerProvider.notifier);
        notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

        await notifier.processarCodigo('03583777');

        final estado = container.read(inventarioRapidoControllerProvider)!;
        expect(estado.totalLeituras, 1);
        expect(estado.totalEncontrados, 1);
        expect(estado.totalPendencias, 0);
        expect(estado.leituras.single.patrimonioUnico?.patrimonio.id, 'abc');
        expect(estado.processando, isFalse);
      },
    );

    test(
      'escanear o MESMO patrimônio várias vezes continua contando como '
      '1 leitura (nunca duplica)',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final container = _criarContainer(repo);
        final notifier = container.read(inventarioRapidoControllerProvider.notifier);
        notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

        await notifier.processarCodigo('42');
        await notifier.processarCodigo('042');
        await notifier.processarCodigo('42');

        final estado = container.read(inventarioRapidoControllerProvider)!;
        expect(estado.totalLeituras, 1);
      },
    );

    test('tombamento anterior conta como encontrado, nunca pendência', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'abc', numero: '999')],
        historicoAnterior: {
          '777': [('abc', 'MANUAL')],
        },
      );
      final container = _criarContainer(repo);
      final notifier = container.read(inventarioRapidoControllerProvider.notifier);
      notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

      await notifier.processarCodigo('777');

      final estado = container.read(inventarioRapidoControllerProvider)!;
      expect(estado.totalEncontrados, 1);
      expect(estado.totalPendencias, 0);
      expect(
        estado.leituras.single.status,
        ScannerResultadoTipo.encontradoAnterior,
      );
    });

    test(
      'não encontrado, ambíguo, código inválido, acesso insuficiente e '
      'falha de consulta contam todos como PENDÊNCIA',
      () async {
        final repo = FakePatrimonioRepository(
          itens: [
            _patrimonio(id: 'p1', numero: '42'),
            _patrimonio(id: 'p2', numero: '042'),
          ],
        );
        final container = _criarContainer(repo);
        final notifier = container.read(inventarioRapidoControllerProvider.notifier);
        notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

        await notifier.processarCodigo('42'); // ambíguo (p1 e p2)
        await notifier.processarCodigo('555'); // não encontrado
        await notifier.processarCodigo('   '); // código inválido

        final estado = container.read(inventarioRapidoControllerProvider)!;
        expect(estado.totalLeituras, 3);
        expect(estado.totalEncontrados, 0);
        expect(estado.totalPendencias, 3);
      },
    );

    test('nunca dispara uma segunda consulta enquanto uma já está em voo', () async {
      final completer = Completer<List<PatrimonioDetalhe>>();
      final repo = _RepositorioTravadoNaBuscaAtual(completer);
      final container = _criarContainer(repo);
      final notifier = container.read(inventarioRapidoControllerProvider.notifier);
      notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

      final primeira = notifier.processarCodigo('42');
      // segunda chamada enquanto a primeira ainda não respondeu
      await notifier.processarCodigo('42');

      expect(repo.chamadas, 1);

      completer.complete([_patrimonio(id: 'abc', numero: '42')]);
      await primeira;

      final estado = container.read(inventarioRapidoControllerProvider)!;
      expect(estado.totalLeituras, 1);
    });
  });

  group('removerLeitura', () {
    test('remove a linha da sessão', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      final notifier = container.read(inventarioRapidoControllerProvider.notifier);
      notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

      await notifier.processarCodigo('42');
      final id = container.read(inventarioRapidoControllerProvider)!.leituras.single.id;

      notifier.removerLeitura(id);

      expect(container.read(inventarioRapidoControllerProvider)!.leituras, isEmpty);
    });
  });

  group('tentarNovamente', () {
    test(
      'corrige uma pendência depois que o patrimônio passa a ser '
      'encontrado (ex.: falha de rede passageira na primeira tentativa)',
      () async {
        final repo = _RepositorioComFalhaNaPrimeiraBuscaAtual(
          itens: [_patrimonio(id: 'abc', numero: '42')],
        );
        final container = _criarContainer(repo);
        final notifier = container.read(inventarioRapidoControllerProvider.notifier);
        notifier.iniciarSessao(localizacaoId: 'loc-1', localizacaoNome: 'Sala A');

        await notifier.processarCodigo('42');
        var estado = container.read(inventarioRapidoControllerProvider)!;
        expect(estado.totalPendencias, 1);
        final id = estado.leituras.single.id;

        await notifier.tentarNovamente(id);

        estado = container.read(inventarioRapidoControllerProvider)!;
        expect(estado.totalPendencias, 0);
        expect(estado.totalEncontrados, 1);
        expect(estado.leituras.single.id, id);
      },
    );
  });
}

class _RepositorioTravadoNaBuscaAtual extends FakePatrimonioRepository {
  _RepositorioTravadoNaBuscaAtual(this._gate);
  final Completer<List<PatrimonioDetalhe>> _gate;
  int chamadas = 0;

  @override
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(
    String codigo,
  ) async {
    chamadas++;
    return _gate.future;
  }
}

class _RepositorioComFalhaNaPrimeiraBuscaAtual extends FakePatrimonioRepository {
  _RepositorioComFalhaNaPrimeiraBuscaAtual({super.itens});
  bool _primeiraChamada = true;

  @override
  Future<List<PatrimonioDetalhe>> buscarPorTombamentoAtualExato(
    String codigo,
  ) async {
    if (_primeiraChamada) {
      _primeiraChamada = false;
      throw const AppException('Falha simulada de rede.');
    }
    return super.buscarPorTombamentoAtualExato(codigo);
  }
}
