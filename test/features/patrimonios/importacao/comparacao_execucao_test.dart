import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/core/errors/app_exception.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/auth/presentation/auth_controller.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/comparacao_execucao.dart';
import 'package:invtec/features/patrimonios/importacao/domain/patrimonio_comparacao.dart';
import 'package:invtec/features/patrimonios/importacao/domain/patrimonio_decisao.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/comparacao_execucao_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// PROMPT 11.6.4 — testes da execução segura das decisões de comparação
/// (`ComparacaoExecucaoController`/`aplicarDecisaoComparacao`), cobrindo os
/// 16 cenários exigidos pela seção 9. Tudo com dados FICTÍCIOS/fakes em
/// memória — nenhuma chamada de rede/Supabase real (restrição da seção 10).
/// Os testes SQL de autorização/atomicidade/idempotência da RPC (seção 9,
/// último parágrafo) não são executáveis neste ambiente sem um Postgres
/// real — ver a limitação anotada no relatório final do prompt.
Profile _perfil(ProfilePerfil perfil, {String id = 'user-1'}) => Profile(
  id: id,
  nome: 'Usuária de Teste',
  email: 'teste@invtec.com',
  perfil: perfil,
  ativo: true,
  criadoEm: DateTime(2026, 1, 1),
  atualizadoEm: DateTime(2026, 1, 1),
);

PatrimonioDetalhe _patrimonio({
  required String id,
  required String numero,
  String setorId = 'setor-getec',
  String? localizacaoId,
  String? descricao = 'Notebook Antigo',
  String? marca = 'DELL',
  DateTime? atualizadoEm,
}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-notebook',
      descricao: descricao,
      marca: marca,
      status: PatrimonioStatus.disponivel,
      setorAtualId: setorId,
      localizacaoAtualId: localizacaoId,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: atualizadoEm ?? DateTime(2026, 1, 1),
    ),
    tipoNome: 'Notebook',
    setorNome: 'GETEC',
  );
}

PatrimonioComparacao _itemDivergente({
  required String patrimonioId,
  required String numero,
  required List<CampoDivergente> divergencias,
  DateTime? versao,
}) => PatrimonioComparacao(
  numeroLinha: 2,
  numeroPatrimonio: numero,
  patrimonioId: patrimonioId,
  classificacao: ClassificacaoComparacao.divergente,
  divergencias: divergencias,
  versaoAtualizadoEm: versao ?? DateTime(2026, 1, 1),
);

ComparacaoLote _lote(List<PatrimonioComparacao> itens) => ComparacaoLote(
  itens: itens,
  resumo: ComparacaoResumo(
    totalLinhas: itens.length,
    identicos: itens.where((i) => i.classificacao == ClassificacaoComparacao.identico).length,
    divergentes: itens.where((i) => i.classificacao == ClassificacaoComparacao.divergente).length,
    novos: itens.where((i) => i.classificacao == ClassificacaoComparacao.novo).length,
    bloqueados: itens.where((i) => i.classificacao == ClassificacaoComparacao.bloqueado).length,
    divergenciasPorCampo: const {},
  ),
);

Map<ChaveDecisaoCampo, DecisaoCampoValor> _decisoes(List<(String, String, DecisaoCampoValor)> entradas) => {
  for (final (patrimonioId, campo, valor) in entradas)
    ChaveDecisaoCampo(patrimonioId: patrimonioId, campo: campo): valor,
};

String Function() _geradorSequencial(String prefixo) {
  var contador = 0;
  return () => '$prefixo-${contador++}';
}

({ProviderContainer container, FakeAuthRepository auth}) _criarContainerExecucao({
  required FakePatrimonioRepository repositorio,
  required ProfilePerfil perfil,
  String Function()? gerarLoteId,
  String Function()? gerarOperacaoId,
  // PROMPT 11.6.5, seção 9 — a trava operacional é DESABILITADA por padrão
  // (`EnvConfig.comparacaoExecucaoHabilitada`, que lê dotenv/dart-define —
  // nenhum dos dois está configurado em teste). A suíte deste arquivo testa
  // o COMPORTAMENTO da execução (não a trava em si, coberta à parte), então
  // o padrão AQUI já nasce habilitado — um teste dedicado ("configuração
  // desabilitada bloqueia a execução") usa `false` explicitamente.
  bool comparacaoExecucaoHabilitada = true,
}) {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (id) => _perfil(perfil, id: id));
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      authRepositoryProvider.overrideWithValue(auth),
      comparacaoExecucaoControllerProvider.overrideWith(
        () => ComparacaoExecucaoController(
          gerarLoteId: gerarLoteId,
          gerarOperacaoId: gerarOperacaoId,
          comparacaoExecucaoHabilitada: () => comparacaoExecucaoHabilitada,
        ),
      ),
    ],
  );
  container.listen(comparacaoExecucaoControllerProvider, (_, _) {});
  addTearDown(() {
    container.dispose();
    auth.dispose();
  });
  return (container: container, auth: auth);
}

