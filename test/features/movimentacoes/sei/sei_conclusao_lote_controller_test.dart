import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/application/sei_conclusao_erros.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_decisao_campo.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/sei_conclusao_lote_controller.dart';

import '../../auth/fake_auth_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// `SeiConclusaoLoteController`: congelamento da
/// decisão, geração única de `loteId`, prevenção de chamadas concorrentes,
/// retry seguro sobre resultado desconhecido (incluindo reconciliação com
/// validação de identidade completa) e isolamento entre documentos/sessões.
/// NENHUM teste aqui monta widget (`pumpWidget`/`testWidgets`) — é só
/// estado + orquestração, testado via `ProviderContainer`, mesmo padrão de
/// `sei_pendencia_salvar_controller_test.dart`. NENHUM Supabase real,
/// nenhum patrimônio do Despacho 577.
void main() {
  late FakeDocumentosSeiRepository repo;
  late FakeAuthRepository authRepo;
  late ProviderContainer container;
  var geradorChamadas = 0;
  String Function() geradorDeLoteId = () {
    geradorChamadas++;
    return 'lote-$geradorChamadas';
  };

  // Provider de TESTE — a mesma classe do provider de produção
  // (`seiConclusaoLoteControllerProvider`), mas com o gerador de `loteId`
  // injetado (determinístico), para os testes provarem "gerado uma única
  // vez" sem depender de UUIDs aleatórios.
  final testeControllerProvider = NotifierProvider<SeiConclusaoLoteController, SeiConclusaoLoteState>(
    () => SeiConclusaoLoteController(gerarLoteId: () => geradorDeLoteId()),
  );

  setUp(() async {
    geradorChamadas = 0;
    repo = FakeDocumentosSeiRepository(
      documentosIniciais: [
        _documento(
          id: 'doc-1',
          versao: 1,
          itens: [_item(id: 'item-1', patrimonioId: 'pat-1'), _item(id: 'item-2', patrimonioId: 'pat-2')],
        ),
        _documento(id: 'doc-2', versao: 1, itens: [_item(id: 'item-3', patrimonioId: 'pat-3', documentoId: 'doc-2')]),
      ],
    );
    authRepo = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (id) => _perfil(id));
    container = ProviderContainer(
      overrides: [
        documentosSeiRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(authRepo),
      ],
    );
    // Espera a sessão de auth SE ESTABILIZAR antes de qualquer teste tocar
    // no controller de lote: `SeiConclusaoLoteController.build()` lê
    // `authControllerProvider` uma vez, de forma síncrona — sem isto, a
    // resolução assíncrona do perfil (`fetchProfile`) poderia terminar
    // DEPOIS de um `confirmar()` já ter alterado o estado, disparando o
    // `ref.listen` do controller e resetando um estado que acabou de ser
    // definido (a mesma corrida que a implementação evita em produção).
    await container.read(authControllerProvider.future);
  });

  tearDown(() {
    container.dispose();
    authRepo.dispose();
  });

  group('congelamento dos parâmetros', () {
    test('a decisão confirmada guarda os 6 campos, com itemIds canônico (distinto e ordenado)', () async {
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-2', 'item-1', 'item-2'], // fora de ordem + repetido
        versaoEsperada: 1,
        observacao: '  entrega em lote  ',
        confirmarLimpezaDestino: true,
      );

      final decisao = container.read(testeControllerProvider).decisao!;
      expect(decisao.documentoId, 'doc-1');
      expect(decisao.itemIds, ['item-1', 'item-2']); // canonicalizado
      expect(decisao.versaoEsperada, 1);
      expect(decisao.observacao, '  entrega em lote  '); // congelado tal como recebido (a normalização é do repositório)
      expect(decisao.confirmarLimpezaDestino, isTrue);
    });
  });

  group('geração única de loteId', () {
    test('gerado 1x por decisão confirmada — retry NUNCA gera outro', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);

      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(geradorChamadas, 1);
      final loteIdOriginal = container.read(testeControllerProvider).decisao!.loteId;
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

      repo.falhaNaConclusao = null;
      await notifier.retry();

      expect(geradorChamadas, 1); // nenhuma chamada nova ao gerador
      expect(container.read(testeControllerProvider).decisao!.loteId, loteIdOriginal);
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.sucesso);
    });

    test('confirmar() enquanto executando OU com tentativa pendente NUNCA gera um loteId novo', () async {
      repo.aguardarConclusao = null;
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);

      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(geradorChamadas, 1);

      // Tentativa pendente (resultadoDesconhecido): uma nova seleção
      // confirmada é IGNORADA — nunca substitui a decisão congelada.
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(geradorChamadas, 1);
      expect(container.read(testeControllerProvider).decisao!.itemIds, ['item-1']);
    });
  });

  group('prevenção de chamadas concorrentes', () {
    test('um segundo confirmar() durante uma chamada em andamento não dispara uma segunda chamada à RPC', () async {
      final espera = Completer<void>();
      repo.aguardarConclusao = espera;
      final notifier = container.read(testeControllerProvider.notifier);

      final primeira = notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      // A chamada já está em voo (presa no `Completer`) — o estado já deve
      // refletir "executando" antes mesmo de aguardar a Future acima.
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.executando);

      // Clique duplo: NENHUM efeito enquanto a primeira não terminou.
      final segunda = notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );

      espera.complete();
      await primeira;
      await segunda;

      expect(repo.concluirLoteCallCount, 1);
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.sucesso);
      expect(container.read(testeControllerProvider).decisao!.itemIds, ['item-1']);
    });
  });

  group('timeout / resultado desconhecido e retry com payload idêntico', () {
    test('resultado desconhecido preserva a decisão; retry reenvia EXATAMENTE o mesmo payload', () async {
      repo.falhaNaConclusao = Exception('conexão perdida');
      final notifier = container.read(testeControllerProvider.notifier);

      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1', 'item-2'],
        versaoEsperada: 1,
        observacao: 'obs',
        confirmarLimpezaDestino: false,
      );

      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(container.read(testeControllerProvider).temTentativaPendente, isTrue);
      expect(repo.concluirLoteCallCount, 1);

      repo.falhaNaConclusao = null;
      await notifier.retry();

      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.sucesso);
      expect(repo.concluirLoteCallCount, 2);
      // As duas chamadas usaram EXATAMENTE o mesmo payload — mesmo loteId,
      // mesmos itemIds, mesma versaoEsperada, mesma observação.
      expect(repo.conclusoesLote[0], repo.conclusoesLote[1]);
    });

    test('reiniciar() é ignorado enquanto houver tentativa pendente (nunca descarta silenciosamente)', () async {
      repo.falhaNaConclusao = Exception('timeout');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );

      notifier.reiniciar();

      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(container.read(testeControllerProvider).decisao, isNotNull);
    });
  });

  group('preservação da tentativa ao "fechar e reabrir" (o provider sobrevive sem .autoDispose)', () {
    test('reler o estado repetidas vezes (equivalente a reabrir o diálogo) não perde a tentativa pendente', () async {
      repo.falhaNaConclusao = Exception('timeout');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      final loteIdOriginal = container.read(testeControllerProvider).decisao!.loteId;

      // Simula fechar/reabrir o diálogo: várias leituras do MESMO provider,
      // sem nenhuma chamada nova.
      for (var i = 0; i < 5; i++) {
        final estado = container.read(testeControllerProvider);
        expect(estado.temTentativaPendente, isTrue);
        expect(estado.decisao!.loteId, loteIdOriginal);
      }
      expect(repo.concluirLoteCallCount, 1); // nenhuma chamada nova só de reler
    });
  });

  group('reconciliação — buscarLotePorId', () {
    test('reconciliar() encontra o registro: a tentativa TINHA sido aplicada, mesmo sem resposta ao cliente', () async {
      // Simula que o SERVIDOR já processou esta decisão (mesmo loteId e
      // mesmos parâmetros) antes de o cliente perceber que a chamada
      // anterior tinha caído — chamando o repositório diretamente, como se
      // fosse a mesma requisição já aplicada no backend.
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-fixo',
        confirmarLimpezaDestino: false,
      );

      geradorDeLoteId = () => 'lote-fixo';
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

      repo.falhaNaConclusao = null;
      await notifier.reconciliar();

      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.sucesso);
      expect(container.read(testeControllerProvider).resultado!.documentoId, 'doc-1');
      // 2 chamadas a `concluirItensLote` (a semeadura direta + a tentativa
      // do controller que falhou como "desconhecida") — a RECONCILIAÇÃO em
      // si não fez NENHUMA chamada nova a ela, só a leitura por `loteId`.
      expect(repo.concluirLoteCallCount, 2);
      expect(repo.buscarLotePorIdCallCount, 1);
    });

    test('reconciliar() não encontra nada: a tentativa REALMENTE não foi aplicada, continua pendente', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );

      await notifier.reconciliar();

      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(container.read(testeControllerProvider).temTentativaPendente, isTrue);
    });
  });

  group('reconciliar() devolve o desfecho da consulta (mesma state, retorno a mais)', () {
    test('registro não encontrado: devolve aindaDesconhecido — state.status permanece resultadoDesconhecido, idêntico a antes', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );

      final resultado = await notifier.reconciliar();

      expect(resultado, SeiReconciliacaoResultado.aindaDesconhecido);
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(container.read(testeControllerProvider).temTentativaPendente, isTrue);
    });

    test('a PRÓPRIA consulta falha (rede/permissão): devolve falhaDeConsulta — diferente de aindaDesconhecido, mesma state.status', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );

      repo.falhaAoBuscarLote = Exception('rede indisponível');
      final resultado = await notifier.reconciliar();

      expect(resultado, SeiReconciliacaoResultado.falhaDeConsulta);
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(container.read(testeControllerProvider).temTentativaPendente, isTrue);
      // A decisão continua intocada — nenhum loteId novo, nenhuma perda de
      // dado, mesmo com a consulta em si falhando.
      expect(container.read(testeControllerProvider).decisao!.itemIds, ['item-1']);
    });

    test('registro encontrado e idêntico: devolve sucesso (state.status já muda sozinho)', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      final loteId = container.read(testeControllerProvider).decisao!.loteId;
      repo.falhaNaConclusao = null;
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: loteId,
        confirmarLimpezaDestino: false,
      );

      final resultado = await notifier.reconciliar();

      expect(resultado, SeiReconciliacaoResultado.sucesso);
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.sucesso);
    });

    test('registro encontrado mas divergente: devolve conflito (state.status já muda sozinho)', () async {
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: 'lote-fixo',
        confirmarLimpezaDestino: false,
      );
      geradorDeLoteId = () => 'lote-fixo';
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      repo.falhaNaConclusao = null;

      final resultado = await notifier.reconciliar();

      expect(resultado, SeiReconciliacaoResultado.conflito);
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
    });

    test('sem tentativa pendente: devolve semEfeito, nenhuma consulta é feita', () async {
      final notifier = container.read(testeControllerProvider.notifier);
      final chamadasAntes = repo.buscarLotePorIdCallCount;

      final resultado = await notifier.reconciliar();

      expect(resultado, SeiReconciliacaoResultado.semEfeito);
      expect(repo.buscarLotePorIdCallCount, chamadasAntes);
    });
  });

  group('reconciliação: identidade completa, nunca só o loteId', () {
    test('mesmo lote_id, mas o registro encontrado tem parâmetros DIFERENTES: bloqueia, nunca aceita', () async {
      // Semeia um registro real para 'lote-fixo', mas com uma seleção de
      // itens DIFERENTE da que a decisão local vai congelar a seguir —
      // simula um `lote_id` reaproveitado (bug ou colisão) para outra
      // operação.
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: 'lote-fixo',
        confirmarLimpezaDestino: false,
      );

      geradorDeLoteId = () => 'lote-fixo';
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'], // seleção DIFERENTE da semeada
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

      repo.falhaNaConclusao = null;
      final loteIdOriginal = container.read(testeControllerProvider).decisao!.loteId;
      final chamadasAntes = repo.concluirLoteCallCount;
      await notifier.reconciliar();

      final estado = container.read(testeControllerProvider);
      // NUNCA aceita o resultado alheio como se fosse
      // desta decisão, e NUNCA vira uma recusa "encerrada": uma divergência
      // descoberta por leitura/comparação no cliente não tem a mesma
      // garantia de "nada foi escrito" que uma recusa SÍNCRONA do servidor
      // tem — fica marcada como conflito de integridade, exigindo
      // investigação, nunca resolvida sozinha.
      expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(estado.emConflitoDeIntegridade, isTrue);
      expect(estado.falha!.codigo, 'P0037');
      // A tentativa original — loteId e os parâmetros congelados — segue
      // intacta, nunca descartada nem substituída.
      expect(estado.temTentativaPendente, isTrue);
      expect(estado.decisao!.loteId, loteIdOriginal);
      expect(estado.decisao!.itemIds, ['item-1']);

      // NENHUMA ação automática a partir daqui: nem reiniciar()...
      notifier.reiniciar();
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(container.read(testeControllerProvider).decisao, isNotNull);
      // ...nem retry()...
      await notifier.retry();
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      // ...nem reconciliar() de novo — NENHUMA chamada nova à RPC de
      // escrita, em nenhum dos casos acima.
      await notifier.reconciliar();
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(repo.concluirLoteCallCount, chamadasAntes);

      // item-1 (a seleção REAL desta decisão) continua intocado.
      expect((await repo.obterPorId('doc-1')).itens.firstWhere((i) => i.id == 'item-1').status, SeiItemPendenciaStatus.pendente);
    });

    test('mesmo lote_id e mesmos parâmetros, mas criado por OUTRO usuário: bloqueia (isolamento entre sessões)', () async {
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        loteId: 'lote-fixo',
        confirmarLimpezaDestino: false,
      );

      geradorDeLoteId = () => 'lote-fixo';
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'], // parâmetros IDÊNTICOS...
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      repo.falhaNaConclusao = null;
      // ...mas a sessão ATUAL, no momento da reconciliação, é de OUTRO
      // usuário (mesmo efeito de `auth.currentUser` mudar entre as duas
      // chamadas — ex.: logout/login como outra pessoa enquanto a
      // tentativa ficou pendente).
      repo.usuarioAtualParaTeste = 'outro-usuario';

      await notifier.reconciliar();

      final estado = container.read(testeControllerProvider);
      expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(estado.falha!.codigo, 'P0037');
      expect(estado.temTentativaPendente, isTrue);
    });

    test('falha de REDE durante a própria consulta de reconciliação: continua pendente, nunca "não encontrado"', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      repo.falhaNaConclusao = null;
      repo.falhaAoBuscarLote = Exception('falha de rede na consulta de reconciliação');

      await notifier.reconciliar();

      // NUNCA tratado como "registro não encontrado" (que também resulta em
      // resultadoDesconhecido, mas por um motivo diferente) — aqui a
      // CONSULTA em si falhou; o estado observável é o mesmo (pendente),
      // mas nenhuma escrita nova foi tentada e a decisão continua intacta.
      final estado = container.read(testeControllerProvider);
      expect(estado.status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(estado.temTentativaPendente, isTrue);
      expect(estado.decisao!.loteId, isNotEmpty);
    });
  });

  group('recusa recebida durante um retry() de tentativa antes desconhecida', () {
    // P0037 NÃO entra mais neste loop: diferente de
    // P0010/P0036 (só disparados quando o `loteId` já foi procurado e NADA
    // foi encontrado — uma recusa confiável), P0037 significa que a RPC
    // ENCONTROU um registro para este `loteId` com identidade divergente —
    // o desfecho correto é `conflitoDeIntegridade`, nunca `recusado` (ver o
    // grupo "P0037 no retry()" logo abaixo).
    for (final codigo in ['P0010', 'P0036']) {
      test('$codigo no retry() encerra a decisão como recusada — nunca descartada automaticamente sem reconciliação', () async {
        // 1ª tentativa: resultado desconhecido (timeout).
        repo.falhaNaConclusao = Exception('timeout simulado');
        final notifier = container.read(testeControllerProvider.notifier);
        await notifier.confirmar(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );
        expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);
        final loteIdOriginal = container.read(testeControllerProvider).decisao!.loteId;

        // 2ª tentativa (retry, MESMO payload): desta vez o SERVIDOR responde
        // de forma definitiva.
        repo.falhaNaConclusao = falhaDeConclusaoSei(
          codigo: codigo,
          mensagemDoServidor: 'recusa simulada $codigo no retry',
          operacao: operacaoConcluirItensSeiLote,
        );
        await notifier.retry();

        final estado = container.read(testeControllerProvider);
        expect(estado.status, SeiConclusaoLoteStatus.recusado);
        expect(estado.falha!.codigo, codigo);
        expect(estado.temTentativaPendente, isFalse);
        // O loteId do retry foi o MESMO da tentativa original — nunca outro.
        expect(estado.decisao!.loteId, loteIdOriginal);
        // A recusa só foi aceita DEPOIS de confirmar, por
        // leitura direta, que nada estava registrado sob este loteId.
        expect(repo.buscarLotePorIdCallCount, 1);

        // Só ENTÃO reiniciar()/uma decisão nova ficam disponíveis.
        notifier.reiniciar();
        expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.ocioso);
      });
    }
  });

  group('P0037 no retry() NUNCA é tratado como ausência do registro', () {
    test(
      'P0037 no retry() (RPC encontrou o loteId com identidade divergente) vira conflitoDeIntegridade, '
      'nunca recusado — mesmo que a leitura de verificação devolva null',
      () async {
        final notifier = container.read(testeControllerProvider.notifier);

        repo.falhaNaConclusao = Exception('timeout simulado');
        await notifier.confirmar(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );
        final loteIdOriginal = container.read(testeControllerProvider).decisao!.loteId;
        expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

        // Retry: a RPC responde P0037 — ela ENCONTROU um registro para este
        // loteId, mas com parâmetros diferentes. Nenhum lote foi semeado no
        // fake: a consulta de verificação (buscarLotePorId) devolverá
        // `null`, exatamente como a RLS ocultando um registro que existe.
        repo.falhaNaConclusao = falhaDeConclusaoSei(
          codigo: 'P0037',
          mensagemDoServidor: 'lote_id já usado para uma operação com parâmetros diferentes',
          operacao: operacaoConcluirItensSeiLote,
        );
        await notifier.retry();

        final estado = container.read(testeControllerProvider);
        expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
        expect(estado.falha!.codigo, 'P0037');
        expect(estado.temTentativaPendente, isTrue);
        // loteId e parâmetros preservados — nunca descartados.
        expect(estado.decisao!.loteId, loteIdOriginal);
        expect(repo.buscarLotePorIdCallCount, 1);

        // reiniciar()/retry()/reconciliar() automático continuam bloqueados
        // — mesma garantia de 11.5.6.2, nenhuma saída automática.
        notifier.reiniciar();
        expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);

        // Nenhuma nova chamada de conclusão foi disparada além do próprio
        // retry (que falhou): confirmar() para outro documento é ignorado.
        final chamadasAntes = repo.concluirLoteCallCount;
        repo.falhaNaConclusao = null;
        await notifier.confirmar(
          documentoId: 'doc-2',
          itemIds: const ['item-3'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );
        expect(repo.concluirLoteCallCount, chamadasAntes);
        expect(container.read(testeControllerProvider).decisao!.loteId, loteIdOriginal);
      },
    );

    test('P0037 no retry() com a verificação encontrando o registro divergente (leitura funciona) também vira conflitoDeIntegridade', () async {
      final notifier = container.read(testeControllerProvider.notifier);

      repo.falhaNaConclusao = Exception('timeout simulado');
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      final loteId = container.read(testeControllerProvider).decisao!.loteId;

      // O registro REALMENTE existe (outra operação reaproveitou o loteId
      // com um item diferente) — desta vez a leitura consegue enxergá-lo.
      repo.falhaNaConclusao = null;
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: loteId,
        confirmarLimpezaDestino: false,
      );

      repo.falhaNaConclusao = falhaDeConclusaoSei(
        codigo: 'P0037',
        mensagemDoServidor: 'lote_id já usado para uma operação com parâmetros diferentes',
        operacao: operacaoConcluirItensSeiLote,
      );
      await notifier.retry();

      final estado = container.read(testeControllerProvider);
      expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(estado.temTentativaPendente, isTrue);
    });

    test('P0037 no retry() com a PRÓPRIA verificação falhando (rede) ainda assim vira conflitoDeIntegridade', () async {
      final notifier = container.read(testeControllerProvider.notifier);

      repo.falhaNaConclusao = Exception('timeout simulado');
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      final loteId = container.read(testeControllerProvider).decisao!.loteId;

      repo.falhaNaConclusao = falhaDeConclusaoSei(
        codigo: 'P0037',
        mensagemDoServidor: 'lote_id já usado para uma operação com parâmetros diferentes',
        operacao: operacaoConcluirItensSeiLote,
      );
      repo.falhaAoBuscarLote = Exception('falha de rede na verificação');
      await notifier.retry();

      final estado = container.read(testeControllerProvider);
      // A certeza já veio do P0037 síncrono — não é rebaixada a
      // "resultado desconhecido" só porque a verificação não funcionou.
      expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(estado.decisao!.loteId, loteId);
    });
  });

  group('auditoria: retry() nunca aceita uma recusa sem confirmar por leitura direta', () {
    test(
      'retry() recebe 42501 (checagem de permissão, ANTES da checagem de loteId na RPC real) mas a tentativa '
      'ORIGINAL já havia sido aplicada — a recusa NUNCA é apresentada; o resultado real vira sucesso',
      () async {
        final notifier = container.read(testeControllerProvider.notifier);

        // 1ª tentativa: timeout do lado do cliente (resultado desconhecido).
        repo.falhaNaConclusao = Exception('timeout simulado');
        await notifier.confirmar(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );
        final estadoIncerto = container.read(testeControllerProvider);
        expect(estadoIncerto.status, SeiConclusaoLoteStatus.resultadoDesconhecido);
        final loteId = estadoIncerto.decisao!.loteId;

        // Simula que a tentativa original, na verdade, FOI aplicada no
        // servidor sob este MESMO loteId (o cliente só não recebeu a
        // resposta) — chamada direta ao repositório, nunca através do
        // controller (que continua achando que o resultado é desconhecido).
        repo.falhaNaConclusao = null;
        await repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          loteId: loteId,
          confirmarLimpezaDestino: false,
        );
        final chamadasAntesDoRetry = repo.concluirLoteCallCount;

        // 2ª tentativa (retry, MESMO payload): a RPC recusa por um motivo
        // cuja checagem, no servidor real, roda ANTES da busca por loteId
        // (ex.: 42501 — permissão mudou entre as duas chamadas) — isto NÃO
        // prova que a tentativa original não foi aplicada.
        repo.falhaNaConclusao = falhaDeConclusaoSei(
          codigo: '42501',
          mensagemDoServidor: 'recusa simulada 42501 no retry (permissão mudou entre as chamadas)',
          operacao: operacaoConcluirItensSeiLote,
        );
        await notifier.retry();

        final estado = container.read(testeControllerProvider);
        // A recusa foi CONFERIDA (não aceita cegamente): encontrou o
        // registro já aplicado e converteu para sucesso — nunca mostrado
        // como recusa ao usuário.
        expect(estado.status, SeiConclusaoLoteStatus.sucesso);
        expect(estado.resultado, isNotNull);
        expect(estado.falha, isNull);
        expect(estado.decisao!.loteId, loteId);
        expect(repo.buscarLotePorIdCallCount, 1);
        // Nenhuma escrita NOVA — só a chamada do retry (que falhou) e a
        // leitura de verificação; nada foi concluído de novo.
        expect(repo.concluirLoteCallCount, chamadasAntesDoRetry + 1);
      },
    );

    test('retry() recebe uma recusa e a verificação encontra um registro DIVERGENTE — vira conflito de integridade', () async {
      final notifier = container.read(testeControllerProvider.notifier);

      repo.falhaNaConclusao = Exception('timeout simulado');
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      final loteId = container.read(testeControllerProvider).decisao!.loteId;

      // Um registro EXISTE sob este loteId, mas pertence a uma operação
      // diferente (outro item) — nunca aceito como prova desta decisão.
      repo.falhaNaConclusao = null;
      await repo.concluirItensLote(
        documentoId: 'doc-1',
        itemIds: const ['item-2'],
        versaoEsperada: 1,
        loteId: loteId,
        confirmarLimpezaDestino: false,
      );

      repo.falhaNaConclusao = falhaDeConclusaoSei(
        codigo: '42501',
        mensagemDoServidor: 'recusa simulada no retry',
        operacao: operacaoConcluirItensSeiLote,
      );
      await notifier.retry();

      final estado = container.read(testeControllerProvider);
      expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
      expect(estado.temTentativaPendente, isTrue);
      expect(estado.emConflitoDeIntegridade, isTrue);
      // Nenhuma saída automática — nem reiniciar(), nem retry(), nem
      // reconciliar() têm efeito a partir daqui (mesma garantia de 11.5.6.2).
      notifier.reiniciar();
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
    });

    test(
      'retry() recebe uma recusa e a PRÓPRIA verificação falha (rede) — nunca assume recusado sozinha, '
      'volta a ficar pendente',
      () async {
        final notifier = container.read(testeControllerProvider.notifier);

        repo.falhaNaConclusao = Exception('timeout simulado');
        await notifier.confirmar(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );
        final loteId = container.read(testeControllerProvider).decisao!.loteId;

        repo.falhaNaConclusao = falhaDeConclusaoSei(
          codigo: '42501',
          mensagemDoServidor: 'recusa simulada no retry',
          operacao: operacaoConcluirItensSeiLote,
        );
        repo.falhaAoBuscarLote = Exception('falha de rede na verificação');
        await notifier.retry();

        final estado = container.read(testeControllerProvider);
        // NUNCA "recusado" sem confirmação — a decisão continua pendente,
        // exatamente como um resultado desconhecido comum.
        expect(estado.status, SeiConclusaoLoteStatus.resultadoDesconhecido);
        expect(estado.temTentativaPendente, isTrue);
        expect(estado.decisao!.loteId, loteId);
      },
    );
  });

  group(
    'retry() com 42501 e verificação retornando null (RLS pode ocultar um registro que existe)',
    () {
      test(
        'null NÃO prova ausência de execução: permanece resultadoDesconhecido, loteId/parâmetros preservados, '
        'reiniciar() continua bloqueado, nenhuma nova decisão é aceita',
        () async {
          final notifier = container.read(testeControllerProvider.notifier);

          // 1ª tentativa: timeout do lado do cliente.
          repo.falhaNaConclusao = Exception('timeout simulado');
          await notifier.confirmar(
            documentoId: 'doc-1',
            itemIds: const ['item-1'],
            versaoEsperada: 1,
            observacao: 'obs original',
            confirmarLimpezaDestino: false,
          );
          final decisaoOriginal = container.read(testeControllerProvider).decisao!;
          expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

          // Retry: a RPC recusa com 42501 (checagem de permissão, ANTES do
          // lookup do loteId) — e a verificação (buscarLotePorId) devolve
          // `null`, exatamente como aconteceria se a RLS da sessão ATUAL
          // estivesse ocultando um registro que na verdade existe (nenhum
          // `_lotes[...]` semeado no fake — o mesmo `null` que uma RLS
          // restritiva produziria).
          repo.falhaNaConclusao = falhaDeConclusaoSei(
            codigo: '42501',
            mensagemDoServidor: 'recusa simulada 42501 no retry (permissão mudou entre as chamadas)',
            operacao: operacaoConcluirItensSeiLote,
          );
          await notifier.retry();

          final estado = container.read(testeControllerProvider);
          // NUNCA apresentado como recusa definitiva — permanece pendente.
          expect(estado.status, SeiConclusaoLoteStatus.resultadoDesconhecido);
          expect(estado.temTentativaPendente, isTrue);
          expect(estado.falha, isNull);
          // loteId e os seis parâmetros continuam EXATAMENTE os mesmos.
          expect(estado.decisao!.loteId, decisaoOriginal.loteId);
          expect(estado.decisao!.documentoId, decisaoOriginal.documentoId);
          expect(estado.decisao!.itemIds, decisaoOriginal.itemIds);
          expect(estado.decisao!.versaoEsperada, decisaoOriginal.versaoEsperada);
          expect(estado.decisao!.observacao, decisaoOriginal.observacao);
          expect(estado.decisao!.confirmarLimpezaDestino, decisaoOriginal.confirmarLimpezaDestino);

          // reiniciar() continua SEM efeito — nenhum descarte automático.
          notifier.reiniciar();
          expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

          // Nenhuma nova decisão é aceita (nem para o MESMO documento, nem
          // para outro) e nenhum `loteId` novo é gerado — nenhuma chamada
          // indevida à RPC.
          repo.falhaNaConclusao = null;
          final chamadasAntes = repo.concluirLoteCallCount;
          await notifier.confirmar(
            documentoId: 'doc-2',
            itemIds: const ['item-3'],
            versaoEsperada: 1,
            confirmarLimpezaDestino: false,
          );
          final estadoFinal = container.read(testeControllerProvider);
          expect(estadoFinal.decisao!.documentoId, 'doc-1', reason: 'a decisão pendente do doc-1 nunca foi trocada');
          expect(estadoFinal.decisao!.loteId, decisaoOriginal.loteId);
          expect(repo.concluirLoteCallCount, chamadasAntes, reason: 'nenhuma chamada indevida à RPC');
        },
      );

      test(
        'depois de ambíguo (null), um registro compatível encontrado posteriormente (reconciliar) resolve como sucesso',
        () async {
          final notifier = container.read(testeControllerProvider.notifier);

          repo.falhaNaConclusao = Exception('timeout simulado');
          await notifier.confirmar(
            documentoId: 'doc-1',
            itemIds: const ['item-1'],
            versaoEsperada: 1,
            confirmarLimpezaDestino: false,
          );
          final loteId = container.read(testeControllerProvider).decisao!.loteId;

          repo.falhaNaConclusao = falhaDeConclusaoSei(
            codigo: '42501',
            mensagemDoServidor: 'recusa simulada no retry',
            operacao: operacaoConcluirItensSeiLote,
          );
          await notifier.retry();
          expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

          // O registro "aparece" (ex.: a RLS deixou de ocultá-lo, ou uma
          // consulta de diagnóstico direta confirma que a operação FOI
          // aplicada) — semeado diretamente no repositório, sob o MESMO
          // loteId e os MESMOS parâmetros da decisão congelada.
          repo.falhaNaConclusao = null;
          await repo.concluirItensLote(
            documentoId: 'doc-1',
            itemIds: const ['item-1'],
            versaoEsperada: 1,
            loteId: loteId,
            confirmarLimpezaDestino: false,
          );

          await notifier.reconciliar();
          final estado = container.read(testeControllerProvider);
          expect(estado.status, SeiConclusaoLoteStatus.sucesso);
          expect(estado.resultado, isNotNull);
        },
      );

      test(
        'depois de ambíguo (null), um registro DIVERGENTE encontrado posteriormente (reconciliar) resolve como '
        'conflito de integridade',
        () async {
          final notifier = container.read(testeControllerProvider.notifier);

          repo.falhaNaConclusao = Exception('timeout simulado');
          await notifier.confirmar(
            documentoId: 'doc-1',
            itemIds: const ['item-1'],
            versaoEsperada: 1,
            confirmarLimpezaDestino: false,
          );
          final loteId = container.read(testeControllerProvider).decisao!.loteId;

          repo.falhaNaConclusao = falhaDeConclusaoSei(
            codigo: '42501',
            mensagemDoServidor: 'recusa simulada no retry',
            operacao: operacaoConcluirItensSeiLote,
          );
          await notifier.retry();
          expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

          // O registro que "aparece" pertence a OUTRA operação (outro item)
          // sob o mesmo loteId — nunca aceito como prova desta decisão.
          repo.falhaNaConclusao = null;
          await repo.concluirItensLote(
            documentoId: 'doc-1',
            itemIds: const ['item-2'],
            versaoEsperada: 1,
            loteId: loteId,
            confirmarLimpezaDestino: false,
          );

          await notifier.reconciliar();
          final estado = container.read(testeControllerProvider);
          expect(estado.status, SeiConclusaoLoteStatus.conflitoDeIntegridade);
          expect(estado.temTentativaPendente, isTrue);
        },
      );
    },
  );

  group('isolamento entre documentos', () {
    test('tentativa pendente do Documento A bloqueia confirmar() para o Documento B (nunca troca de decisão)', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.resultadoDesconhecido);

      repo.falhaNaConclusao = null;
      await notifier.confirmar(
        documentoId: 'doc-2',
        itemIds: const ['item-3'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );

      // Nada mudou: a decisão continua sendo a do Documento A, ainda
      // pendente — o Documento B nunca "assumiu" o controller.
      final estado = container.read(testeControllerProvider);
      expect(estado.status, SeiConclusaoLoteStatus.resultadoDesconhecido);
      expect(estado.decisao!.documentoId, 'doc-1');
      expect(repo.concluirLoteCallCount, 1);
    });
  });

  group('isolamento entre sessões autenticadas', () {
    test('logout descarta uma decisão pendente do estado local (nunca reaproveitada pela próxima sessão)', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(container.read(testeControllerProvider).temTentativaPendente, isTrue);

      await authRepo.signOut();
      // Deixa a invalidação de `authControllerProvider` se resolver.
      await container.read(authControllerProvider.future);

      final estado = container.read(testeControllerProvider);
      expect(estado.status, SeiConclusaoLoteStatus.ocioso);
      expect(estado.decisao, isNull);
      // O registro no SERVIDOR não foi apagado — só o estado local: uma
      // consulta futura (por quem tiver acesso) continuaria encontrando o
      // que já foi escrito, se algo tiver sido escrito.
    });

    test('login como outro usuário também descarta o estado local anterior', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      expect(container.read(testeControllerProvider).temTentativaPendente, isTrue);

      await authRepo.signIn(email: 'outra@example.com', password: 'x'); // FakeAuthRepository troca o id ao logar
      await container.read(authControllerProvider.future);

      expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.ocioso);
      expect(container.read(testeControllerProvider).decisao, isNull);
    });

    test('uma transição de auth para o MESMO usuário (ex.: refresh trivial) NÃO descarta a tentativa pendente', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      final loteIdOriginal = container.read(testeControllerProvider).decisao!.loteId;

      // Reenvia o MESMO usuário no stream de auth (sem trocar de sessão) —
      // não deve zerar o estado pendente.
      authRepo.reemitirEstadoAtualParaTeste();
      await container.read(authControllerProvider.future);

      final estado = container.read(testeControllerProvider);
      expect(estado.temTentativaPendente, isTrue);
      expect(estado.decisao!.loteId, loteIdOriginal);
    });

    test(
      'troca efetiva de usuário também descarta um conflito de integridade (mesmo isolamento)',
      () async {
        // Chega a um conflito de integridade (não só resultadoDesconhecido).
        await repo.concluirItensLote(
          documentoId: 'doc-1',
          itemIds: const ['item-2'],
          versaoEsperada: 1,
          loteId: 'lote-fixo',
          confirmarLimpezaDestino: false,
        );
        geradorDeLoteId = () => 'lote-fixo';
        repo.falhaNaConclusao = Exception('timeout simulado');
        final notifier = container.read(testeControllerProvider.notifier);
        await notifier.confirmar(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );
        repo.falhaNaConclusao = null;
        await notifier.reconciliar();
        expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.conflitoDeIntegridade);

        // Troca EFETIVA de usuário — segue o mesmo isolamento: mesmo um
        // conflito de integridade não sobrevive a uma sessão diferente
        // (nada é reaproveitado por outra sessão).
        await authRepo.signIn(email: 'outra@example.com', password: 'x');
        await container.read(authControllerProvider.future);

        final estado = container.read(testeControllerProvider);
        expect(estado.status, SeiConclusaoLoteStatus.ocioso);
        expect(estado.decisao, isNull);
        expect(estado.emConflitoDeIntegridade, isFalse);
      },
    );
  });

  group('preservação da conclusão individual', () {
    test('concluirItem continua funcionando, sem interferência do controller de lote', () async {
      repo.falhaNaConclusao = Exception('timeout simulado');
      final notifier = container.read(testeControllerProvider.notifier);
      await notifier.confirmar(
        documentoId: 'doc-1',
        itemIds: const ['item-1'],
        versaoEsperada: 1,
        confirmarLimpezaDestino: false,
      );
      // Uma tentativa de lote pendente NÃO impede a conclusão INDIVIDUAL de
      // um item diferente — são fluxos independentes.
      repo.falhaNaConclusao = null;
      final resultado = await repo.concluirItem(documentoId: 'doc-1', itemId: 'item-2', versaoEsperada: 1);

      expect(resultado.jaConcluido, isFalse);
      expect(resultado.item.status, SeiItemPendenciaStatus.concluido);
      expect(repo.concluirCallCount, 1);
    });
  });

  group('recusa definitiva do servidor — P0010, P0036, P0037', () {
    for (final codigo in ['P0010', 'P0036', 'P0037']) {
      test('$codigo encerra a decisão como recusada (nunca "resultado desconhecido"), permite reiniciar()', () async {
        repo.falhaNaConclusao = falhaDeConclusaoSei(
          codigo: codigo,
          mensagemDoServidor: 'recusa simulada $codigo',
          operacao: operacaoConcluirItensSeiLote,
        );
        final notifier = container.read(testeControllerProvider.notifier);

        await notifier.confirmar(
          documentoId: 'doc-1',
          itemIds: const ['item-1'],
          versaoEsperada: 1,
          confirmarLimpezaDestino: false,
        );

        final estado = container.read(testeControllerProvider);
        expect(estado.status, SeiConclusaoLoteStatus.recusado);
        expect(estado.temTentativaPendente, isFalse);
        expect(estado.falha!.codigo, codigo);

        // Uma recusa DEFINITIVA (a transação foi desfeita) permite reiniciar
        // e começar uma decisão nova — diferente de resultado desconhecido.
        notifier.reiniciar();
        expect(container.read(testeControllerProvider).status, SeiConclusaoLoteStatus.ocioso);
        expect(container.read(testeControllerProvider).decisao, isNull);
      });
    }
  });
}

SeiDocumentoPendente _documento({required String id, required int versao, required List<SeiItemPendente> itens}) {
  return SeiDocumentoPendente.fromItens(
    id: id,
    numeroDocumentoSei: 'SEI-$id',
    tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
    nomeArquivo: 'despacho.pdf',
    hashSha256: 'hash-$id',
    versao: versao,
    criadoEm: DateTime.utc(2026, 1, 1),
    criadoPorId: 'user-1',
    criadoPorNome: 'Usuária de Teste',
    itens: itens,
  );
}

Profile _perfil(String id) => Profile(
  id: id,
  nome: 'Usuária de Teste',
  email: '$id@example.com',
  perfil: ProfilePerfil.operador,
  ativo: true,
  criadoEm: DateTime.utc(2026, 1, 1),
  atualizadoEm: DateTime.utc(2026, 1, 1),
);

SeiItemPendente _item({required String id, required String patrimonioId, String documentoId = 'doc-1'}) {
  return SeiItemPendente(
    id: id,
    documentoId: documentoId,
    linha: 1,
    patrimonioId: patrimonioId,
    numeroPatrimonio: SeiValorCorrigivel(original: 'PAT-$id'),
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
