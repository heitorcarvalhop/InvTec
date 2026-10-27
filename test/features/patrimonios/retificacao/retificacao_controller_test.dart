import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_comparacao.dart';
import 'package:invtec/features/patrimonios/retificacao/domain/retificacao_execucao.dart';
import 'package:invtec/features/patrimonios/retificacao/presentation/retificacao_controller.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../auth/fake_permissions_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';

/// Testes do fluxo completo de `RetificacaoController` (carregar CSV →
/// resolver por UUID → revisão → confirmar → executar). Tudo com dados
/// FICTÍCIOS em memória — nenhuma chamada de rede/Supabase real. Os
/// testes de autorização/atomicidade/idempotência da RPC real não são
/// executáveis neste ambiente sem um Postgres real (ver auditoria da
/// migration `20261022140000_add_retificacao_cadastral_unidade.sql`).
Profile _perfil(ProfilePerfil perfil, {String id = 'user-1'}) => Profile(
  id: id,
  nome: 'Usuária de Teste',
  email: 'teste@invtec.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
  accessStatus: ProfileAccessStatus.active,
  rejectionCount: 0,
);

final _getec = Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1));
final _cimehgo = Setor(
  id: 'setor-cimehgo',
  nome: 'CIMEHGO',
  sigla: 'CIMEHGO',
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
);

PatrimonioDetalhe _patrimonio({required String id, required String numero, DateTime? atualizadoEm}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.emUso,
      setorAtualId: _getec.id,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: atualizadoEm ?? DateTime(2026, 1, 1),
    ),
    tipoNome: 'Monitor',
    setorNome: 'GETEC',
  );
}

const _cabecalho =
    'ID patrimônio no InvTec;Tombamento oficial (texto);Tombamento atual no InvTec;Descrição oficial;'
    'Setor atual (InvTec);Unidade correta (sigla);Unidade correta (nome);Localização atual no InvTec;'
    'Localização na planilha;Localização planejada;Série InvTec;Série oficial;'
    'Tombamento anterior planilha;Status tombamento anterior;Status cruzamento;Status da revisão;'
    'Observação / justificativa';

/// Monta um CSV válido com uma linha por `(patrimonioId, tombamento)` —
/// sempre "Setor atual" = GETEC e destino = CIMEHGO, suficiente para os
/// cenários desta suíte.
List<int> _csv(List<(String id, String tombamento)> linhas) {
  final corpo = linhas
      .map((l) => '${l.$1};${l.$2};${l.$2};Descrição;GETEC;CIMEHGO;CIMEHGO;;;;;;;;;;')
      .join('\n');
  return utf8.encode('$_cabecalho\n$corpo\n');
}

Future<({ProviderContainer container, FakeAuthRepository auth})> _criarContainer({
  required FakePatrimonioRepository repositorio,
  required ProfilePerfil perfil,
  FakeSetorRepository? setorRepositorio,
  String Function()? gerarLoteId,
  String Function()? gerarOperacaoId,
  // Trava desabilitada por padrão (igual à real, e igual ao padrão da
  // suíte irmã `comparacao_execucao_test.dart`) — testes desta suíte que
  // não são sobre a trava em si a habilitam explicitamente.
  bool retificacaoExecucaoHabilitada = true,
  Set<String>? permissoesExtras,
}) async {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (id) => _perfil(perfil, id: id));
  final permissoes = permissoesExtras == null
      ? FakePermissionsRepository.paraPerfil(perfil)
      : FakePermissionsRepository(chaves: permissoesExtras);
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      authRepositoryProvider.overrideWithValue(auth),
      permissionsRepositoryProvider.overrideWithValue(permissoes),
      setorRepositoryProvider.overrideWithValue(setorRepositorio ?? FakeSetorRepository(setores: [_getec, _cimehgo])),
      retificacaoControllerProvider.overrideWith(
        () => RetificacaoController(
          gerarLoteId: gerarLoteId,
          gerarOperacaoId: gerarOperacaoId,
          retificacaoExecucaoHabilitada: () => retificacaoExecucaoHabilitada,
        ),
      ),
    ],
  );
  container.listen(retificacaoControllerProvider, (_, _) {});
  addTearDown(() {
    container.dispose();
    auth.dispose();
  });
  // Espera a resolução INICIAL de authControllerProvider antes de devolver
  // o container — sem isso, `RetificacaoController.build()` pode capturar
  // `_usuarioConhecido = null` (ainda carregando) e o `ref.listen` interno
  // trataria a resolução posterior como "troca de usuário", resetando o
  // estado no meio de um teste (mesmo cuidado de
  // `comparacao_execucao_test.dart`).
  await container.read(authControllerProvider.future);
  return (container: container, auth: auth);
}