void main() {
  group('construirItensParaExecucao (puro)', () {
    test('6. um item IDÊNTICO nunca entra na lista, mesmo com uma decisão residual para ele', () {
      final lote = _lote([
        const PatrimonioComparacao(
          numeroLinha: 1,
          numeroPatrimonio: '100000',
          patrimonioId: 'p-identico',
          classificacao: ClassificacaoComparacao.identico,
        ),
      ]);
      final itens = construirItensParaExecucao(
        comparacao: lote,
        decisoes: _decisoes([('p-identico', 'Descrição', DecisaoCampoValor.aplicar)]),
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, isEmpty);
    });

    test('7. um item NOVO nunca entra na lista (não é cadastrado automaticamente)', () {
      final lote = _lote([
        const PatrimonioComparacao(
          numeroLinha: 1,
          numeroPatrimonio: '999999',
          classificacao: ClassificacaoComparacao.novo,
        ),
      ]);
      final itens = construirItensParaExecucao(
        comparacao: lote,
        decisoes: const {},
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, isEmpty);
    });

    test('um item BLOQUEADO nunca entra na lista', () {
      final lote = _lote([
        const PatrimonioComparacao(
          numeroLinha: 1,
          numeroPatrimonio: '555555',
          classificacao: ClassificacaoComparacao.bloqueado,
          motivoBloqueio: 'motivo qualquer',
        ),
      ]);
      final itens = construirItensParaExecucao(
        comparacao: lote,
        decisoes: const {},
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, isEmpty);
    });

    test('5. campo com decisão pendente/ignorar nunca entra nos parâmetros — só o decidido aplicar', () {
      final item = _itemDivergente(
        patrimonioId: 'p1',
        numero: '123456',
        divergencias: const [
          CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
          CampoDivergente(campo: 'Marca', tipo: TipoDivergencia.metadado, valorInvtec: 'DELL', valorPlanilha: 'LENOVO'),
        ],
      );
      final itens = construirItensParaExecucao(
        comparacao: _lote([item]),
        decisoes: _decisoes([
          ('p1', 'Descrição', DecisaoCampoValor.aplicar),
          ('p1', 'Marca', DecisaoCampoValor.ignorar),
        ]),
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, hasLength(1));
      expect(itens.single.descricao, 'B');
      expect(itens.single.marca, isNull);
    });

    test('um patrimônio 100% ignorado/pendente nunca gera item (nenhuma decisão "aplicar")', () {
      final item = _itemDivergente(
        patrimonioId: 'p1',
        numero: '123456',
        divergencias: const [
          CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
        ],
      );
      final itens = construirItensParaExecucao(
        comparacao: _lote([item]),
        decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.ignorar)]),
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, isEmpty);
    });

    test('setor/localização com valorPlanilhaId nulo (defensivo) nunca é aplicado mesmo decidido "aplicar"', () {
      final item = _itemDivergente(
        patrimonioId: 'p1',
        numero: '123456',
        divergencias: const [
          CampoDivergente(
            campo: 'Localização atual',
            tipo: TipoDivergencia.localizacao,
            valorInvtec: 'A',
            valorPlanilha: 'B',
            // valorPlanilhaId ausente de propósito — nunca deveria acontecer
            // na prática (PatrimonioComparador sempre preenche), mas a
            // tradução tem que se defender do mesmo jeito.
          ),
        ],
      );
      final itens = construirItensParaExecucao(
        comparacao: _lote([item]),
        decisoes: _decisoes([('p1', 'Localização atual', DecisaoCampoValor.aplicar)]),
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, isEmpty);
    });

    test('operacaoId é gerado uma vez por item, distinto entre eles', () {
      final itemA = _itemDivergente(
        patrimonioId: 'p1',
        numero: '1',
        divergencias: const [
          CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
        ],
      );
      final itemB = _itemDivergente(
        patrimonioId: 'p2',
        numero: '2',
        divergencias: const [
          CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
        ],
      );
      final itens = construirItensParaExecucao(
        comparacao: _lote([itemA, itemB]),
        decisoes: _decisoes([
          ('p1', 'Descrição', DecisaoCampoValor.aplicar),
          ('p2', 'Descrição', DecisaoCampoValor.aplicar),
        ]),
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens.map((i) => i.operacaoId).toSet(), hasLength(2));
    });
  });

  group('ComparacaoExecucaoController', () {
    test('1. ADMIN executando atualização de metadados', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456')]);
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      final lote = _lote([
        _itemDivergente(
          patrimonioId: 'p1',
          numero: '123456',
          divergencias: const [
            CampoDivergente(
              campo: 'Descrição',
              tipo: TipoDivergencia.metadado,
              valorInvtec: 'Notebook Antigo',
              valorPlanilha: 'Notebook Dell Latitude',
            ),
          ],
        ),
      ]);
      final controller = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
      await controller.confirmar(
        comparacao: lote,
        decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
        justificativa: '',
      );

      final estado = ctx.container.read(comparacaoExecucaoControllerProvider);
      expect(estado.fase, ComparacaoExecucaoFase.concluida);
      expect(estado.sucessos, 1);
      expect(repo.decisoesAplicadas, hasLength(1));
      expect(repo.decisoesAplicadas.single.descricao, 'Notebook Dell Latitude');
      expect(repo.decisoesAplicadas.single.novoSetorId, isNull);
      expect(repo.decisoesAplicadas.single.novaLocalizacaoId, isNull);
      final atualizado = await repo.buscarDetalhePorId('p1');
      expect(atualizado!.patrimonio.descricao, 'Notebook Dell Latitude');
    });

    test('2. usuário não ADMIN tentando executar não chama a "RPC" nem muda o estado', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456')]);
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.operador);
      await ctx.container.read(authControllerProvider.future);

      final lote = _lote([
        _itemDivergente(
          patrimonioId: 'p1',
          numero: '123456',
          divergencias: const [
            CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
          ],
        ),
      ]);
      final controller = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
      await controller.confirmar(
        comparacao: lote,
        decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
        justificativa: '',
      );

      expect(ctx.container.read(comparacaoExecucaoControllerProvider).fase, ComparacaoExecucaoFase.ociosa);
      expect(repo.aplicarDecisaoComparacaoCallCount, 0);
    });

    test('3. alteração somente de localização', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', localizacaoId: 'loc-antiga')],
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      final lote = _lote([
        _itemDivergente(
          patrimonioId: 'p1',
          numero: '123456',
          divergencias: const [
            CampoDivergente(
              campo: 'Localização atual',
              tipo: TipoDivergencia.localizacao,
              valorInvtec: 'Sala A',
              valorPlanilha: 'Sala B',
              valorPlanilhaId: 'loc-nova',
            ),
          ],
        ),
      ]);
      final controller = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
      await controller.confirmar(
        comparacao: lote,
        decisoes: _decisoes([('p1', 'Localização atual', DecisaoCampoValor.aplicar)]),
        justificativa: 'regularização de inventário',
      );

      expect(ctx.container.read(comparacaoExecucaoControllerProvider).sucessos, 1);
      final enviado = repo.decisoesAplicadas.single;
      expect(enviado.novaLocalizacaoId, 'loc-nova');
      expect(enviado.novoSetorId, isNull);
      expect(enviado.temMetadado, isFalse);
      expect(enviado.temMovimentacao, isTrue);
    });

    test('4. alteração de metadados e localização no mesmo patrimônio — uma única chamada, tudo ou nada', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', descricao: 'Antiga', localizacaoId: 'loc-antiga')],
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      final divergencias = const [
        CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'Antiga', valorPlanilha: 'Nova'),
        CampoDivergente(
          campo: 'Localização atual',
          tipo: TipoDivergencia.localizacao,
          valorInvtec: 'Sala A',
          valorPlanilha: 'Sala B',
          valorPlanilhaId: 'loc-nova',
        ),
      ];
      final decisoes = _decisoes([
        ('p1', 'Descrição', DecisaoCampoValor.aplicar),
        ('p1', 'Localização atual', DecisaoCampoValor.aplicar),
      ]);

      final controller = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
      await controller.confirmar(
        comparacao: _lote([_itemDivergente(patrimonioId: 'p1', numero: '123456', divergencias: divergencias)]),
        decisoes: decisoes,
        justificativa: 'regularização',
      );
      expect(repo.decisoesAplicadas, hasLength(1)); // UMA chamada, os dois campos juntos.
      expect(repo.decisoesAplicadas.single.descricao, 'Nova');
      expect(repo.decisoesAplicadas.single.novaLocalizacaoId, 'loc-nova');

      // Agora prova a garantia transacional: se a "RPC" recusa a chamada
      // inteira, NADA fica parcialmente aplicado (nem a descrição).
      final repo2 = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', descricao: 'Antiga', localizacaoId: 'loc-antiga')],
        errosExecucaoPorPatrimonioId: {'p1': falhaDeExecucaoComparacao(codigo: 'P0001', mensagemDoServidor: 'erro')},
      );
      final ctx2 = _criarContainerExecucao(repositorio: repo2, perfil: ProfilePerfil.admin);
      await ctx2.container.read(authControllerProvider.future);
      await ctx2.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([_itemDivergente(patrimonioId: 'p1', numero: '123456', divergencias: divergencias)]),
            decisoes: decisoes,
            justificativa: 'regularização',
          );
      final aindaAntigo = await repo2.buscarDetalhePorId('p1');
      expect(aindaAntigo!.patrimonio.descricao, 'Antiga'); // nunca parcialmente atualizado
      expect(aindaAntigo.patrimonio.localizacaoAtualId, 'loc-antiga');
    });

    test('5. campo ignorado permanece inalterado no cadastro final', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', descricao: 'Antiga', marca: 'DELL')],
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      final divergencias = const [
        CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'Antiga', valorPlanilha: 'Nova'),
        CampoDivergente(campo: 'Marca', tipo: TipoDivergencia.metadado, valorInvtec: 'DELL', valorPlanilha: 'LENOVO'),
      ];
      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([_itemDivergente(patrimonioId: 'p1', numero: '123456', divergencias: divergencias)]),
            decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar), ('p1', 'Marca', DecisaoCampoValor.ignorar)]),
            justificativa: '',
          );

      final atualizado = await repo.buscarDetalhePorId('p1');
      expect(atualizado!.patrimonio.descricao, 'Nova');
      expect(atualizado.patrimonio.marca, 'DELL'); // ignorado — nunca tocado
    });

    test('8. destino inválido — recusa síncrona, nada gravado', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        errosExecucaoPorPatrimonioId: {
          'p1': falhaDeExecucaoComparacao(
            codigo: 'P0001',
            mensagemDoServidor: 'A localização de destino informada não pertence ao setor de destino',
          ),
        },
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(
                    campo: 'Localização atual',
                    tipo: TipoDivergencia.localizacao,
                    valorInvtec: 'A',
                    valorPlanilha: 'B',
                    valorPlanilhaId: 'loc-invalida',
                  ),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Localização atual', DecisaoCampoValor.aplicar)]),
            justificativa: 'j',
          );

      final estado = ctx.container.read(comparacaoExecucaoControllerProvider);
      expect(estado.falhas, 1);
      expect(estado.itens['p1']!.status, ItemExecucaoStatus.falha);
      expect(repo.decisoesAplicadas, isEmpty);
    });

    test('9. patrimônio com impedimento SEI — recusado com mensagem específica', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        errosExecucaoPorPatrimonioId: {
          'p1': falhaDeExecucaoComparacao(codigo: 'P0042', mensagemDoServidor: 'pendência SEI'),
        },
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(
                    campo: 'Setor atual',
                    tipo: TipoDivergencia.setor,
                    valorInvtec: 'A',
                    valorPlanilha: 'B',
                    valorPlanilhaId: 'setor-novo',
                  ),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Setor atual', DecisaoCampoValor.aplicar)]),
            justificativa: 'j',
          );

      final item = ctx.container.read(comparacaoExecucaoControllerProvider).itens['p1']!;
      expect(item.status, ItemExecucaoStatus.falha);
      expect(item.falha!.message, contains('pendência SEI'));
      expect(repo.decisoesAplicadas, isEmpty);
    });

    test('10. alteração concorrente após a comparação — conflito de versão, nunca sobrescreve', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', descricao: 'Antiga', atualizadoEm: DateTime(2026, 1, 1))],
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      // Simula OUTRA sessão alterando o patrimônio depois da comparação.
      repo.substituirDetalhe(
        _patrimonio(id: 'p1', numero: '123456', descricao: 'Alterada por outro usuário', atualizadoEm: DateTime(2026, 2, 1)),
      );

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            // versaoAtualizadoEm CONGELADA na referência antiga (2026-01-01) —
            // representa a comparação feita ANTES da alteração concorrente.
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                versao: DateTime(2026, 1, 1),
                divergencias: const [
                  CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'Antiga', valorPlanilha: 'Nova'),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
            justificativa: '',
          );

      final item = ctx.container.read(comparacaoExecucaoControllerProvider).itens['p1']!;
      expect(item.status, ItemExecucaoStatus.falha);
      expect(item.falha!.codigo, 'P0040');
      expect(item.falha!.message, contains('alterado por outra operação'));
      final aindaComOutroValor = await repo.buscarDetalhePorId('p1');
      expect(aindaComOutroValor!.patrimonio.descricao, 'Alterada por outro usuário'); // nunca sobrescrito
    });

    test('11. falha durante processamento (erro genérico do servidor)', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        errosExecucaoPorPatrimonioId: {
          'p1': falhaDeExecucaoComparacao(codigo: null, mensagemDoServidor: 'erro interno qualquer'),
        },
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
            justificativa: '',
          );

      expect(ctx.container.read(comparacaoExecucaoControllerProvider).itens['p1']!.status, ItemExecucaoStatus.falha);
    });

    test('12/13. timeout após gravação efetiva e retry sem duplicar', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        operacaoIdsComRespostaPerdida: {'op-0'},
      );
      final ctx = _criarContainerExecucao(
        repositorio: repo,
        perfil: ProfilePerfil.admin,
        gerarLoteId: () => 'lote-fixo',
        gerarOperacaoId: _geradorSequencial('op'),
      );
      await ctx.container.read(authControllerProvider.future);

      final lote = _lote([
        _itemDivergente(
          patrimonioId: 'p1',
          numero: '123456',
          divergencias: const [
            CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
          ],
        ),
      ]);
      final controller = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
      await controller.confirmar(
        comparacao: lote,
        decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
        justificativa: '',
      );

      // 12. a escrita REALMENTE aconteceu, mas a resposta se perdeu.
      var estado = ctx.container.read(comparacaoExecucaoControllerProvider);
      expect(estado.itens['p1']!.status, ItemExecucaoStatus.resultadoDesconhecido);
      expect(repo.decisoesAplicadas, hasLength(1));
      final resultadoJaGravado = await repo.buscarExecucaoComparacaoPorOperacaoId('op-0');
      expect(resultadoJaGravado, isNotNull);

      // 13. retry com o MESMO operacaoId — encontra o registro, nenhuma escrita nova.
      await controller.retryItem('p1');
      estado = ctx.container.read(comparacaoExecucaoControllerProvider);
      expect(estado.itens['p1']!.status, ItemExecucaoStatus.sucesso);
      expect(estado.itens['p1']!.resultado!.jaExecutado, isTrue);
      expect(repo.decisoesAplicadas, hasLength(1)); // continua 1 — nenhuma duplicação.
      expect(repo.aplicarDecisaoComparacaoCallCount, 2); // chamou de novo, mas sem escrever de novo.
    });

    test(
      '14. troca de usuário interrompe novas solicitações (uma nova confirmação não é aceita após a troca)',
      () async {
        final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456')]);
        final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
        await ctx.container.read(authControllerProvider.future);

        final controller = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
        await controller.confirmar(
          comparacao: _lote([
            _itemDivergente(
              patrimonioId: 'p1',
              numero: '123456',
              divergencias: const [
                CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
              ],
            ),
          ]),
          decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
          justificativa: '',
        );
        expect(ctx.container.read(comparacaoExecucaoControllerProvider).sucessos, 1);
        expect(repo.aplicarDecisaoComparacaoCallCount, 1);

        // Troca de usuário (logout) — o estado local é descartado (mesma
        // defesa em profundidade de `SeiConclusaoLoteController`).
        await ctx.auth.signOut();
        await ctx.container.read(authControllerProvider.future);
        expect(ctx.container.read(comparacaoExecucaoControllerProvider).total, 0);

        // Uma NOVA solicitação de execução, depois da troca, nunca é aceita
        // (nem chega a chamar o repositório): o perfil da sessão atual não
        // é mais ADMIN (usuário deslogado).
        await controller.confirmar(
          comparacao: _lote([
            _itemDivergente(
              patrimonioId: 'p2',
              numero: '654321',
              divergencias: const [
                CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
              ],
            ),
          ]),
          decisoes: _decisoes([('p2', 'Descrição', DecisaoCampoValor.aplicar)]),
          justificativa: '',
        );
        expect(repo.aplicarDecisaoComparacaoCallCount, 1); // continua 1 — nenhuma chamada nova.
      },
    );

    test('15. processamento fictício com aproximadamente 500 itens', () async {
      final patrimonios = [
        for (var i = 0; i < 500; i++) _patrimonio(id: 'p$i', numero: '${100000 + i}', descricao: 'Antiga $i'),
      ];
      final repo = FakePatrimonioRepository(itens: patrimonios);
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      final itensComparacao = [
        for (var i = 0; i < 500; i++)
          _itemDivergente(
            patrimonioId: 'p$i',
            numero: '${100000 + i}',
            divergencias: [
              CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'Antiga $i', valorPlanilha: 'Nova $i'),
            ],
          ),
      ];
      final decisoes = _decisoes([
        for (var i = 0; i < 500; i++) ('p$i', 'Descrição', DecisaoCampoValor.aplicar),
      ]);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(comparacao: _lote(itensComparacao), decisoes: decisoes, justificativa: '');

      final estado = ctx.container.read(comparacaoExecucaoControllerProvider);
      expect(estado.total, 500);
      expect(estado.sucessos, 500);
      expect(repo.decisoesAplicadas, hasLength(500));
    });
  });

  group('16. preservação — importação/comparação convencional inalteradas', () {
    final tipos = [TipoPatrimonio(id: 'tipo-notebook', nome: 'Notebook', ativo: true, criadoEm: DateTime(2026, 1, 1))];
    final setores = [Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1))];

    ({ProviderContainer container, FakeAuthRepository auth}) criarContainerImportacao({
      required FakePatrimonioRepository repositorio,
      required ProfilePerfil perfil,
      String Function()? gerarOperacaoId,
    }) {
      final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (id) => _perfil(perfil, id: id));
      final container = ProviderContainer(
        overrides: [
          patrimonioRepositoryProvider.overrideWithValue(repositorio),
          tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: tipos)),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: setores)),
          localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: const <Localizacao>[])),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
          authRepositoryProvider.overrideWithValue(auth),
          comparacaoExecucaoControllerProvider.overrideWith(
            () => ComparacaoExecucaoController(
              gerarLoteId: () => 'lote-fixo',
              gerarOperacaoId: gerarOperacaoId,
              comparacaoExecucaoHabilitada: () => true,
            ),
          ),
        ],
      );
      container.listen(patrimonioImportControllerProvider, (_, _) {});
      container.listen(comparacaoExecucaoControllerProvider, (_, _) {});
      addTearDown(() {
        container.dispose();
        auth.dispose();
      });
      return (container: container, auth: auth);
    }

    test('uma execução pendente (resultado desconhecido) bloqueia uma NOVA comparação', () async {
      // operacaoId determinístico 'op-0' — a escrita real chega a acontecer
      // no fake, mas a RESPOSTA se perde (mesmo cenário do 12/13), deixando
      // o item em resultadoDesconhecido de verdade (não uma simulação
      // parcial).
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        operacaoIdsComRespostaPerdida: {'op-0'},
      );
      final ctx = criarContainerImportacao(
        repositorio: repo,
        perfil: ProfilePerfil.admin,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      await ctx.container.read(authControllerProvider.future);

      final execucaoController = ctx.container.read(comparacaoExecucaoControllerProvider.notifier);
      await execucaoController.confirmar(
        comparacao: _lote([
          _itemDivergente(
            patrimonioId: 'p1',
            numero: '123456',
            divergencias: const [
              CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
            ],
          ),
        ]),
        decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
        justificativa: '',
      );
      expect(ctx.container.read(comparacaoExecucaoControllerProvider).temPendencia, isTrue);

      // PROMPT 11.6.4, seção 7/9 — uma nova comparação nunca começa enquanto
      // essa pendência não for resolvida (retry/reconciliar).
      final importController = ctx.container.read(patrimonioImportControllerProvider.notifier);
      await importController.compararParaAdmin();

      expect(ctx.container.read(patrimonioImportControllerProvider).mensagemErro, mensagemComparacaoBloqueadaPorExecucaoPendente);

      // Resolvendo a pendência (retry — idempotente, encontra a escrita já
      // feita), uma nova comparação volta a ser permitida.
      await execucaoController.retryItem('p1');
      expect(ctx.container.read(comparacaoExecucaoControllerProvider).temPendencia, isFalse);
    });

    test('cadastro/atualização convencionais nunca chamam aplicarDecisaoComparacao', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456')]);
      final ctx = criarContainerImportacao(repositorio: repo, perfil: ProfilePerfil.operador);
      await ctx.container.read(authControllerProvider.future);

      await repo.cadastrar(tipoId: 'tipo-notebook', destinoId: 'setor-getec', numeroPatrimonio: '999999');
      await repo.atualizar(id: 'p1', tipoId: 'tipo-notebook', descricao: 'Nova descrição');

      expect(repo.aplicarDecisaoComparacaoCallCount, 0);
      expect(repo.cadastrarCallCount, 1);
      expect(repo.atualizarCallCount, 1);
    });
  });

  group('PROMPT 11.6.5 — auditoria de homologação', () {
    test('ehFalhaDeTransporte reconhece códigos de gateway/timeout, nunca um SQLSTATE real', () {
      for (final codigo in ['500', '502', '503', '504', '408']) {
        expect(ehFalhaDeTransporte(codigo), isTrue, reason: codigo);
      }
      for (final codigo in ['P0040', 'P0041', 'P0042', 'P0043', '42501', '23505', 'P0001', 'P0002', null]) {
        expect(ehFalhaDeTransporte(codigo), isFalse, reason: '$codigo');
      }
    });

    test('mensagemErroExecucaoComparacao nunca apresenta uma falha de transporte como recusa definitiva', () {
      final mensagem = mensagemErroExecucaoComparacao(codigo: '503', mensagemDoServidor: 'Service Unavailable');
      expect(mensagem, isNot(contains('Nada foi gravado')));
      expect(mensagem.toLowerCase(), contains('não foi possível confirmar'));
    });

    test('seção 9 — configuração desabilitada (padrão) bloqueia a execução real, mesmo ADMIN e itens elegíveis', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456')]);
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin, comparacaoExecucaoHabilitada: false);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Descrição', DecisaoCampoValor.aplicar)]),
            justificativa: '',
          );

      expect(ctx.container.read(comparacaoExecucaoControllerProvider).fase, ComparacaoExecucaoFase.ociosa);
      expect(repo.aplicarDecisaoComparacaoCallCount, 0);
    });

    test('seção 2C — mesmo operacaoId com justificativa diferente é conflito (P0041), nunca reaproveitado', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456', localizacaoId: 'loc-antiga')]);
      final primeira = DecisaoItemParaExecutar(
        operacaoId: 'op-fixo',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        numeroPatrimonio: '123456',
        versaoEsperada: DateTime(2026, 1, 1),
        justificativa: 'motivo A',
        novoSetorId: null,
        novaLocalizacaoId: 'loc-nova',
      );
      await repo.aplicarDecisaoComparacao(primeira);
      expect(repo.decisoesAplicadas, hasLength(1));

      final segundaComJustificativaDiferente = DecisaoItemParaExecutar(
        operacaoId: 'op-fixo',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        numeroPatrimonio: '123456',
        versaoEsperada: DateTime(2026, 1, 1),
        justificativa: 'motivo B — diferente',
        novoSetorId: null,
        novaLocalizacaoId: 'loc-nova',
      );
      await expectLater(
        () => repo.aplicarDecisaoComparacao(segundaComJustificativaDiferente),
        throwsA(isA<ComparacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0041')),
      );
      expect(repo.decisoesAplicadas, hasLength(1)); // nenhuma segunda escrita.
    });

    test('seção 2C — mesmo operacaoId com campo diferente é conflito (P0041)', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456', descricao: 'Antiga')]);
      final primeira = DecisaoItemParaExecutar(
        operacaoId: 'op-fixo',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        numeroPatrimonio: '123456',
        versaoEsperada: DateTime(2026, 1, 1),
        descricao: 'Nova A',
      );
      await repo.aplicarDecisaoComparacao(primeira);

      final segundaComDescricaoDiferente = DecisaoItemParaExecutar(
        operacaoId: 'op-fixo',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        numeroPatrimonio: '123456',
        versaoEsperada: DateTime(2026, 1, 1),
        descricao: 'Nova B — diferente',
      );
      await expectLater(
        () => repo.aplicarDecisaoComparacao(segundaComDescricaoDiferente),
        throwsA(isA<ComparacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0041')),
      );
    });

    test('seção 2E — duas operações (ids diferentes) do mesmo snapshot: a primeira conclui, a segunda detecta conflito', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', descricao: 'Antiga', atualizadoEm: DateTime(2026, 1, 1))],
      );
      final mesmoSnapshot = DateTime(2026, 1, 1);

      final operacaoA = DecisaoItemParaExecutar(
        operacaoId: 'op-A',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        numeroPatrimonio: '123456',
        versaoEsperada: mesmoSnapshot,
        descricao: 'Versão de A',
      );
      final operacaoB = DecisaoItemParaExecutar(
        operacaoId: 'op-B',
        loteId: 'lote-1',
        patrimonioId: 'p1',
        numeroPatrimonio: '123456',
        versaoEsperada: mesmoSnapshot,
        descricao: 'Versão de B',
      );

      final resultadoA = await repo.aplicarDecisaoComparacao(operacaoA);
      expect(resultadoA.jaExecutado, isFalse);
      final atualizado = await repo.buscarDetalhePorId('p1');
      expect(atualizado!.patrimonio.descricao, 'Versão de A');

      // B chega DEPOIS, com o mesmo snapshot (agora desatualizado) — nunca
      // aplica por cima de A: detecta o conflito de versão.
      await expectLater(
        () => repo.aplicarDecisaoComparacao(operacaoB),
        throwsA(isA<ComparacaoExecucaoFalhouException>().having((e) => e.codigo, 'codigo', 'P0040')),
      );
      final aindaDeA = await repo.buscarDetalhePorId('p1');
      expect(aindaDeA!.patrimonio.descricao, 'Versão de A'); // nunca sobrescrito por B.
    });

    test('3 — setor isoladamente: sucesso, e a localização (do setor antigo) é limpa pela regra já homologada', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456', setorId: 'setor-antigo', localizacaoId: 'loc-no-setor-antigo')],
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(
                    campo: 'Setor atual',
                    tipo: TipoDivergencia.setor,
                    valorInvtec: 'Setor Antigo',
                    valorPlanilha: 'Setor Novo',
                    valorPlanilhaId: 'setor-novo',
                  ),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Setor atual', DecisaoCampoValor.aplicar)]),
            justificativa: 'regularização de setor',
          );

      expect(ctx.container.read(comparacaoExecucaoControllerProvider).sucessos, 1);
      final atualizado = await repo.buscarDetalhePorId('p1');
      expect(atualizado!.patrimonio.setorAtualId, 'setor-novo');
      expect(atualizado.patrimonio.localizacaoAtualId, isNull); // limpa — pertencia só ao setor antigo.
    });

    test('3 — setor incompatível com a localização informada é recusado, nada gravado', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        errosExecucaoPorPatrimonioId: {
          'p1': falhaDeExecucaoComparacao(
            codigo: 'P0001',
            mensagemDoServidor: 'A localização de destino informada não pertence ao setor de destino',
          ),
        },
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(
                    campo: 'Setor atual',
                    tipo: TipoDivergencia.setor,
                    valorInvtec: 'A',
                    valorPlanilha: 'B',
                    valorPlanilhaId: 'setor-novo',
                  ),
                  CampoDivergente(
                    campo: 'Localização atual',
                    tipo: TipoDivergencia.localizacao,
                    valorInvtec: 'C',
                    valorPlanilha: 'D',
                    valorPlanilhaId: 'loc-de-outro-setor',
                  ),
                ],
              ),
            ]),
            decisoes: _decisoes([
              ('p1', 'Setor atual', DecisaoCampoValor.aplicar),
              ('p1', 'Localização atual', DecisaoCampoValor.aplicar),
            ]),
            justificativa: 'j',
          );

      final item = ctx.container.read(comparacaoExecucaoControllerProvider).itens['p1']!;
      expect(item.status, ItemExecucaoStatus.falha);
      expect(repo.decisoesAplicadas, isEmpty);
    });

    test('3 — patrimônio com bloqueio (BAIXADO) recusa alteração de setor/localização, nada gravado', () async {
      final repo = FakePatrimonioRepository(
        itens: [_patrimonio(id: 'p1', numero: '123456')],
        errosExecucaoPorPatrimonioId: {
          'p1': falhaDeExecucaoComparacao(codigo: 'P0001', mensagemDoServidor: 'Patrimônio baixado não pode mudar de setor'),
        },
      );
      final ctx = _criarContainerExecucao(repositorio: repo, perfil: ProfilePerfil.admin);
      await ctx.container.read(authControllerProvider.future);

      await ctx.container
          .read(comparacaoExecucaoControllerProvider.notifier)
          .confirmar(
            comparacao: _lote([
              _itemDivergente(
                patrimonioId: 'p1',
                numero: '123456',
                divergencias: const [
                  CampoDivergente(
                    campo: 'Setor atual',
                    tipo: TipoDivergencia.setor,
                    valorInvtec: 'A',
                    valorPlanilha: 'B',
                    valorPlanilhaId: 'setor-novo',
                  ),
                ],
              ),
            ]),
            decisoes: _decisoes([('p1', 'Setor atual', DecisaoCampoValor.aplicar)]),
            justificativa: 'j',
          );

      final item = ctx.container.read(comparacaoExecucaoControllerProvider).itens['p1']!;
      expect(item.status, ItemExecucaoStatus.falha);
      expect(repo.decisoesAplicadas, isEmpty);
    });

    test('seção 1 — uma sessão diferente nunca recebe o resultado de uma operação que não é dela', () async {
      final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '123456')], autorId: 'admin-A');
      final resultado = await repo.aplicarDecisaoComparacao(
        DecisaoItemParaExecutar(
          operacaoId: 'op-de-a',
          loteId: 'lote-1',
          patrimonioId: 'p1',
          numeroPatrimonio: '123456',
          versaoEsperada: DateTime(2026, 1, 1),
          descricao: 'Nova',
        ),
      );
      expect(resultado.jaExecutado, isFalse);

      // A própria sessão A consegue reler normalmente.
      expect(await repo.buscarExecucaoComparacaoPorOperacaoId('op-de-a'), isNotNull);

      // Uma sessão B (outro ADMIN) NUNCA recebe o resultado da operação de A.
      repo.usuarioAtualParaTeste = 'admin-B';
      await expectLater(
        () => repo.buscarExecucaoComparacaoPorOperacaoId('op-de-a'),
        throwsA(isA<AppException>()),
      );
    });

    test('número patrimonial nunca é um campo comparável/aplicável neste fluxo', () {
      // Mesmo que uma decisão "aplicar" exista para o rótulo antigo (por
      // engano de um chamador), a tradução não tem NENHUM campo de destino
      // para ele — DecisaoItemParaExecutar não possui mais esse parâmetro
      // (removido em definitivo, seção 4).
      final item = _itemDivergente(
        patrimonioId: 'p1',
        numero: '123456',
        divergencias: const [
          CampoDivergente(campo: 'Descrição', tipo: TipoDivergencia.metadado, valorInvtec: 'A', valorPlanilha: 'B'),
        ],
      );
      final itens = construirItensParaExecucao(
        comparacao: _lote([item]),
        decisoes: _decisoes([
          ('p1', 'Número patrimonial', DecisaoCampoValor.aplicar),
          ('p1', 'Descrição', DecisaoCampoValor.aplicar),
        ]),
        loteId: 'lote-1',
        justificativa: null,
        gerarOperacaoId: _geradorSequencial('op'),
      );
      expect(itens, hasLength(1));
      expect(itens.single.descricao, 'B');
    });
  });
}
