import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/dashboard/data/dashboard_repository_supabase.dart';
import 'package:invtec/features/localizacoes/data/localizacao_repository_supabase.dart';
import 'package:invtec/features/localizacoes/domain/localizacao.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/data/tipo_patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/importacao/data/spreadsheet_parser.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_field.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_column_mapping.dart';
import 'package:invtec/features/patrimonios/importacao/domain/import_defaults.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_controller.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/patrimonio_import_state.dart';
import 'package:invtec/features/patrimonios/importacao/presentation/widgets/import_locations_step.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../dashboard/fake_dashboard_repository.dart';
import '../../localizacoes/fake_localizacao_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';
import '../fake_tipo_patrimonio_repository.dart';

/// PROMPT 8.13.1, seção 2: o dropdown de localização precisa refletir o
/// ESTADO EFETIVO da decisão (mesmo quando ela veio de resolução automática
/// ou de uma regra conhecida, não só de uma escolha manual anterior) —
/// nunca mostrar "Deixar pendente" ao lado de um status "Localização
/// resolvida". Monta o estado diretamente (bypassa `carregarArquivo`, que
/// usa `compute()` e pode travar sob `testWidgets`) — ver
/// `import_tipos_pendentes_step_test.dart` para o mesmo raciocínio.
final _localizacoesReais = [
  Localizacao(
    id: 'loc-universitario',
    setorId: 'setor-getec',
    nome: 'GETEC - UNIVERSITÁRIO',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
  Localizacao(
    id: 'loc-situacao',
    setorId: 'setor-getec',
    nome: 'SITUAÇÃO/SITUADA - PA',
    ativo: true,
    criadoEm: DateTime(2026, 1, 1),
  ),
];

final _linhasPlanilha = <List<Object?>>[
  ['Patrimônio', 'Descricao', 'Localizacao', 'Marca', 'Serial'],
  ['1', 'Item 1', 'GETEC - UNIVERSITÁRIO', 'Dell', 'S1'],
  ['2', 'Item 2', 'SITUAÇÃO - PA', 'Dell', 'S2'],
  ['3', 'Item 3', 'INTANGÍVEIS', 'Dell', 'S3'],
  ['4', 'Item 4', 'TI - SOFTWARE', 'Dell', 'S4'],
  ['5', 'Item 5', 'BAIXAS LOCALIZADAS', 'Dell', 'S5'],
  ['6', 'Item 6', 'SALA MISTERIOSA X', 'Dell', 'S6'],
];

void main() {
  testWidgets(
    'dropdown de localização reflete o estado efetivo — nunca "Deixar pendente" para algo já '
    'resolvido automaticamente ou por regra conhecida',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          patrimonioRepositoryProvider.overrideWithValue(FakePatrimonioRepository()),
          tipoPatrimonioRepositoryProvider.overrideWithValue(FakeTipoPatrimonioRepository(tipos: const [])),
          setorRepositoryProvider.overrideWithValue(
            FakeSetorRepository(
              setores: [Setor(id: 'setor-getec', nome: 'GETEC', sigla: 'GETEC', ativo: true, criadoEm: DateTime(2026, 1, 1))],
            ),
          ),
          localizacaoRepositoryProvider.overrideWithValue(
            FakeLocalizacaoRepository(localizacoes: _localizacoesReais),
          ),
          dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepository()),
        ],
      );
      addTearDown(container.dispose);
      container.listen(patrimonioImportControllerProvider, (_, _) {});
      final controller = container.read(patrimonioImportControllerProvider.notifier);

      controller.state = PatrimonioImportState(
        abas: [ImportParsedSheet(nome: 'Sheet1', linhas: _linhasPlanilha)],
        abaSelecionadaIndice: 0,
        mapeamento: ImportColumnMapping.vazio.definindo(ImportColumnField.localizacao, 2),
        padroes: const ImportDefaults(destinoPadraoId: 'setor-getec'),
      );

      final state = container.read(patrimonioImportControllerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ImportLocationsStep(state: state)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "GETEC - UNIVERSITÁRIO": resolve sozinha (nome idêntico) — aparece
      // como rótulo da linha E como valor selecionado no dropdown.
      expect(find.text('GETEC - UNIVERSITÁRIO'), findsNWidgets(2));

      // "SITUAÇÃO - PA": resolve via apelido conhecido para o nome oficial
      // "SITUAÇÃO/SITUADA - PA" — o dropdown deve mostrar o nome OFICIAL
      // selecionado (nunca "Deixar pendente").
      expect(find.text('SITUAÇÃO/SITUADA - PA'), findsOneWidget);

      // INTANGÍVEIS / TI - SOFTWARE / BAIXAS LOCALIZADAS: regra conhecida
      // "sem localização" — as 3 devem mostrar "Importar sem localização"
      // selecionado no dropdown, nunca "Deixar pendente".
      expect(find.text('Importar sem localização'), findsNWidgets(3));

      // Só a linha genuinamente desconhecida ("SALA MISTERIOSA X") deve
      // mostrar "Deixar pendente" — exatamente 1 ocorrência no total.
      expect(find.text('Deixar pendente'), findsOneWidget);
    },
  );
}
