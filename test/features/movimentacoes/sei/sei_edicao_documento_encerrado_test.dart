import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invtec/features/auth/data/auth_repository_supabase.dart';
import 'package:invtec/features/auth/domain/profile.dart';
import 'package:invtec/features/movimentacoes/domain/movimentacao.dart';
import 'package:invtec/features/movimentacoes/sei/data/documentos_sei_repository_supabase.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_documento_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendencia_status.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_item_pendente.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_pendencia_exceptions.dart';
import 'package:invtec/features/movimentacoes/sei/domain/sei_valor_corrigivel.dart';
import 'package:invtec/features/movimentacoes/sei/presentation/widgets/sei_pendencia_detalhe_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../auth/fake_auth_repository.dart';
import 'fake_documentos_sei_repository.dart';

/// `editar_documento_sei_pendente` deve recusar documento ENCERRADO (nenhum
/// item PENDENTE), além do bloqueio por item CONCLUÍDO.
///
/// A migration está PREPARADA, NÃO aplicada: nada aqui fala com o Supabase.
/// Os testes cobrem (1) o comportamento esperado no fake, que espelha a
/// função; (2) a UI; (3) a tradução do erro real no repositório, usando a
/// mensagem LIDA da migration; e (4) a estrutura do próprio SQL.
const _docId = 'doc-ficticio';
const _arquivoAntigo = 'supabase/migrations/20260921170000_add_documentos_sei.sql';
const _arquivoNovo = 'supabase/migrations/20260925120000_block_edit_documento_sei_encerrado.sql';

SeiItemPendente _item(int linha, [SeiItemPendenciaStatus status = SeiItemPendenciaStatus.pendente]) {
  return SeiItemPendente(
    id: 'item-$linha',
    documentoId: _docId,
    linha: linha,
    numeroPatrimonio: SeiValorCorrigivel(original: '90000000$linha'),
    origemTexto: const SeiValorCorrigivel(original: 'GETEC'),
    destinoTexto: const SeiValorCorrigivel(original: 'GEASI'),
    numeroChamado: const SeiValorCorrigivel(original: '9999'),
    equipamentoTexto: const SeiValorCorrigivel(original: 'Equipamento fictício'),
    status: status,
    motivoCancelamento: status == SeiItemPendenciaStatus.cancelado ? 'motivo' : null,
    criadoEm: DateTime(2026, 9, 22),
  );
}

SeiDocumentoPendente _documento(List<SeiItemPendente> itens) => SeiDocumentoPendente.fromItens(
  id: _docId,
  numeroDocumentoSei: '99999999',
  numeroDocumentoFormatado: '999999/2026/TESTE-PROMPT1137',
  assunto: 'Assunto original',
  tipoOperacaoPretendida: MovimentacaoTipo.transferencia,
  nomeArquivo: 'despacho.pdf',
  hashSha256: 'hash',
  versao: 1,
  criadoEm: DateTime(2026, 9, 22),
  criadoPorId: 'user-1',
  criadoPorNome: 'Fulano',
  itens: itens,
);

/// Edita com a versão ATUAL do documento (o cliente sempre relê antes), para
/// que só a regra de bloqueio — e não um conflito de versão — decida o resultado.
Future<SeiDocumentoPendente> _editar(FakeDocumentosSeiRepository repo) async {
  final versaoAtual = (await repo.obterPorId(_docId)).versao;
  return repo.editarDocumento(
    documentoId: _docId,
    versaoEsperada: versaoAtual,
    motivo: 'Correção',
    assunto: () => 'Assunto novo',
  );
}

/// Texto do arquivo com fim de linha normalizado.
String _ler(String caminho) => File(caminho).readAsStringSync().replaceAll('\r\n', '\n');

/// Corpo da função `editar_documento_sei_pendente` dentro de um arquivo SQL.
String _funcaoEditar(String sql) {
  final inicio = sql.indexOf('create or replace function public.editar_documento_sei_pendente(');
  expect(inicio, isNonNegative, reason: 'função não encontrada');
  final fim = sql.indexOf('\n\$\$;', inicio);
  return sql.substring(inicio, fim + '\n\$\$;'.length);
}

/// Bloco do guard novo — ancorado em SQL real (nunca em texto de
/// comentário, que pode mudar): do `if not exists` que checa ausência de
/// item PENDENTE até o `end if;` correspondente.
final _blocoGuard = RegExp(
  r"\n(  --[^\n]*\n)*  if not exists \(\s*select 1\s*from public\.documentos_sei_itens\s*where documento_id = p_documento_id\s*and status = 'PENDENTE'\s*\) then.*?using errcode = .42501.;\n  end if;\n",
  dotAll: true,
);

