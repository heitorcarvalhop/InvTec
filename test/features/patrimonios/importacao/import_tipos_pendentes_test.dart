import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_repository.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_row.dart';
import 'package:invtec/features/patrimonios/importacao/domain/profiles/tipo_inference.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/patrimonios/presentation/patrimonio_reference_data.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// Catálogo de tipos usado só nestes testes — inclui um tipo INATIVO
/// (`tipo-obsoleto`) especificamente para provar que a tela de pendências
/// nunca o oferece como opção (PROMPT 8.13, seção 2/9).
final _tipos = [
  TipoPatrimonio(id: 'tipo-rede', nome: 'Equipamento de Rede', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-mobiliario', nome: 'Mobiliário', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-obsoleto', nome: 'Obsoleto', ativo: false, criadoEm: DateTime(2026, 1, 1)),
];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
const _localizacoes = <Localizacao>[];

ProviderContainer _criarContainer(PatrimonioRepository repositorio) {
  final container = ProviderContainer(
    overrides: [
      patrimonioRepositoryProvider.overrideWithValue(repositorio),
      tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
      setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
      localizacaoRepositoryProvider.overrideWithValue(FakeLocalizacaoRepository(localizacoes: _localizacoes)),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
    ],
  );
  container.listen(patrimonioImportControllerProvider, (_, _) {});
  return container;
}

Uint8List _csv(String conteudo) => Uint8List.fromList(utf8.encode(conteudo));

/// Planilha genérica (perfil não-GETEC) SEM coluna de tipo mapeada — todas
/// as linhas ficam bloqueadas por "Tipo é obrigatório e está vazio"
/// (a mesma condição que, na planilha real da GETEC, afeta os 37
/// registros — PROMPT 8.13). Duas linhas com a mesma descrição (grupo
/// "semelhantes" de 2) e uma linha com descrição diferente (grupo de 1).
const _csvSemTipo =
    'Patrimônio;Descricao;Marca;Serial;Setor\n'
    '00001;RACK PADRAO PISO;Dell;S1;GETEC\n'
    '00002;RACK PADRAO PISO;Dell;S2;GETEC\n'
    '00003;OUTRA COISA QUALQUER;Dell;S3;GETEC\n';

Future<void> _avancarAteTiposPendentes(
  PatrimonioImportController controller, {
  String csv = _csvSemTipo,
}) async {
  await controller.carregarArquivo(nomeArquivo: 'inventario.csv', bytes: _csv(csv));
  controller.confirmarCabecalho();
  controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
  controller.definirColuna(ImportColumnField.descricao, 1);
  controller.definirColuna(ImportColumnField.marca, 2);
  controller.definirColuna(ImportColumnField.numeroSerie, 3);
  controller.definirColuna(ImportColumnField.setor, 4);
  controller.avancarParaPadroes();
  controller.definirPadroes(const ImportDefaults(origemPadraoId: 'setor-almoxarifado'));
  await controller.analisar();
}

