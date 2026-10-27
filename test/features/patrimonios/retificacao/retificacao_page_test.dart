import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/patrimonios/data/patrimonio_repository_supabase.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio.dart';
import 'package:invtec/features/patrimonios/domain/patrimonio_detalhe.dart';
import 'package:invtec/features/patrimonios/retificacao/presentation/retificacao_controller.dart';
import 'package:invtec/features/patrimonios/retificacao/presentation/retificacao_page.dart';
import 'package:invtec/features/setores/data/setor_repository_supabase.dart';
import 'package:invtec/features/setores/domain/setor.dart';

import '../../auth/fake_auth_repository.dart';
import '../../auth/fake_permissions_repository.dart';
import '../../setores/fake_setor_repository.dart';
import '../fake_patrimonio_repository.dart';

Profile _perfil(ProfilePerfil perfil) => Profile(
  id: 'user-1',
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

PatrimonioDetalhe _patrimonio({required String id, required String numero}) {
  return PatrimonioDetalhe(
    patrimonio: Patrimonio(
      id: id,
      numeroPatrimonio: numero,
      tipoId: 'tipo-1',
      status: PatrimonioStatus.emUso,
      setorAtualId: _getec.id,
      dataCadastro: DateTime(2026, 1, 1),
      atualizadoEm: DateTime(2026, 1, 1),
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

List<int> _csvUmItem() => utf8.encode('$_cabecalho\np1;1;1;Descrição;GETEC;CIMEHGO;CIMEHGO;;;;;;;;;;\n');

Future<RetificacaoController> _pumpPagina(
  WidgetTester tester, {
  ProfilePerfil perfil = ProfilePerfil.admin,
  Set<String>? permissoesExtras,
  bool retificacaoExecucaoHabilitada = true,
}) async {
  final auth = FakeAuthRepository(initialUserId: 'user-1', profileResolver: (_) => _perfil(perfil));
  addTearDown(auth.dispose);
  final permissoes = permissoesExtras == null
      ? FakePermissionsRepository.paraPerfil(perfil)
      : FakePermissionsRepository(chaves: permissoesExtras);
  final repo = FakePatrimonioRepository(itens: [_patrimonio(id: 'p1', numero: '1')]);

  late RetificacaoController controller;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        permissionsRepositoryProvider.overrideWithValue(permissoes),
        patrimonioRepositoryProvider.overrideWithValue(repo),
        setorRepositoryProvider.overrideWithValue(FakeSetorRepository(setores: [_getec, _cimehgo])),
        retificacaoControllerProvider.overrideWith(() {
          controller = RetificacaoController(retificacaoExecucaoHabilitada: () => retificacaoExecucaoHabilitada);
          return controller;
        }),
      ],
      child: const MaterialApp(home: RetificacaoPage()),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('fase inicial: mostra o botão de selecionar CSV', (tester) async {
    await _pumpPagina(tester);

    expect(find.byKey(const Key('retificacao-selecionar-arquivo')), findsOneWidget);
    expect(find.text('Retificação cadastral de unidade'), findsOneWidget);
  });

  testWidgets('depois de carregar o CSV: mostra o resumo e a lista de itens', (tester) async {
    final controller = await _pumpPagina(tester);

    await controller.carregarCsv(_csvUmItem());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retificacao-resumo-prontos')), findsOneWidget);
    expect(find.text('Prontos para retificar: 1'), findsOneWidget);
    expect(find.byKey(const Key('retificacao-item-2')), findsOneWidget);
    expect(find.byKey(const Key('retificacao-justificativa')), findsOneWidget);
  });

  testWidgets(
    'sem permissão patrimonio.rectify_unit: nenhum botão de confirmação, aviso explícito',
    (tester) async {
      final controller = await _pumpPagina(
        tester,
        perfil: ProfilePerfil.admin,
        permissoesExtras: {'patrimonio.view'},
      );
      await controller.carregarCsv(_csvUmItem());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retificacao-confirmar')), findsNothing);
      expect(
        find.textContaining('Sua sessão não tem perfil ADMIN/GESTOR ou a permissão'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'com permissão mas trava operacional desabilitada: aviso explícito, nenhum botão de confirmação',
    (tester) async {
      final controller = await _pumpPagina(tester, retificacaoExecucaoHabilitada: false);
      await controller.carregarCsv(_csvUmItem());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retificacao-confirmar')), findsNothing);
      expect(
        find.textContaining('A execução real desta campanha ainda está desabilitada'),
        findsOneWidget,
      );
    },
  );

  testWidgets('campo de justificativa aceita texto e atualiza o estado do controller', (tester) async {
    final controller = await _pumpPagina(tester);
    await controller.carregarCsv(_csvUmItem());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('retificacao-justificativa')), 'Plano SEMAD');
    await tester.pumpAndSettle();

    expect(controller.state.justificativa, 'Plano SEMAD');
  });

  // O botão "retificacao-confirmar" só é renderizado quando
  // `EnvConfig.retificacaoExecucaoHabilitada` (lido DIRETO da classe
  // estática, nunca do `retificacaoExecucaoHabilitada` injetável do
  // controller — mesmo padrão já estabelecido por
  // `import_comparacao_resumo_step.dart`/`EnvConfig.
  // comparacaoExecucaoHabilitada`) é `true`. Em ambiente de teste
  // (sem dotenv/dart-define configurados) ela é sempre `false` — por
  // isso o fluxo "confirmar → executar → ver conclusão" através da UI
  // não é testável neste nível; está inteiramente coberto em
  // `retificacao_controller_test.dart` (que injeta a trava
  // diretamente no controller).
  testWidgets(
    'sem a trava de ambiente habilitada (padrão em teste): nenhum botão de confirmação, mesmo com '
    'tudo o resto em ordem',
    (tester) async {
      final controller = await _pumpPagina(tester);
      await controller.carregarCsv(_csvUmItem());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('retificacao-justificativa')), 'Plano SEMAD');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retificacao-confirmar')), findsNothing);
      expect(
        find.textContaining('A execução real desta campanha ainda está desabilitada'),
        findsOneWidget,
      );
    },
  );
}