void main() {
  group('comportamento esperado (fake que espelha a função)', () {
    test('1. 2 PENDENTE: edição permitida', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1), _item(2)]),
        ],
      );
      expect((await _editar(repo)).assunto, 'Assunto novo');
    });

    test('2. 1 CANCELADO + 1 PENDENTE: edição permitida', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1, SeiItemPendenciaStatus.cancelado), _item(2)]),
        ],
      );
      expect((await _editar(repo)).assunto, 'Assunto novo');
    });

    test('3. 2 CANCELADO: edição bloqueada e nada muda', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1, SeiItemPendenciaStatus.cancelado), _item(2, SeiItemPendenciaStatus.cancelado)]),
        ],
      );
      await expectLater(_editar(repo), throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()));
      final depois = await repo.obterPorId(_docId);
      expect(depois.assunto, 'Assunto original');
      expect(depois.versao, 1);
      expect(await repo.listarEventos(_docId), isEmpty, reason: 'nenhum evento EDICAO gravado');
    });

    test('4. com CONCLUIDO: continua bloqueado pela regra existente (mesmo com pendente)', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1), _item(2)]),
        ],
      );
      repo.marcarItemConcluidoParaTeste('item-1', movimentacaoId: 'mov-1');
      await expectLater(_editar(repo), throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()));
    });

    test('todos CONCLUIDOS (0 pendentes): bloqueado', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1)]),
        ],
      );
      repo.marcarItemConcluidoParaTeste('item-1', movimentacaoId: 'mov-1');
      await expectLater(_editar(repo), throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()));
    });

    test('CONCLUIDO + CANCELADO (nenhum pendente): bloqueado', () async {
      final repo = FakeDocumentosSeiRepository(
        documentosIniciais: [
          _documento([_item(1), _item(2, SeiItemPendenciaStatus.cancelado)]),
        ],
      );
      repo.marcarItemConcluidoParaTeste('item-1', movimentacaoId: 'mov-1');
      await expectLater(_editar(repo), throwsA(isA<SeiDocumentoBloqueadoParaEdicaoException>()));
    });

    test('estados do modelo: encerrado x permiteEdicao', () {
      expect(_documento([_item(1), _item(2)]).permiteEdicao, isTrue);
      expect(_documento([_item(1, SeiItemPendenciaStatus.cancelado), _item(2)]).permiteEdicao, isTrue);
      final doisCancelados = _documento([
        _item(1, SeiItemPendenciaStatus.cancelado),
        _item(2, SeiItemPendenciaStatus.cancelado),
      ]);
      expect(doisCancelados.encerrado, isTrue);
      expect(doisCancelados.permiteEdicao, isFalse);
    });
  });

  group('5a. UI: documento encerrado não mostra "Editar documento"', () {
    Future<void> abrir(WidgetTester tester, SeiDocumentoPendente documento) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = FakeAuthRepository(
        initialUserId: 'user-1',
        profileResolver: (_) => Profile(
          id: 'user-1',
          nome: 'Usuária',
          email: 'u@example.com',
          perfil: ProfilePerfil.admin,
          ativo: true,
          criadoEm: DateTime.utc(2026, 1, 1),
          atualizadoEm: DateTime.utc(2026, 1, 1),
        ),
      );
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            documentosSeiRepositoryProvider.overrideWithValue(
              FakeDocumentosSeiRepository(documentosIniciais: [documento]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSeiPendenciaDetalheDialog(context, _docId),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('2 cancelados: sem botão Editar', (tester) async {
      await abrir(
        tester,
        _documento([_item(1, SeiItemPendenciaStatus.cancelado), _item(2, SeiItemPendenciaStatus.cancelado)]),
      );
      expect(find.text('Editar documento'), findsNothing);
    });

    testWidgets('com pendente: botão Editar presente', (tester) async {
      await abrir(tester, _documento([_item(1, SeiItemPendenciaStatus.cancelado), _item(2)]));
      expect(find.text('Editar documento'), findsOneWidget);
    });
  });

  group('5b. repositório traduz o erro real do banco', () {
    /// Mensagem EXATA do `raise exception` do guard, lida da migration
    /// preparada e formatada como o Postgres faria (`%` -> id do documento).
    String mensagemDoGuard() {
      final casamento = RegExp(
        r"raise exception '(Documento % está bloqueado para edição: encerrado \(nenhum item pendente\))'",
      ).firstMatch(_ler(_arquivoNovo));
      expect(casamento, isNotNull, reason: 'guard não encontrado na migration');
      return casamento!.group(1)!.replaceFirst('%', _docId);
    }

    test('42501 + mensagem do guard (documento encerrado) -> SeiDocumentoBloqueadoParaEdicaoException', () {
      final erro = PostgrestException(message: mensagemDoGuard(), code: '42501');
      final traduzido = traduzirBloqueioDeEdicaoSei(erro, _docId);
      expect(traduzido, isA<SeiDocumentoBloqueadoParaEdicaoException>());
      expect(traduzido!.documentoId, _docId);
    });

    test('a mensagem antiga (item concluído) continua traduzida igual', () {
      final erro = PostgrestException(
        message: 'Documento $_docId está bloqueado para edição: já tem item concluído',
        code: '42501',
      );
      expect(traduzirBloqueioDeEdicaoSei(erro, _docId), isA<SeiDocumentoBloqueadoParaEdicaoException>());
    });

    test('outros erros NÃO viram bloqueio (permissão, conflito de versão, item inválido)', () {
      const permissao = PostgrestException(
        message: 'Usuário sem permissão para editar documento SEI pendente',
        code: '42501',
      );
      const conflito = PostgrestException(message: 'Conflito de edição: versão 1 informada', code: 'P0010');
      const item = PostgrestException(message: 'Item x não está PENDENTE', code: 'P0001');
      expect(traduzirBloqueioDeEdicaoSei(permissao, _docId), isNull);
      expect(traduzirBloqueioDeEdicaoSei(conflito, _docId), isNull);
      expect(traduzirBloqueioDeEdicaoSei(item, _docId), isNull);
    });
  });

  group('migration preparada (só leitura do arquivo — nada é executado)', () {
    late String novo;
    late String antigo;
    late String funcaoNova;
    late String funcaoAntiga;

    setUpAll(() {
      novo = _ler(_arquivoNovo);
      antigo = _ler(_arquivoAntigo);
      funcaoNova = _funcaoEditar(novo);
      funcaoAntiga = _funcaoEditar(antigo);
    });

    /// SQL sem as linhas de comentário `--`.
    String semComentarios(String sql) => sql.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

    test('a migration antiga NÃO foi editada (não contém o guard)', () {
      expect(antigo, isNot(contains('encerrado (nenhum item pendente)')));
      expect(_blocoGuard.hasMatch(funcaoAntiga), isFalse);
    });

    test('define UMA única função: a mesma, com mesma assinatura, retorno, SECURITY DEFINER e search_path', () {
      final sql = semComentarios(novo);
      expect('create or replace function'.allMatches(sql).length, 1);
      expect(sql, contains('public.editar_documento_sei_pendente('));

      String cabecalho(String funcao) => funcao.substring(0, funcao.indexOf('as \$\$'));
      expect(cabecalho(funcaoNova), cabecalho(funcaoAntiga), reason: 'nome, parâmetros, retorno e atributos idênticos');
      expect(cabecalho(funcaoNova), contains('returns public.documentos_sei'));
      expect(cabecalho(funcaoNova), contains('security definer'));
      expect(cabecalho(funcaoNova), contains("set search_path = ''"));
    });

    test('o corpo (sem comentários) é IDÊNTICO ao antigo, exceto pelo bloco novo', () {
      expect(_blocoGuard.allMatches(funcaoNova).length, 1);
      expect(
        semComentarios(funcaoNova.replaceFirst(_blocoGuard, '')).trim(),
        semComentarios(funcaoAntiga).trim(),
      );
    });

    test('o guard usa a consulta e o errcode acordados', () {
      final guard = _blocoGuard.firstMatch(funcaoNova)!.group(0)!;
      expect(guard, contains('select 1'));
      expect(guard, contains('from public.documentos_sei_itens'));
      expect(guard, contains('documento_id = p_documento_id'));
      expect(guard, contains("status = 'PENDENTE'"));
      expect(guard, contains("using errcode = '42501'"));
    });

    test('ordem preservada: lock do documento -> versão -> concluídos -> GUARD -> validações -> locks de item', () {
      int posicao(String trecho) {
        final i = funcaoNova.indexOf(trecho);
        expect(i, isNonNegative, reason: 'não achei: $trecho');
        return i;
      }

      final lockDocumento = posicao('where id = p_documento_id\n  for update;');
      final versao = posicao('v_documento.versao <> p_versao_esperada');
      final concluidos = posicao('v_qtd_concluidos > 0');
      final guard = posicao("status = 'PENDENTE'\n  ) then");
      final validaPayload = posicao("jsonb_typeof(p_alteracoes) <> 'object'");
      final lockItem = posicao('from public.documentos_sei_itens where id = v_item_id for update');
      final escrita = posicao('update public.documentos_sei set');

      expect(lockDocumento, lessThan(versao));
      expect(versao, lessThan(concluidos));
      expect(concluidos, lessThan(guard), reason: 'o bloqueio por concluído continua com precedência');
      expect(guard, lessThan(validaPayload));
      expect(validaPayload, lessThan(lockItem));
      expect(lockItem, lessThan(escrita));
    });

    test('não mexe nas outras funções, em permissões nem em dados', () {
      final sql = semComentarios(novo).toLowerCase();
      for (final proibido in [
        'cancelar_pendentes_documento_sei',
        'cancelar_item_sei_pendente',
        'criar_documento_sei_pendente',
        'grant ',
        'revoke ',
        'drop ',
        'alter ',
        'create table',
        'create trigger',
        'delete from',
        'insert into public.documentos_sei ',
      ]) {
        expect(sql, isNot(contains(proibido)), reason: 'a migration não deve conter "$proibido"');
      }
    });
  });
}
