import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/tipo_patrimonio.dart';
import 'package:invtec/features/patrimonios/importacao/data/spreadsheet_parser.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_page.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// Widget test dedicado à confirmação da aplicação em lote (PROMPT 8.13,
/// seção 4) — comportamento que só existe na UI (o controller nunca exige
/// confirmação sozinho; quem decide interromper para perguntar é a tela).
///
/// Monta as linhas diretamente (em vez de `carregarArquivo`, que usa
/// `compute()` para decodificar o arquivo num isolate real): sob
/// `testWidgets`/`AutomatedTestWidgetsFlutterBinding`, aguardar uma
/// resposta de isolate real pode travar o teste indefinidamente — o
/// pipeline de análise em si (`ImportAnalyzer`/`analisar()`) é puro e não
/// depende do parser de arquivo, então isso não perde cobertura nenhuma do
/// comportamento sob teste.
final _tipos = [
  TipoPatrimonio(id: 'tipo-rede', nome: 'Equipamento de Rede', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  TipoPatrimonio(id: 'tipo-mobiliario', nome: 'Mobiliário', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
final _setores = [
  Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GE', ativo: true, criadoEm: DateTime(2026, 1, 1)),
  Setor(id: 'setor-almoxarifado', nome: 'Almoxarifado', ativo: true, criadoEm: DateTime(2026, 1, 1)),
];
const _localizacoes = <Localizacao>[];

final _linhasCsv = <List<Object?>>[
  ['Patrimônio', 'Descricao', 'Marca', 'Serial', 'Setor'],
  ['00001', 'RACK PADRAO PISO', 'Dell', 'S1', 'GETEC'],
  ['00002', 'RACK PADRAO PISO', 'Dell', 'S2', 'GETEC'],
  ['00003', 'OUTRA COISA QUALQUER', 'Dell', 'S3', 'GETEC'],
];

Future<PatrimonioImportController> _avancarAteTiposPendentes(ProviderContainer container) async {
  final controller = container.read(patrimonioImportControllerProvider.notifier);
  controller.state = PatrimonioImportState(
    abas: [ImportParsedSheet(nome: 'Sheet1', linhas: _linhasCsv)],
    abaSelecionadaIndice: 0,
  );
  controller.definirColuna(ImportColumnField.numeroPatrimonio, 0);
  controller.definirColuna(ImportColumnField.descricao, 1);
  controller.definirColuna(ImportColumnField.marca, 2);
  controller.definirColuna(ImportColumnField.numeroSerie, 3);
  controller.definirColuna(ImportColumnField.setor, 4);
  controller.avancarParaPadroes();
  controller.definirPadroes(const ImportDefaults(origemPadraoId: 'setor-almoxarifado'));
  await controller.analisar();
  return controller;
}

void main() {
  testWidgets(
    'aplicar aos semelhantes exige confirmação, respeita o cancelamento e só afeta o grupo escolhido',
    (tester) async {
      // Viewport alto o bastante para o indicador de passos (PROMPT 9.3) +
      // o conteúdo do passo não empurrar os elementos tocados abaixo da
      // área visível do teste.
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakePatrimonioRepository();
      final container = ProviderContainer(
        overrides: [
          patrimonioRepositoryProvider.overrideWithValue(repo),
          tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: _tipos)),
          setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: _setores)),
          localizacaoRepositoryProvider.overrideWithValue(
            FakeLocalizacaoRepository(localizacoes: _localizacoes),
          ),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(patrimonioImportControllerProvider, (_, _) {});

      await _avancarAteTiposPendentes(container);
      expect(container.read(patrimonioImportControllerProvider).step, ImportStep.resolverTipos);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PatrimonioImportPage()))),
        ),
      );
      await tester.pumpAndSettle();

      // expande o grupo "RACK PADRAO PISO" (2 patrimônios)
      await tester.tap(find.byKey(const ValueKey('grupo-tipo-pendente-RACK PADRAO PISO')));
      await tester.pumpAndSettle();

      // abre o dropdown "Aplicar aos semelhantes" e escolhe um tipo
      await tester.tap(find.byKey(const ValueKey('lote-tipo-pendente-RACK PADRAO PISO')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equipamento de Rede').last);
      await tester.pumpAndSettle();

      // diálogo de confirmação mostra a quantidade afetada antes de aplicar
      expect(find.text('Aplicar tipo em lote?'), findsOneWidget);
      expect(find.textContaining('aplicada a 2 patrimônios'), findsOneWidget);

      // CANCELAR: nenhuma linha deve mudar
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      var linhas = container.read(patrimonioImportControllerProvider).linhas;
      expect(linhas.every((l) => l.tipoIdResolvido == null), isTrue);

      // repete e agora CONFIRMA
      await tester.tap(find.byKey(const ValueKey('lote-tipo-pendente-RACK PADRAO PISO')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equipamento de Rede').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      linhas = container.read(patrimonioImportControllerProvider).linhas;
      final rackUm = linhas.firstWhere((l) => l.numeroPatrimonio == '00001');
      final rackDois = linhas.firstWhere((l) => l.numeroPatrimonio == '00002');
      final outra = linhas.firstWhere((l) => l.numeroPatrimonio == '00003');
      expect(rackUm.tipoIdResolvido, 'tipo-rede');
      expect(rackDois.tipoIdResolvido, 'tipo-rede');
      // grupo diferente nunca é afetado pela aplicação em lote de outro grupo.
      expect(outra.tipoIdResolvido, isNull);

      expect(repo.cadastrarCallCount, 0);
      expect(repo.atualizarCallCount, 0);
    },
  );
}
