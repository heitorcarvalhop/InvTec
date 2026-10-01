import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Testes ESTRUTURAIS da migration (NÃO aplicada) da execução segura de
/// comparação patrimonial:
///
///  * `20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql`.
///
/// Não há Postgres neste ambiente: os testes leem o TEXTO do arquivo. Cada
/// cenário vira uma asserção sobre a presença/ausência/ORDEM de um trecho de
/// SQL — o que o SQL faz de fato quando roda só pode ser provado em
/// homologação com um Postgres real. Mesmo formato de
/// `sei_conclusao_lote_migration_test.dart`.
const _arquivo = 'supabase/migrations/20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql';

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

  group('seção 4 — número patrimonial nunca é um parâmetro/campo aplicável', () {
    test('p_numero_patrimonio não existe em nenhum lugar do arquivo', () {
      expect(norm, isNot(contains('p_numero_patrimonio')));
    });

    test('v_numero_patrimonio não existe (nenhuma variável derivada dele)', () {
      expect(norm, isNot(contains('v_numero_patrimonio')));
    });

    test('a função não faz UPDATE de numero_patrimonio', () {
      expect(norm, isNot(contains('set numero_patrimonio')));
      expect(norm, isNot(contains('numero_patrimonio = coalesce')));
    });
  });

  group('seção 2D — proteção transacional contra execução dupla (advisory lock)', () {
    test('usa pg_advisory_xact_lock sobre o operacao_id', () {
      expect(norm, contains('pg_advisory_xact_lock(hashtextextended(\'comparacao_patrimonio:\' || p_operacao_id::text, 0))'));
    });

    test('a trava vem ANTES da checagem de idempotência (SELECT por operacao_id) e do INSERT final', () {
      _emOrdem(norm, [
        'perform pg_advisory_xact_lock',
        'select e.lote_id, e.patrimonio_id, e.versao_esperada, e.campos_solicitados, e.justificativa, e.criado_por, e.resultado',
        'insert into public.patrimonio_comparacao_execucoes',
      ]);
    });
  });

  group('seção 2C — identidade de um retry inclui justificativa', () {
    test('a comparação de identidade confere justificativa (is distinct from)', () {
      expect(norm, contains('v_existente.justificativa is distinct from v_justificativa'));
    });

    test('a comparação de identidade continua conferindo lote_id, patrimonio_id, versao_esperada, campos e criado_por', () {
      expect(norm, contains('v_existente.lote_id <> p_lote_id'));
      expect(norm, contains('v_existente.patrimonio_id <> p_patrimonio_id'));
      expect(norm, contains('v_existente.versao_esperada <> p_versao_esperada'));
      expect(norm, contains('v_existente.campos_solicitados <> v_campos'));
      expect(norm, contains('v_existente.criado_por <> auth.uid()'));
    });

    test('um retry idêntico devolve o resultado gravado com ja_executado true, sem nova escrita antes do retorno', () {
      final iRetorno = _idx(norm, "return v_existente.resultado || jsonb_build_object('ja_executado', true);");
      final iInsertFinal = _idx(norm, 'insert into public.patrimonio_comparacao_execucoes', desde: iRetorno);
      // o ÚNICO insert nesta tabela deve vir DEPOIS do retorno antecipado do
      // retry idêntico — nunca duas inserções possíveis no mesmo caminho.
      expect(norm.indexOf('insert into public.patrimonio_comparacao_execucoes'), iInsertFinal);
    });
  });

  group('seção 1 — autorização e visibilidade', () {
    test('a RPC exige ADMIN (private.has_perfil) antes de qualquer outra coisa', () {
      final iCheck = _idx(norm, "if private.has_perfil('ADMIN') is not true then");
      final iLock = _idx(norm, 'perform pg_advisory_xact_lock', desde: iCheck);
      expect(iCheck, lessThan(iLock));
    });

    test('security definer e search_path vazio', () {
      expect(norm, contains('security definer'));
      expect(norm, contains("set search_path = ''"));
    });

    test('GRANT/REVOKE da função: só authenticated executa', () {
      expect(
        norm,
        contains('revoke all on function public.aplicar_decisao_comparacao_patrimonio from public, anon, authenticated;'),
      );
      expect(norm, contains('grant execute on function public.aplicar_decisao_comparacao_patrimonio to authenticated;'));
    });

    test('RLS da tabela de controle: só ADMIN lê, nenhuma escrita concedida a authenticated', () {
      expect(norm, contains('alter table public.patrimonio_comparacao_execucoes enable row level security;'));
      expect(norm, contains("using ((select private.has_perfil('ADMIN')));"));
      expect(norm, contains('revoke all on table public.patrimonio_comparacao_execucoes from public, anon, authenticated;'));
      expect(norm, contains('grant select on table public.patrimonio_comparacao_execucoes to authenticated;'));
      // nenhum GRANT de insert/update/delete para authenticated — só SELECT.
      expect(norm, isNot(contains('grant insert on table public.patrimonio_comparacao_execucoes')));
      expect(norm, isNot(contains('grant update on table public.patrimonio_comparacao_execucoes')));
      expect(norm, isNot(contains('grant delete on table public.patrimonio_comparacao_execucoes')));
    });
  });

  group('seção 5 — revalidação/conflitos', () {
    test('P0040 (conflito de versão) compara atualizado_em com a versão esperada, ANTES de qualquer escrita', () {
      final iVersao = _idx(norm, "using errcode = 'P0040'");
      final iUpdateMetadado = _idx(norm, 'update public.patrimonios set numero_serie', desde: 0);
      expect(iVersao, lessThan(iUpdateMetadado));
      expect(norm, contains('v_patrimonio.atualizado_em is distinct from p_versao_esperada'));
    });

    test('P0042 (pendência SEI) só é checado quando a decisão muda setor/localização', () {
      final iCheckMovimentacao = _idx(norm, 'if v_tem_movimentacao then');
      final iPendenciaSei = _idx(norm, "using errcode = 'P0042'", desde: iCheckMovimentacao);
      expect(iPendenciaSei, greaterThan(iCheckMovimentacao));
      expect(norm, contains("from public.documentos_sei_itens i"));
      expect(norm, contains("i.status = 'PENDENTE'"));
    });

    test('P0043 (nenhum campo informado) continua presente', () {
      expect(norm, contains("using errcode = 'P0043'"));
    });
  });

  group('seção 2/3 — reaproveitamento de registrar_movimentacao (atomicidade)', () {
    test('chama registrar_movimentacao com AJUSTE_INVENTARIO, nunca duplica suas regras', () {
      expect(norm, contains("p_tipo := 'AJUSTE_INVENTARIO'"));
      expect(norm, contains('public.registrar_movimentacao('));
    });

    test('nunca faz UPDATE direto de setor_atual_id/localizacao_atual_id', () {
      expect(norm, isNot(contains('set setor_atual_id')));
      expect(norm, isNot(contains('set localizacao_atual_id')));
    });

    test('esta migration NUNCA toca (DROP/CREATE OR REPLACE) registrar_movimentacao nem nenhuma RPC SEI', () {
      expect(norm, isNot(contains('create or replace function public.registrar_movimentacao')));
      expect(norm, isNot(contains('create function public.registrar_movimentacao')));
      expect(norm, isNot(contains('drop function public.registrar_movimentacao')));
      expect(norm, isNot(contains('concluir_item_documento_sei')));
      expect(norm, isNot(contains('concluir_itens_documento_sei_lote')));
      expect(norm, isNot(contains('documentos_sei_lotes_conclusao')));
    });

    test('nenhum bloco de exceção (EXCEPTION WHEN) envolve as escritas — uma falha desfaz a função inteira', () {
      expect(norm, isNot(contains('exception when')));
    });
  });

  test('a função é criada sem CREATE OR REPLACE (nunca aplicada, sempre CREATE simples nesta etapa)', () {
    expect(bruto, contains('create function public.aplicar_decisao_comparacao_patrimonio('));
    expect(bruto, isNot(contains('create or replace function public.aplicar_decisao_comparacao_patrimonio')));
  });
}