void main() {
  group('PatrimonioImportController — tela de pendências de tipo (PROMPT 8.13)', () {
    test('linha sem tipo começa bloqueada e a análise para no passo de tipos pendentes', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.step, ImportStep.resolverTipos);
      expect(state.linhas.every((l) => l.status == ImportRowStatus.erro), isTrue);
      expect(
        state.linhas.every((l) => l.issues.any((i) => i.message.contains('Tipo é obrigatório'))),
        isTrue,
      );
      expect(state.totalTipoPendente, 3);
      expect(state.tipoPendenteRestantes, 3);
      expect(state.tipoPendenteResolvidos, 0);
    });

    test('seleção manual de tipo desbloqueia a linha', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final linha = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
            (l) => l.numeroPatrimonio == '00003',
          );

      controller.definirTipoPendente(linha, 'tipo-mobiliario');

      expect(linha.tipoIdResolvido, 'tipo-mobiliario');
      expect(linha.status, isNot(ImportRowStatus.erro));
      expect(linha.seraEnviada, isTrue);
      expect(container.read(patrimonioImportControllerProvider).tipoPendenteRestantes, 2);
    });

    test('o id usado vem do catálogo ativo real carregado (nunca hardcoded)', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final tiposAtivos = await container.read(tiposAtivosProvider.future);
      final linha = container.read(patrimonioImportControllerProvider).linhas.first;

      final escolhido = tiposAtivos.first;
      controller.definirTipoPendente(linha, escolhido.id);

      expect(tiposAtivos.map((t) => t.id), contains(linha.tipoIdResolvido));
      expect(linha.tipoIdResolvido, escolhido.id);
    });

    test('tipo inativo carregado no catálogo nunca aparece entre os tipos ativos oferecidos', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);

      final tiposAtivos = await container.read(tiposAtivosProvider.future);

      expect(tiposAtivos.any((t) => t.id == 'tipo-obsoleto'), isFalse);
      expect(tiposAtivos.map((t) => t.nome), isNot(contains('Obsoleto')));
    });

    test('decisão manual sobrevive a uma reanálise completa da sessão', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final numeroLinhaAlvo = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroPatrimonio == '00003')
          .numeroLinha;
      controller.definirTipoPendente(
        container.read(patrimonioImportControllerProvider).linhas.firstWhere(
              (l) => l.numeroLinha == numeroLinhaAlvo,
            ),
        'tipo-mobiliario',
      );

      // reanálise completa: ImportRow são recriados do zero.
      await controller.analisar();

      final linhaRecriada = container
          .read(patrimonioImportControllerProvider)
          .linhas
          .firstWhere((l) => l.numeroLinha == numeroLinhaAlvo);
      expect(linhaRecriada.tipoIdResolvido, 'tipo-mobiliario');
      expect(linhaRecriada.tipoResolvidoManualmente, isTrue);
      expect(linhaRecriada.status, isNot(ImportRowStatus.erro));
      // as outras 2 linhas continuam pendentes: só restam elas no passo.
      expect(container.read(patrimonioImportControllerProvider).tipoPendenteRestantes, 2);
    });

    test('aplicação em lote afeta somente o grupo de descrição escolhido', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      final rackUm = linhas.firstWhere((l) => l.numeroPatrimonio == '00001');
      final rackDois = linhas.firstWhere((l) => l.numeroPatrimonio == '00002');
      final outra = linhas.firstWhere((l) => l.numeroPatrimonio == '00003');

      final grupo = controller.linhasSemelhantesPendentes(rackUm);
      expect(grupo, hasLength(2));
      expect(grupo, containsAll([rackUm, rackDois]));
      expect(grupo, isNot(contains(outra)));

      controller.aplicarTipoEmLote(grupo, 'tipo-rede');

      expect(rackUm.tipoIdResolvido, 'tipo-rede');
      expect(rackDois.tipoIdResolvido, 'tipo-rede');
      expect(outra.tipoIdResolvido, isNull);
      expect(container.read(patrimonioImportControllerProvider).tipoPendenteRestantes, 1);
    });

    test('decisão manual (inclusive em lote) nunca altera o classificador global de tipo', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      // antes de qualquer decisão: "RACK" não é reconhecido pelo classificador.
      expect(
        inferirTipoPorDescricao('RACK PADRAO PISO').confianca,
        InferenciaTipoConfianca.naoIdentificada,
      );

      await _avancarAteTiposPendentes(controller);
      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      final grupoRack = linhas.where((l) => l.descricao == 'RACK PADRAO PISO').toList();
      controller.aplicarTipoEmLote(grupoRack, 'tipo-rede');

      // depois da decisão em lote desta sessão: o classificador GLOBAL
      // continua exatamente igual — nunca aprendeu "rack" -> Equipamento de
      // Rede (seção 3/8 do PROMPT 8.13).
      expect(
        inferirTipoPorDescricao('RACK PADRAO PISO').confianca,
        InferenciaTipoConfianca.naoIdentificada,
      );
      expect(
        inferirTipoPorDescricao('RACK 04 OUTRO PATRIMONIO').confianca,
        InferenciaTipoConfianca.naoIdentificada,
      );
    });

    test('voltar para o passo anterior preserva as escolhas já feitas', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final linha = container.read(patrimonioImportControllerProvider).linhas.firstWhere(
            (l) => l.numeroPatrimonio == '00003',
          );
      controller.definirTipoPendente(linha, 'tipo-mobiliario');

      controller.voltar();

      final state = container.read(patrimonioImportControllerProvider);
      expect(state.mapeamentoTiposPendentes[linha.numeroLinha], 'tipo-mobiliario');
      expect(linha.tipoIdResolvido, 'tipo-mobiliario');
    });

    test('resolver todas as pendências chega a zero restantes', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      final grupoRack = linhas.where((l) => l.descricao == 'RACK PADRAO PISO').toList();
      final outra = linhas.firstWhere((l) => l.numeroPatrimonio == '00003');

      controller.aplicarTipoEmLote(grupoRack, 'tipo-rede');
      controller.definirTipoPendente(outra, 'tipo-mobiliario');

      final estadoFinal = container.read(patrimonioImportControllerProvider);
      expect(estadoFinal.tipoPendenteRestantes, 0);
      expect(estadoFinal.tipoPendenteResolvidos, 3);
      expect(estadoFinal.linhas.every((l) => l.seraEnviada), isTrue);
    });

    test('nenhuma ação da tela de pendências chama cadastro ou atualização no repositório', () async {
      final repo = FakePatrimonioRepository();
      final container = _criarContainer(repo);
      addTearDown(container.dispose);
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      await _avancarAteTiposPendentes(controller);
      final linhas = container.read(patrimonioImportControllerProvider).linhas;
      final grupoRack = linhas.where((l) => l.descricao == 'RACK PADRAO PISO').toList();
      final outra = linhas.firstWhere((l) => l.numeroPatrimonio == '00003');

      controller.aplicarTipoEmLote(grupoRack, 'tipo-rede');
      controller.definirTipoPendente(outra, 'tipo-mobiliario');
      controller.avancarDeTiposPendentesParaRevisao();

      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
      expect(container.read(patrimonioImportControllerProvider).step, ImportStep.revisar);
    });

    test(
      'avancarDeTiposPendentesParaRevisao é rejeitado enquanto restantes > 0, e só permitido em 0 '
      '(proteção no controller, não só desabilitar o botão na UI — PROMPT 8.13.1)',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await _avancarAteTiposPendentes(controller);
        final linhas = List<ImportRow>.from(container.read(patrimonioImportControllerProvider).linhas);
        expect(linhas, hasLength(3));

        // Restantes 3 -> bloqueado.
        controller.avancarDeTiposPendentesParaRevisao();
        expect(container.read(patrimonioImportControllerProvider).step, ImportStep.resolverTipos);

        controller.definirTipoPendente(linhas[0], 'tipo-mobiliario');
        // Restantes 2 -> bloqueado.
        controller.avancarDeTiposPendentesParaRevisao();
        expect(container.read(patrimonioImportControllerProvider).step, ImportStep.resolverTipos);

        controller.definirTipoPendente(linhas[1], 'tipo-mobiliario');
        // Restantes 1 -> bloqueado.
        controller.avancarDeTiposPendentesParaRevisao();
        expect(container.read(patrimonioImportControllerProvider).step, ImportStep.resolverTipos);

        controller.definirTipoPendente(linhas[2], 'tipo-mobiliario');
        // Restantes 0 -> permitido.
        expect(container.read(patrimonioImportControllerProvider).tipoPendenteRestantes, 0);
        controller.avancarDeTiposPendentesParaRevisao();
        expect(container.read(patrimonioImportControllerProvider).step, ImportStep.revisar);
      },
    );

    test(
      'numeroLinha é estável: uma decisão continua associada ao patrimônio correto depois de uma '
      'reanálise completa, mesmo tomada fora de ordem (PROMPT 8.13.1, seção 5)',
      () async {
        final repo = FakePatrimonioRepository();
        final container = _criarContainer(repo);
        addTearDown(container.dispose);
        final controller = container.read(patrimonioImportControllerProvider.notifier);

        await _avancarAteTiposPendentes(controller);
        final linhas = container.read(patrimonioImportControllerProvider).linhas;
        final porNumero = {for (final l in linhas) l.numeroPatrimonio!: l};

        // ordem deliberadamente fora de sequência (última linha primeiro).
        controller.definirTipoPendente(porNumero['00003']!, 'tipo-mobiliario');
        controller.definirTipoPendente(porNumero['00001']!, 'tipo-rede');
        controller.definirTipoPendente(porNumero['00002']!, 'tipo-rede');

        // reanálise completa: os objetos ImportRow são recriados do zero.
        await controller.analisar();

        final linhasRecriadas = container.read(patrimonioImportControllerProvider).linhas;
        final porNumeroDepois = {for (final l in linhasRecriadas) l.numeroPatrimonio!: l};

        expect(porNumeroDepois['00001']!.tipoIdResolvido, 'tipo-rede');
        expect(porNumeroDepois['00002']!.tipoIdResolvido, 'tipo-rede');
        expect(porNumeroDepois['00003']!.tipoIdResolvido, 'tipo-mobiliario');
        expect(container.read(patrimonioImportControllerProvider).tipoPendenteRestantes, 0);
      },
    );
  });
}
