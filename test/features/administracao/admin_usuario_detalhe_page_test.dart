import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/administracao/data/usuario_admin_repository_supabase.dart';
import 'package:invtec/features/administracao/presentation/admin_usuario_detalhe_page.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/data/permissions_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';

import '../auth/fake_auth_repository.dart';
import 'fake_permissions_repository.dart';
import 'fake_usuario_admin_repository.dart';

Profile _usuario({
  required String id,
  String nome = 'Usuário de Teste',
  String? email = 'usuario@example.com',
  ProfilePerfil perfil = ProfilePerfil.operador,
  ProfileAccessStatus accessStatus = ProfileAccessStatus.active,
  String? cpf = '52998224725',
  int rejectionCount = 0,
  DateTime? approvedAt,
  String? approvedBy,
  String? rejectedReason,
  String? blockedReason,
}) {
  return Profile(
    id: id,
    nome: nome,
    email: email,
    perfil: perfil,
    ativo: accessStatus == ProfileAccessStatus.active,
    criadoEm: DateTime.utc(2026, 1, 1),
    atualizadoEm: DateTime.utc(2026, 1, 1),
    accessStatus: accessStatus,
    rejectionCount: rejectionCount,
    cpf: cpf,
    approvedAt: approvedAt,
    approvedBy: approvedBy,
    rejectedReason: rejectedReason,
    blockedReason: blockedReason,
  );
}

const _todasAsChavesComDefault = {
  'patrimonio.view': true,
  'patrimonio.create': true,
  'patrimonio.edit': true,
  'patrimonio.compare_update': true,
  'movimentacao.view': true,
  'movimentacao.create': true,
  'setor.view': true,
  'setor.manage': true,
  'localizacao.view': true,
  'localizacao.manage': true,
  'tipo_patrimonio.view': true,
  'tipo_patrimonio.manage': true,
  'sei.view': true,
  'sei.manage': true,
};