void main() {
  group('carregarCsv', () {
    test('resolve por UUID e classifica pronto/já correto/bloqueado', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '1'), _patrimonio(id: 'p2', numero: '2')],
      );
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1'), ('p2', '2'), ('nao-existe', '3')]));

      final estado = ctx.container.read(retificacaoControllerProvider);
      expect(estado.fase, RetificacaoFase.revisao);
      expect(estado.lote!.resumo.totalLinhas, 3);
      expect(estado.lote!.resumo.prontos, 2);
      expect(estado.lote!.resumo.bloqueadosPorMotivo[ClassificacaoRetificacao.patrimonioNaoEncontrado], 1);
    });

    test('CSV com cabeçalho inválido: erro de carregamento, nunca trava em "carregando"', () async {
      final repo = FakePatrimonioRepository();
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(utf8.encode('coluna errada;outra\nvalor;valor\n'));

      final estado = ctx.container.read(retificacaoControllerProvider);
      expect(estado.fase, RetificacaoFase.semArquivo);
      expect(estado.erroCarregamento, isNotNull);
    });
  });

  group('confirmarExecucao — autorização e trava operacional', () {
    Future<RetificacaoState> carregarEConfirmar(
      ProviderContainer container, {
      String justificativa = 'Plano SEMAD',
    }) async {
      final controller = container.read(retificacaoControllerProvider.notifier);
      await controller.carregarCsv(_csv([('p1', '1')]));
      controller.definirJustificativa(justificativa);
      await controller.confirmarExecucao();
      return container.read(retificacaoControllerProvider);
    }

    test('OPERADOR (sem perfil ADMIN/GESTOR): confirmarExecucao não executa nada', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.operador);

      final estado = await carregarEConfirmar(ctx.container);

      expect(estado.fase, RetificacaoFase.revisao); // nunca avançou para executando
      expect(repo.retificarUnidadePatrimonioCallCount, 0);
    });

    test('ADMIN sem a permissão patrimonio.rectify_unit: confirmarExecucao não executa nada', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(
        repositorio: repo,
        perfil: ProfilePerfil.admin,
        permissoesExtras: {'patrimonio.view'}, // sem patrimonio.rectify_unit
      );

      final estado = await carregarEConfirmar(ctx.container);

      expect(estado.fase, RetificacaoFase.revisao);
      expect(repo.retificarUnidadePatrimonioCallCount, 0);
    });

    test('GESTOR com a permissão: confirmarExecucao EXECUTA (ADMIN não é exclusivo aqui)', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.gestor);

      final estado = await carregarEConfirmar(ctx.container);

      expect(estado.fase, RetificacaoFase.concluida);
      expect(estado.sucessos, 1);
      expect(repo.retificarUnidadePatrimonioCallCount, 1);
    });

    test('justificativa vazia: confirmarExecucao não executa nada', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);

      final estado = await carregarEConfirmar(ctx.container, justificativa: '   ');

      expect(estado.fase, RetificacaoFase.revisao);
      expect(repo.retificarUnidadePatrimonioCallCount, 0);
    });

    test(
      'trava operacional desabilitada: ADMIN com permissão ainda não executa nada '
      '(independente de perfil/permissão/migration já existir)',
      () async {
        final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
        final ctx = await _criarContainer(
          repositorio: repo,
          perfil: ProfilePerfil.admin,
          retificacaoExecucaoHabilitada: false,
        );

        final estado = await carregarEConfirmar(ctx.container);

        expect(estado.fase, RetificacaoFase.revisao);
        expect(repo.retificarUnidadePatrimonioCallCount, 0);
      },
    );

    test('ADMIN com tudo em ordem: executa e conclui com sucesso', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);

      final estado = await carregarEConfirmar(ctx.container);

      expect(estado.fase, RetificacaoFase.concluida);
      expect(estado.sucessos, 1);
      expect(estado.falhas, 0);
      expect(repo.retificacoesAplicadas, hasLength(1));
    });

    test('apenas itens PRONTOS entram na execução — já corretos/bloqueados nunca são enviados', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '1')], // p2 não existe -> bloqueado
      );
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1'), ('nao-existe', '2')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao();

      final estado = ctx.container.read(retificacaoControllerProvider);
      expect(estado.totalExecucao, 1); // só o item pronto
      expect(estado.sucessos, 1);
    });
  });

  group('retryItem', () {
    test('reenvia um item de resultado desconhecido e não afeta os demais', () async {
      final repo = _RepositorioComFalhaDeRedeUmaVez(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao();

      var estado = ctx.container.read(retificacaoControllerProvider);
      expect(estado.desconhecidos, 1);
      expect(estado.fase, RetificacaoFase.concluida);

      await controller.retryItem('p1');

      estado = ctx.container.read(retificacaoControllerProvider);
      expect(estado.sucessos, 1);
      expect(estado.desconhecidos, 0);
      expect(estado.fase, RetificacaoFase.concluida);
    });

    test('nunca reenvia um item que não está em resultadoDesconhecido', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao();
      expect(ctx.container.read(retificacaoControllerProvider).sucessos, 1);

      await controller.retryItem('p1'); // já é sucesso — sem efeito

      expect(repo.retificarUnidadePatrimonioCallCount, 1); // nenhuma segunda chamada
    });
  });

  group('execução sequencial e interrupção segura', () {
    test('nunca executa dois itens ao mesmo tempo (um por vez, nunca em lote)', () async {
      final repo = _RepositorioComContagemDeConcorrencia(
        itens: [_patrimonio(id: 'p1', numero: '1'), _patrimonio(id: 'p2', numero: '2'), _patrimonio(id: 'p3', numero: '3')],
      );
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1'), ('p2', '2'), ('p3', '3')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao();

      expect(repo.maximoEmVoo, 1); // nunca 2 ou 3 simultâneas
      expect(ctx.container.read(retificacaoControllerProvider).sucessos, 3);
    });

    test(
      'solicitarInterrupcao para ANTES do próximo item, sem cancelar a chamada em voo',
      () async {
        final repo = _RepositorioComPausaControlada(
          itens: [_patrimonio(id: 'p1', numero: '1'), _patrimonio(id: 'p2', numero: '2')],
        );
        final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
        final controller = ctx.container.read(retificacaoControllerProvider.notifier);

        await controller.carregarCsv(_csv([('p1', '1'), ('p2', '2')]));
        controller.definirJustificativa('j');

        final execucao = controller.confirmarExecucao();
        // Deixa a chamada de p1 começar (ainda presa no completer) antes de
        // pedir a interrupção — prova que ela não é abortada no meio. Espera
        // em microtasks sucessivas (nunca um delay fixo arbitrário) até o
        // status mudar para "executando".
        for (var i = 0; i < 50; i++) {
          if (ctx.container.read(retificacaoControllerProvider).itensExecucao['p1']?.status ==
              ItemExecucaoRetificacaoStatus.executando) {
            break;
          }
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          ctx.container.read(retificacaoControllerProvider).itensExecucao['p1']!.status,
          ItemExecucaoRetificacaoStatus.executando,
        );

        controller.solicitarInterrupcao();
        repo.liberarPrimeiraChamada();
        await execucao;

        final estado = ctx.container.read(retificacaoControllerProvider);
        expect(estado.fase, RetificacaoFase.concluida);
        expect(estado.interrompidaPeloUsuario, isTrue);
        expect(estado.sucessos, 1); // p1 terminou normalmente
        expect(
          estado.itensExecucao['p2']!.status,
          ItemExecucaoRetificacaoStatus.pendente,
        ); // p2 nunca começou
        expect(repo.retificarUnidadePatrimonioCallCount, 1);
      },
    );

    test('solicitarInterrupcao sem execução em andamento: sem efeito', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao(); // já concluída

      controller.solicitarInterrupcao(); // sem execução em andamento

      final estado = ctx.container.read(retificacaoControllerProvider);
      expect(estado.fase, RetificacaoFase.concluida);
      expect(estado.sucessos, 1);
    });
  });

  group('reiniciar', () {
    test('limpa o estado quando não há pendência', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao();

      controller.reiniciar();

      expect(ctx.container.read(retificacaoControllerProvider).fase, RetificacaoFase.semArquivo);
    });

    test('nunca limpa o estado enquanto houver pendência (resultadoDesconhecido)', () async {
      final repo = _RepositorioComFalhaDeRedeUmaVez(itens: [_patrimonio(id: 'p1', numero: '1')]);
      final ctx = await _criarContainer(repositorio: repo, perfil: ProfilePerfil.admin);
      final controller = ctx.container.read(retificacaoControllerProvider.notifier);

      await controller.carregarCsv(_csv([('p1', '1')]));
      controller.definirJustificativa('j');
      await controller.confirmarExecucao();
      expect(ctx.container.read(retificacaoControllerProvider).desconhecidos, 1);

      controller.reiniciar();

      expect(ctx.container.read(retificacaoControllerProvider).fase, RetificacaoFase.concluida);
    });
  });
}

