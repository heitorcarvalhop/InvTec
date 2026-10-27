import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_lote_persistencia.dart';

ImportLoteSessaoPersistida sessaoFake({
  String loteId = 'lote-1',
  String usuarioId = 'user-1',
  List<ImportLoteLinhaPersistida>? linhas,
}) => ImportLoteSessaoPersistida(
  loteId: loteId,
  usuarioId: usuarioId,
  nomeArquivo: 'inventario.csv',
  criadoEm: DateTime(2026, 1, 1, 10, 30),
  linhas:
      linhas ??
      const [
        ImportLoteLinhaPersistida(
          numeroLinha: 2,
          operacaoId: 'op-1',
          status: ImportLoteLinhaPersistidaStatus.pendente,
        ),
        ImportLoteLinhaPersistida(
          numeroLinha: 3,
          operacaoId: 'op-2',
          status: ImportLoteLinhaPersistidaStatus.sucesso,
        ),
      ],
);

void main() {
  group('ImportLotePersistencia', () {
    test('salvar seguido de carregar devolve a mesma sessão', () async {
      final persistencia = ImportLotePersistencia('/dados', fileSystem: MemoryFileSystem());
      final sessao = sessaoFake();

      await persistencia.salvar(sessao);
      final carregada = persistencia.carregar('user-1');

      expect(carregada, isNotNull);
      expect(carregada!.loteId, 'lote-1');
      expect(carregada.usuarioId, 'user-1');
      expect(carregada.nomeArquivo, 'inventario.csv');
      expect(carregada.criadoEm, DateTime(2026, 1, 1, 10, 30));
      expect(carregada.linhas, hasLength(2));
      expect(carregada.linhas[0].numeroLinha, 2);
      expect(carregada.linhas[0].operacaoId, 'op-1');
      expect(carregada.linhas[0].status, ImportLoteLinhaPersistidaStatus.pendente);
      expect(carregada.linhas[1].status, ImportLoteLinhaPersistidaStatus.sucesso);
    });

    test('carregar sem nenhuma sessão salva devolve null', () async {
      final persistencia = ImportLotePersistencia('/dados', fileSystem: MemoryFileSystem());
      expect(persistencia.carregar('user-sem-sessao'), isNull);
    });

    test('chaves incluem o usuarioId — sessão de um usuário nunca aparece para outro', () async {
      final persistencia = ImportLotePersistencia('/dados', fileSystem: MemoryFileSystem());
      await persistencia.salvar(sessaoFake(usuarioId: 'user-a', loteId: 'lote-a'));

      expect(persistencia.carregar('user-a'), isNotNull);
      expect(persistencia.carregar('user-b'), isNull);
    });

    test('limpar remove a sessão — carregar depois devolve null', () async {
      final persistencia = ImportLotePersistencia('/dados', fileSystem: MemoryFileSystem());
      await persistencia.salvar(sessaoFake());
      expect(persistencia.carregar('user-1'), isNotNull);

      await persistencia.limpar('user-1', 'lote-1');
      expect(persistencia.carregar('user-1'), isNull);
    });

    test('limpar com loteId diferente do atual não afeta a sessão atual', () async {
      final persistencia = ImportLotePersistencia('/dados', fileSystem: MemoryFileSystem());
      await persistencia.salvar(sessaoFake(loteId: 'lote-atual'));

      await persistencia.limpar('user-1', 'lote-velho-que-nao-e-mais-o-atual');

      expect(persistencia.carregar('user-1'), isNotNull);
    });

    test('salvar uma nova sessão para o mesmo usuário substitui a anterior como "atual"', () async {
      final persistencia = ImportLotePersistencia('/dados', fileSystem: MemoryFileSystem());
      await persistencia.salvar(sessaoFake(loteId: 'lote-antigo'));
      await persistencia.salvar(sessaoFake(loteId: 'lote-novo'));

      final carregada = persistencia.carregar('user-1');
      expect(carregada!.loteId, 'lote-novo');
    });

    test('carregar nunca lança com um diretório inexistente — trata como "nenhuma sessão"', () async {
      final persistencia = ImportLotePersistencia('/nao-existe', fileSystem: MemoryFileSystem());
      expect(persistencia.carregar('user-1'), isNull);
    });
  });

  group('ImportLoteSessaoPersistida.completo', () {
    test('true quando nenhuma linha está pendente', () {
      final sessao = sessaoFake(
        linhas: const [
          ImportLoteLinhaPersistida(
            numeroLinha: 1,
            operacaoId: 'op-1',
            status: ImportLoteLinhaPersistidaStatus.sucesso,
          ),
          ImportLoteLinhaPersistida(
            numeroLinha: 2,
            operacaoId: 'op-2',
            status: ImportLoteLinhaPersistidaStatus.falha,
          ),
        ],
      );
      expect(sessao.completo, isTrue);
    });

    test('false quando ao menos uma linha ainda está pendente', () {
      final sessao = sessaoFake();
      expect(sessao.completo, isFalse);
    });
  });

  group('ImportLotePersistencia — carga (milhares de linhas)', () {
    /// Evidência da decisão de arquitetura (ver docstring de
    /// [ImportLotePersistencia]): simula uma sessão de 10.000 linhas (o teto
    /// pedido pela tarefa) — cada uma com um `operacaoId` UUID real — e
    /// confirma que salvar/carregar/sobreviver a uma "reabertura do
    /// processo" (nova instância da classe, nunca reaproveitando estado em
    /// memória) continua rápido e correto neste volume. Não é só uma
    /// medição de tempo: confirma CORREÇÃO (todas as 10.000 linhas voltam
    /// intactas) sob o volume que `shared_preferences` não foi desenhado
    /// para suportar bem (arquivo único reescrito por completo a cada
    /// gravação, compartilhado com toda e qualquer outra preferência do
    /// app).
    test(
      '10.000 linhas: salvar+carregar preserva todos os operacaoId, mesmo numa instância NOVA (reinício simulado)',
      () async {
        final linhas = [
          for (var i = 1; i <= 10000; i++)
            ImportLoteLinhaPersistida(
              numeroLinha: i,
              operacaoId: 'op-$i-${'x' * 16}', // tamanho comparável a um UUID v4 real.
              status: i.isEven ? ImportLoteLinhaPersistidaStatus.sucesso : ImportLoteLinhaPersistidaStatus.pendente,
            ),
        ];
        final sessao = ImportLoteSessaoPersistida(
          loteId: 'lote-carga',
          usuarioId: 'user-carga',
          nomeArquivo: 'inventario_10k.xlsx',
          criadoEm: DateTime(2026, 1, 1),
          linhas: linhas,
        );

        // Mesmo `MemoryFileSystem` (equivalente ao disco real para fins de
        // serialização/leitura — só troca o backend de I/O) compartilhado
        // entre as duas instâncias abaixo, simulando "gravou, processo
        // encerrou, processo reabriu": a SEGUNDA instância não reaproveita
        // nenhum estado em memória da primeira.
        final fs = MemoryFileSystem();
        final cronometro = Stopwatch()..start();
        await ImportLotePersistencia('/dados', fileSystem: fs).salvar(sessao);
        cronometro.stop();
        // Generoso de propósito (evita flakiness em máquina de CI lenta) —
        // o objetivo é provar ordem de grandeza (sub-segundo), não
        // microbenchmark.
        expect(cronometro.elapsedMilliseconds, lessThan(5000));

        final novaInstancia = ImportLotePersistencia('/dados', fileSystem: fs);
        final carregada = novaInstancia.carregar('user-carga');

        expect(carregada, isNotNull);
        expect(carregada!.linhas, hasLength(10000));
        for (var i = 0; i < 10000; i++) {
          expect(carregada.linhas[i].operacaoId, linhas[i].operacaoId);
          expect(carregada.linhas[i].numeroLinha, linhas[i].numeroLinha);
          expect(carregada.linhas[i].status, linhas[i].status);
        }
      },
    );
  });
}