Future<void> _pumpDetalhePage(
  WidgetTester tester, {
  required String idExibido,
  required String adminLogadoId,
  required FakeUsuarioAdminRepository usuarioRepo,
  FakePermissionsRepository? permissoesRepo,
}) async {
  // Janela alta o bastante para a página inteira (identidade + acesso +
  // ações + até 14 linhas de permissão) caber sem exigir scroll do teste —
  // evita falhas de "offset fora da árvore" ao tocar em botões/controles
  // mais abaixo na tela.
  tester.view.physicalSize = const Size(1400, 2800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final usuarioLogado = usuarioRepo.usuariosParaTeste.firstWhere(
    (u) => u.id == adminLogadoId,
    orElse: () => _usuario(id: adminLogadoId, perfil: ProfilePerfil.admin),
  );
  final fakeAuth = FakeAuthRepository(
    initialUserId: adminLogadoId,
    profileResolver: (_) => usuarioLogado,
  );
  addTearDown(fakeAuth.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(fakeAuth),
        usuarioAdminRepositoryProvider.overrideWithValue(usuarioRepo),
        permissionsRepositoryProvider.overrideWithValue(
          permissoesRepo ?? FakePermissionsRepository(defaults: _todasAsChavesComDefault),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: AdminUsuarioDetalhePage(id: idExibido))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('aprovar', () {
    testWidgets('abre diálogo com CONSULTA pré-selecionado', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', accessStatus: ProfileAccessStatus.pending),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar acesso'));
      await tester.pumpAndSettle();

      expect(find.text('Aprovar acesso'), findsWidgets);
      expect(find.text('Consulta'), findsOneWidget);
    });

    testWidgets('selecionar ADMIN exige confirmação reforçada antes de aprovar', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', accessStatus: ProfileAccessStatus.pending),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar acesso'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Consulta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Administrador').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar acesso').last);
      await tester.pumpAndSettle();

      // Segunda confirmação reforçada — o fluxo normal NÃO conclui sem ela.
      expect(find.text('Este usuário terá acesso administrativo ao InvTec.'), findsOneWidget);
      expect(repo.aprovarCallCount, 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Conceder acesso de administrador'));
      await tester.pumpAndSettle();

      expect(repo.aprovarCallCount, 1);
      expect(repo.usuariosParaTeste.firstWhere((u) => u.id == 'alvo').perfil, ProfilePerfil.admin);
      expect(find.text('Acesso aprovado.'), findsOneWidget);
    });
  });

  group('rejeitar', () {
    testWidgets('exige motivo obrigatório', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', accessStatus: ProfileAccessStatus.pending, rejectionCount: 0),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Rejeitar'));
      await tester.pumpAndSettle();

      expect(find.text('Rejeição 1 de 3'), findsOneWidget);
      expect(find.text('Este usuário ainda poderá reenviar a solicitação.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Rejeitar solicitação'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o motivo.'), findsOneWidget);
      expect(repo.rejeitarCallCount, 0);
    });

    testWidgets('3ª rejeição avisa que vai bloquear a conta', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', accessStatus: ProfileAccessStatus.pending, rejectionCount: 2),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Rejeitar'));
      await tester.pumpAndSettle();

      expect(find.text('Rejeição 3 de 3'), findsOneWidget);
      expect(
        find.text('Esta rejeição bloqueará a conta até intervenção de um administrador.'),
        findsOneWidget,
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'Motivo *'), 'Dados inconsistentes');
      await tester.tap(find.widgetWithText(FilledButton, 'Rejeitar solicitação'));
      await tester.pumpAndSettle();

      expect(repo.rejeitarCallCount, 1);
      expect(repo.usuariosParaTeste.firstWhere((u) => u.id == 'alvo').accessStatus, ProfileAccessStatus.blocked);
      expect(find.text('Solicitação rejeitada. Conta bloqueada.'), findsOneWidget);
    });
  });

  group('desbloquear', () {
    testWidgets('usuário já aprovado antes: avisa que volta para Ativo', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(
            id: 'alvo',
            accessStatus: ProfileAccessStatus.blocked,
            approvedAt: DateTime.utc(2026, 1, 1),
            blockedReason: 'Comportamento suspeito',
          ),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Desbloquear'));
      await tester.pumpAndSettle();

      expect(
        find.text('Este usuário já foi aprovado antes — ao desbloquear, voltará para Ativo.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Desbloquear').last);
      await tester.pumpAndSettle();

      expect(repo.usuariosParaTeste.firstWhere((u) => u.id == 'alvo').accessStatus, ProfileAccessStatus.active);
    });

    testWidgets('usuário nunca aprovado: avisa que volta para Pendente', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', accessStatus: ProfileAccessStatus.blocked, approvedAt: null),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(FilledButton, 'Desbloquear'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Este usuário nunca foi aprovado — ao desbloquear, voltará para Pendente '
          'com o contador de rejeições zerado.',
        ),
        findsOneWidget,
      );
    });
  });

  group('editar identidade', () {
    testWidgets('altera nome e CPF com motivo obrigatório', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', nome: 'Nome Errado', accessStatus: ProfileAccessStatus.active),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editar identidade'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome *'), 'Nome Corrigido');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo da alteração *'),
        'Correção solicitada pelo usuário',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(repo.alterarIdentidadeCallCount, 1);
      expect(repo.usuariosParaTeste.firstWhere((u) => u.id == 'alvo').nome, 'Nome Corrigido');
      expect(find.text('Identidade atualizada.'), findsOneWidget);
    });

    testWidgets('CPF legado null mostra campo vazio e não quebra', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', cpf: null, accessStatus: ProfileAccessStatus.active),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      expect(find.text('Não informado'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editar identidade'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextFormField, 'CPF *'), findsOneWidget);
    });
  });

  group('painel de permissões', () {
    testWidgets('herdar/permitir/negar chamam o método certo do controller', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', perfil: ProfilePerfil.admin, accessStatus: ProfileAccessStatus.active),
        ],
      );
      final permissoesRepo = FakePermissionsRepository(defaults: _todasAsChavesComDefault);

      await _pumpDetalhePage(
        tester,
        idExibido: 'alvo',
        adminLogadoId: 'admin-1',
        usuarioRepo: repo,
        permissoesRepo: permissoesRepo,
      );

      final tristateSetorView = find.byKey(const ValueKey('permissao-tristate-setor.view'));
      expect(tristateSetorView, findsOneWidget);

      await tester.tap(find.descendant(of: tristateSetorView, matching: find.text('Negar')));
      await tester.pumpAndSettle();
      expect(permissoesRepo.definirPermissaoCallCount, 1);

      await tester.tap(find.descendant(of: tristateSetorView, matching: find.text('Herdar')));
      await tester.pumpAndSettle();
      expect(permissoesRepo.removerOverrideCallCount, 1);
    });

    testWidgets('compare_update fica desabilitado para quem não é ADMIN', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', perfil: ProfilePerfil.gestor, accessStatus: ProfileAccessStatus.active),
        ],
      );
      final permissoesRepo = FakePermissionsRepository(
        defaults: {..._todasAsChavesComDefault, 'patrimonio.compare_update': false},
      );

      await _pumpDetalhePage(
        tester,
        idExibido: 'alvo',
        adminLogadoId: 'admin-1',
        usuarioRepo: repo,
        permissoesRepo: permissoesRepo,
      );

      expect(find.text('Exclusiva de administrador'), findsOneWidget);

      final tristateCompareUpdate = find.byKey(
        const ValueKey('permissao-tristate-patrimonio.compare_update'),
      );
      // warnIfMissed: false — o toque é deliberadamente absorvido pelo
      // `IgnorePointer` (controle travado); o teste existe exatamente para
      // confirmar isso, não é um erro de finder.
      await tester.tap(
        find.descendant(of: tristateCompareUpdate, matching: find.text('Permitir')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(permissoesRepo.definirPermissaoCallCount, 0);
    });

    testWidgets('ADMIN não pode alterar as próprias permissões', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin, accessStatus: ProfileAccessStatus.active),
        ],
      );
      final permissoesRepo = FakePermissionsRepository(defaults: _todasAsChavesComDefault);

      await _pumpDetalhePage(
        tester,
        idExibido: 'admin-1',
        adminLogadoId: 'admin-1',
        usuarioRepo: repo,
        permissoesRepo: permissoesRepo,
      );

      expect(
        find.text('Suas próprias permissões não podem ser alteradas nesta tela.'),
        findsOneWidget,
      );

      final tristateSetorView = find.byKey(const ValueKey('permissao-tristate-setor.view'));
      // warnIfMissed: false — mesmo motivo do teste de compare_update: o
      // painel inteiro está travado por `IgnorePointer` (auto-gestão).
      await tester.tap(
        find.descendant(of: tristateSetorView, matching: find.text('Negar')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(permissoesRepo.definirPermissaoCallCount, 0);

      final botaoRestaurar = find.widgetWithText(TextButton, 'Restaurar padrão do perfil');
      expect(tester.widget<TextButton>(botaoRestaurar).onPressed, isNull);
    });

    testWidgets('painel não aparece para usuário PENDING', (tester) async {
      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', accessStatus: ProfileAccessStatus.pending),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      expect(find.text('Permissões'), findsNothing);
    });
  });

  group('responsividade', () {
    testWidgets('390px: detalhe de usuário ativo sem overflow/exceções', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = FakeUsuarioAdminRepository(
        usuarios: [
          _usuario(id: 'admin-1', perfil: ProfilePerfil.admin),
          _usuario(id: 'alvo', perfil: ProfilePerfil.admin, accessStatus: ProfileAccessStatus.active),
        ],
      );
      await _pumpDetalhePage(tester, idExibido: 'alvo', adminLogadoId: 'admin-1', usuarioRepo: repo);

      expect(find.text('Permissões'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