/// Lança uma falha de rede (nunca uma recusa do servidor) na PRIMEIRA
/// chamada a [retificarUnidadePatrimonio] de cada patrimônio — simula
/// "resultado desconhecido", nunca "falhou". Chamadas seguintes (retry)
/// delegam normalmente.
class _RepositorioComFalhaDeRedeUmaVez extends FakePatrimonioRepository {
  _RepositorioComFalhaDeRedeUmaVez({super.itens});
  final Set<String> _jaFalhou = {};

  @override
  Future<ResultadoRetificacaoUnidade> retificarUnidadePatrimonio(ItemRetificacaoParaExecutar item) async {
    if (_jaFalhou.add(item.patrimonioId)) {
      throw Exception('Falha de rede simulada');
    }
    return super.retificarUnidadePatrimonio(item);
  }
}

/// Rastreia o número de chamadas a [retificarUnidadePatrimonio]
/// SIMULTANEAMENTE em voo — prova que `RetificacaoController._processar` é
/// sequencial (nunca dispara a próxima antes da anterior terminar), mesmo
/// com um atraso artificial que exporia qualquer concorrência real.
class _RepositorioComContagemDeConcorrencia extends FakePatrimonioRepository {
  _RepositorioComContagemDeConcorrencia({super.itens});
  int _emVoo = 0;
  int maximoEmVoo = 0;

