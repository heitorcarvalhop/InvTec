import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Testes ESTRUTURAIS da migration (NÃO aplicada) que corrige
/// `private.handle_new_user` para rejeitar, já no signup, um CPF informado
/// com checksum inválido:
///
///  * `20261008120000_reject_invalid_cpf_on_signup.sql`.
///
/// Não há Postgres neste ambiente: os testes leem o TEXTO do arquivo. Cada
/// cenário vira uma asserção sobre a presença/ausência/ORDEM de um trecho de
/// SQL — o que o SQL faz de fato quando roda só pode ser provado em
/// homologação com um Postgres real. Mesmo formato de
/// `aplicar_decisao_comparacao_patrimonio_migration_test.dart`.
const _arquivo = 'supabase/migrations/20261008120000_reject_invalid_cpf_on_signup.sql';

String _ler(String caminho) => File(caminho).readAsStringSync().replaceAll('\r\n', '\n');

String _semComentarios(String sql) => sql.replaceAll(RegExp(r'--[^\n]*'), '');

/// SQL sem comentários e com o espaço em branco colapsado — comparação
/// semântica (ignora indentação, quebras de linha, CRLF/LF e comentários).
String _norm(String sql) => _semComentarios(sql).replaceAll(RegExp(r'\s+'), ' ').trim();

int _idx(String texto, String trecho, {int desde = 0}) {
  final i = texto.indexOf(trecho, desde);
  expect(i, greaterThanOrEqualTo(0), reason: 'trecho não encontrado (a partir de $desde): $trecho');
  return i;
}

/// Confere que [trechos] aparecem em [texto] nesta ORDEM (cada um depois do
/// anterior).
void _emOrdem(String texto, List<String> trechos) {
  var desde = 0;
  for (final t in trechos) {
    desde = _idx(texto, t, desde: desde) + t.length;
  }
}

void main() {
  late String bruto;
  late String norm;

  setUpAll(() {
    bruto = _ler(_arquivo);
    norm = _norm(bruto);
  });

  group('migration é ADITIVA e vem depois das migrations referenciadas', () {
    test('redefine handle_new_user via CREATE OR REPLACE (não edita a migration anterior)', () {
      expect(norm, contains('create or replace function private.handle_new_user()'));
    });

    test('security definer e search_path vazio preservados', () {
      expect(norm, contains('security definer'));
      expect(norm, contains("set search_path = ''"));
    });
  });

  group('regra B — CPF informado e inválido: aborta ANTES do INSERT', () {
    test('a função chama private.is_valid_cpf antes de inserir o profile', () {
      final iCheck = _idx(norm, 'private.is_valid_cpf(v_cpf)');
      final iInsert = _idx(norm, 'insert into public.profiles', desde: 0);
      expect(iCheck, lessThan(iInsert));
    });

    test('existe um raise exception condicionado a is_valid_cpf ser falso, ANTES do insert', () {
      _emOrdem(norm, [
        'if v_cpf is not null and private.is_valid_cpf(v_cpf) is not true then',
        "raise exception 'CPF inválido.' using errcode = 'P0001';",
        'end if;',
        'insert into public.profiles',
      ]);
    });

    test('usa o errcode P0001 (padrão do projeto), não um errcode genérico do Postgres', () {
      expect(norm, contains("using errcode = 'P0001'"));
    });

    test('quando válido, o fluxo normal (insert + notify) continua presente', () {
      _emOrdem(norm, [
        'insert into public.profiles (id, nome, email, cpf, perfil, ativo, access_status, rejection_count)',
        'perform private.notify_admins_access_request(',
      ]);
    });
  });

  group('regra A — CPF ausente/NULL/vazio: pula a checagem e insere com cpf NULL', () {
    test('normaliza o CPF para só dígitos com a mesma expressão de normalize_profile_cpf', () {
      expect(
        norm,
        contains(
          "nullif(regexp_replace(coalesce(new.raw_user_meta_data ->> 'cpf', ''), '[^0-9]', '', 'g'), '')",
        ),
      );
    });

    test('a condição do if inclui explicitamente "v_cpf is not null" antes de chamar is_valid_cpf', () {
      expect(norm, contains('if v_cpf is not null and private.is_valid_cpf(v_cpf) is not true then'));
    });

    test('o INSERT usa a variável normalizada (v_cpf), não o valor bruto de raw_user_meta_data', () {
      expect(
        norm,
        contains('insert into public.profiles (id, nome, email, cpf, perfil, ativo, access_status, rejection_count) values ( new.id, v_nome, new.email, v_cpf,'),
      );
    });
  });

  group('regra C — CPF duplicado: nenhuma checagem nova, só a constraint já existente', () {
    test('não adiciona nenhum segundo SELECT de verificação de CPF existente em profiles', () {
      expect(norm, isNot(contains('select 1 from public.profiles where cpf')));
      expect(norm, isNot(contains('select id from public.profiles where cpf')));
      expect(norm, isNot(contains('exists (select')));
    });

    test('não cria nenhuma função/endpoint cpf_existe nesta migration', () {
      expect(norm, isNot(contains('cpf_existe')));
    });

    test('nenhuma função cpf_existe é CRIADA em lugar nenhum do projeto (fora de comentários explicativos)', () {
      final dir = Directory('supabase/migrations');
      final arquivosComFuncaoCpfExiste = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .where((f) {
            final semComentarios = _norm(f.readAsStringSync());
            return semComentarios.contains('function public.cpf_existe') ||
                semComentarios.contains('function private.cpf_existe');
          });
      expect(arquivosComFuncaoCpfExiste, isEmpty);
    });

    test('a duplicidade continua dependendo só de profiles_cpf_key (migration 20261005120000)', () {
      final constraintSql = _norm(
        _ler('supabase/migrations/20261005120000_add_profile_access_control.sql'),
      );
      expect(
        constraintSql,
        contains('create unique index profiles_cpf_key on public.profiles (cpf) where cpf is not null;'),
      );
    });
  });

  group('cpf continua NULLABLE — nenhuma migration adiciona NOT NULL à coluna', () {
    test('esta migration não adiciona NOT NULL a profiles.cpf', () {
      expect(norm, isNot(contains('alter column cpf set not null')));
      expect(norm, isNot(contains('add column cpf text not null')));
    });

    test('nenhuma migration do projeto adiciona NOT NULL a profiles.cpf', () {
      final dir = Directory('supabase/migrations');
      final violacoes = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .where((f) {
            final conteudo = _norm(f.readAsStringSync());
            return conteudo.contains('alter column cpf set not null') ||
                conteudo.contains('add column cpf text not null');
          });
      expect(violacoes, isEmpty);
    });
  });

  test('não altera aprovação/rejeição/bloqueio/permissões/notifications/realtime', () {
    expect(bruto, isNot(contains('create or replace function public.aprovar_usuario')));
    expect(bruto, isNot(contains('create or replace function public.rejeitar_usuario')));
    expect(bruto, isNot(contains('create or replace function public.bloquear_usuario')));
    expect(bruto, isNot(contains('create or replace function private.has_perfil')));
    expect(bruto, isNot(contains('create table public.notifications')));
    expect(bruto, isNot(contains('alter publication supabase_realtime')));
  });
}