  @override
  Future<ResultadoRetificacaoUnidade> retificarUnidadePatrimonio(ItemRetificacaoParaExecutar item) async {
    _emVoo++;
    if (_emVoo > maximoEmVoo) maximoEmVoo = _emVoo;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    try {
      return await super.retificarUnidadePatrimonio(item);
    } finally {
      _emVoo--;
    }
  }
}

/// A PRIMEIRA chamada a [retificarUnidadePatrimonio] só termina quando o
/// teste chama [liberarPrimeiraChamada] — permite pedir
/// `solicitarInterrupcao()` enquanto essa chamada ainda está em voo, e
/// provar que ela termina normalmente (nunca é cancelada) antes do próximo
/// item (que nunca deveria começar).
class _RepositorioComPausaControlada extends FakePatrimonioRepository {
  _RepositorioComPausaControlada({super.itens});
  final Completer<void> _primeiraChamada = Completer<void>();
  var _jaChamou = false;

  void liberarPrimeiraChamada() => _primeiraChamada.complete();

  @override
  Future<ResultadoRetificacaoUnidade> retificarUnidadePatrimonio(ItemRetificacaoParaExecutar item) async {
    if (!_jaChamou) {
      _jaChamou = true;
      await _primeiraChamada.future;
    }
    return super.retificarUnidadePatrimonio(item);
  }
}
