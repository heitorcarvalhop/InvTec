import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PROMPT 11.5.2 — testes ESTRUTURAIS da migration (NÃO aplicada) da
/// conclusão em LOTE de itens SEI:
///
///  * `20260928100000_add_concluir_itens_documento_sei_lote.sql` — a tabela
///    `documentos_sei_lotes_conclusao` e a RPC atômica
///    `concluir_itens_documento_sei_lote`.
///
/// Não há Postgres neste ambiente (nem local nem remoto foi tocado): os
/// testes leem o TEXTO do arquivo. Cada cenário pedido no prompt vira uma
/// asserção sobre o guard, o código de erro, a ORDEM dos passos ou a
/// ausência de escrita — o que o SQL faz de fato quando roda só pode ser
/// provado em homologação (mesmo formato do PROMPT 11.4.4), fora deste
/// prompt.
const _dir = 'supabase/migrations/';
const _lote = '${_dir}20260928100000_add_concluir_itens_documento_sei_lote.sql';
const _individual = '${_dir}20260925140000_add_concluir_item_documento_sei.sql';
const _sei = '${_dir}20260921170000_add_documentos_sei.sql';
const _localizacoes = '${_dir}20260914140000_add_localizacoes.sql';

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
/// anterior) e devolve as posições.
List<int> _emOrdem(String texto, List<String> trechos) {
  final posicoes = <int>[];
  var desde = 0;
  for (final t in trechos) {
    final i = _idx(texto, t, desde: desde);
    posicoes.add(i);
    desde = i + t.length;
  }
  return posicoes;
}

void main() {
  late String bruto;
  late String norm;
  late String individualBruto;

  setUpAll(() {
    bruto = _ler(_lote);
    norm = _norm(bruto);
    individualBruto = _ler(_individual);
  });

  group('a função individual não foi tocada', () {
    test('20260925140000 não foi modificada por esta migration (nenhum arquivo antigo foi alterado)', () {
      // Esta própria checagem só prova que o ARQUIVO da migration antiga
      // segue no repositório com o conteúdo que já era esperado por
      // `sei_conclusao_entrega_migrations_test.dart` — a garantia real é
      // não existir, no arquivo novo, nenhum DROP/CREATE OR REPLACE dela.
      expect(individualBruto, contains('create or replace function public.concluir_item_documento_sei('));
    });

    test(
      '20260928100000 nunca faz DROP nem CREATE (OR REPLACE) de concluir_item_documento_sei nem de registrar_movimentacao',
      () {
        expect(norm, isNot(contains('drop function')));
        expect(norm, isNot(contains('create or replace function public.concluir_item_documento_sei')));
        expect(norm, isNot(contains('create function public.concluir_item_documento_sei')));
        expect(norm, isNot(contains('create or replace function public.registrar_movimentacao')));
        expect(norm, isNot(contains('create function public.registrar_movimentacao')));
        expect(norm, isNot(contains('grant execute on function public.concluir_item_documento_sei')));
        expect(norm, isNot(contains('revoke all on function public.concluir_item_documento_sei')));
      },
    );

    test('a única função criada/alterada por esta migration é a de lote', () {
      expect(RegExp('create (or replace )?function ').allMatches(norm).length, 1);
      expect(norm, contains('create or replace function public.concluir_itens_documento_sei_lote('));
    });
  });

  group('tabela de controle: documentos_sei_lotes_conclusao', () {
    test('colunas mínimas: lote_id, documento_id, item_ids, parâmetros originais, usuário, data, resultado', () {
      final bloco = RegExp(
        r'create table public\.documentos_sei_lotes_conclusao \(\n([\s\S]*?)\n\);',
      ).firstMatch(bruto)!.group(1)!;
      for (final coluna in [
        'lote_id uuid primary key',
        'documento_id uuid not null references public.documentos_sei (id) on delete restrict',
        'item_ids uuid[] not null',
        'versao_esperada integer not null',
        'observacao text',
        'confirmar_limpeza_destino boolean not null',
        'criado_por uuid not null references public.profiles (id) on delete restrict',
        'criado_em timestamptz not null default now()',
        'resultado jsonb not null',
      ]) {
        expect(bloco, contains(coluna), reason: coluna);
      }
    });

    test('nunca fica vazia (CHECK cardinality > 0)', () {
      expect(
        norm,
        contains('constraint documentos_sei_lotes_conclusao_item_ids_nao_vazio check (cardinality(item_ids) > 0)'),
      );
    });

    test('RLS ligada, com policy de SELECT só (mesmo público de leitura das outras tabelas SEI)', () {
      expect(norm, contains('alter table public.documentos_sei_lotes_conclusao enable row level security;'));
      expect(
        norm,
        contains(
          'create policy documentos_sei_lotes_conclusao_select on public.documentos_sei_lotes_conclusao '
          'for select to authenticated using ((select private.has_perfil(\'ADMIN\', \'GESTOR\', \'OPERADOR\', \'CONSULTA\')));',
        ),
      );
      // só a UMA policy de SELECT verificada acima existe (nenhuma outra
      // policy de INSERT/UPDATE/DELETE foi criada para esta tabela).
      expect(RegExp('create policy').allMatches(norm).length, 1);
    });

    test('GRANT: authenticated só recebe SELECT — nunca INSERT/UPDATE/DELETE direto na tabela', () {
      expect(
        norm,
        contains('revoke all on table public.documentos_sei_lotes_conclusao from public, anon, authenticated;'),
      );
      expect(norm, contains('grant select on public.documentos_sei_lotes_conclusao to authenticated;'));
      expect(norm, isNot(contains('grant insert on public.documentos_sei_lotes_conclusao')));
      expect(norm, isNot(contains('grant update on public.documentos_sei_lotes_conclusao')));
      expect(norm, isNot(contains('grant delete on public.documentos_sei_lotes_conclusao')));
      expect(norm, isNot(contains('grant all on public.documentos_sei_lotes_conclusao')));
    });
  });

  group('assinatura e permissões da RPC de lote', () {
    test('assinatura: 6 parâmetros, retorna jsonb, SECURITY DEFINER, search_path vazio', () {
      expect(
        norm,
        contains(
          'create or replace function public.concluir_itens_documento_sei_lote( p_documento_id uuid, '
          'p_item_ids uuid[], p_versao_esperada integer, p_lote_id uuid, p_observacao text default null, '
          'p_confirmar_limpeza_destino boolean default false ) returns jsonb language plpgsql '
          'security definer set search_path = \'\' as \$\$',
        ),
      );
    });

    test('REVOKE de tudo e GRANT EXECUTE só para authenticated (nunca anon)', () {
      expect(
        norm,
        contains('revoke all on function public.concluir_itens_documento_sei_lote from public, anon, authenticated;'),
      );
      expect(norm, contains('grant execute on function public.concluir_itens_documento_sei_lote to authenticated;'));
    });

    test('perfil ADMIN/GESTOR/OPERADOR verificado primeiro (42501)', () {
      expect(norm, contains('if private.has_perfil(\'ADMIN\', \'GESTOR\', \'OPERADOR\') is not true then'));
      final i = _idx(norm, 'Usuário sem permissão para concluir itens de documento SEI em lote');
      expect(norm.substring(i, i + 120), contains('errcode = \'42501\''));
      expect(_idx(norm, 'has_perfil'), lessThan(_idx(norm, 'pg_advisory_xact_lock')));
    });

    test('limite de 200 itens por chamada', () {
      expect(norm, contains('v_limite_itens constant integer := 200;'));
      final i = _idx(norm, 'cardinality(p_item_ids) > v_limite_itens then');
      expect(norm.substring(i - 10, i + 200), contains('errcode = \'P0001\''));
    });

    test('PROMPT 11.5.2.1 — rejeita p_confirmar_limpeza_destino nulo (P0001), antes de qualquer trabalho', () {
      final i = _idx(norm, 'if p_confirmar_limpeza_destino is null then');
      expect(norm.substring(i, i + 180), contains('errcode = \'P0001\''));
      // antes da canonicalização, do advisory lock e de qualquer lock de linha
      expect(i, lessThan(_idx(norm, 'select array_agg(x.id order by x.id)')));
      expect(i, lessThan(_idx(norm, 'perform pg_advisory_xact_lock(')));
      expect(i, lessThan(_idx(norm, 'for update')));
    });
  });

  group('canonicalização e validação do conjunto de item_ids', () {
    test('rejeita array vazio, elemento nulo e mais de 200 itens', () {
      for (final trecho in [
        'if cardinality(p_item_ids) = 0 then',
        'if cardinality(p_item_ids) > v_limite_itens then',
        'if exists (select 1 from unnest(p_item_ids) as x(id) where x.id is null) then',
      ]) {
        expect(norm, contains(trecho));
      }
    });

    test('canonicaliza como distinto + ordenado por id (nunca deduplica silenciosamente: duplicata é erro)', () {
      expect(norm, contains('select array_agg(x.id order by x.id) into v_item_ids from unnest(p_item_ids) as x(id);'));
      final i = _idx(
        norm,
        'if cardinality(v_item_ids) <> (select count(distinct x.id) from unnest(p_item_ids) as x(id)) then',
      );
      expect(norm.substring(i, i + 220), contains('errcode = \'P0001\''));
      expect(norm.substring(i, i + 220), contains('repetido'));
    });

    test('a canonicalização acontece ANTES do advisory lock e da consulta ao lote existente', () {
      _emOrdem(norm, [
        'select array_agg(x.id order by x.id) into v_item_ids from unnest(p_item_ids) as x(id);',
        'perform pg_advisory_xact_lock(',
        'select * into v_lote from public.documentos_sei_lotes_conclusao where lote_id = p_lote_id;',
      ]);
    });
  });

  group('serialização por lote_id (advisory lock) e identidade da operação', () {
    test('trava por p_lote_id ANTES de qualquer lock de linha (documento/item)', () {
      final lockAdvisory = _idx(
        norm,
        'perform pg_advisory_xact_lock(hashtextextended(\'lote_sei:\' || p_lote_id::text, 0));',
      );
      final lockDocumento = _idx(norm, 'from public.documentos_sei where id = p_documento_id for update;');
      expect(lockAdvisory, lessThan(lockDocumento));
    });

    test('retry idêntico: compara documento, itens, versão, observação, confirmação de limpeza E usuário', () {
      final i = _idx(norm, 'if found then');
      final fim = _idx(norm, 'end if;', desde: _idx(norm, 'errcode = \'P0037\''));
      final ramo = norm.substring(i, fim);
      for (final condicao in [
        'v_lote.documento_id = p_documento_id',
        'v_lote.item_ids = v_item_ids',
        'v_lote.versao_esperada = p_versao_esperada',
        'v_lote.observacao is not distinct from v_observacao',
        'v_lote.confirmar_limpeza_destino = p_confirmar_limpeza_destino',
        'v_lote.criado_por = auth.uid()',
      ]) {
        expect(ramo, contains(condicao), reason: condicao);
      }
    });

    test('retry idêntico devolve o resultado gravado + ja_executado=true, SEM travar nada e SEM escrever', () {
      final iFound = _idx(norm, 'if found then');
      final iReturn = _idx(norm, 'return v_lote.resultado || jsonb_build_object(\'ja_executado\', true);');
      final iRaise = _idx(norm, 'errcode = \'P0037\'');
      expect(iFound, lessThan(iReturn));
      expect(iReturn, lessThan(iRaise));
      final ramoRetry = norm.substring(iFound, iReturn + 80);
      expect(ramoRetry, isNot(contains('for update')));
      expect(ramoRetry, isNot(contains('insert into')));
      expect(ramoRetry, isNot(contains('update public.')));
      expect(ramoRetry, isNot(contains('concluir_item_documento_sei(')));
    });

    test(
      'mesmo lote_id com QUALQUER parâmetro diferente (itens, observação, confirmação, versão ou usuário) -> P0037',
      () {
        final i = _idx(norm, 'lote_id % já foi usado para uma operação com parâmetros diferentes');
        expect(norm.substring(i, i + 260), contains('errcode = \'P0037\''));
        // a mensagem cobre explicitamente os 6 pontos de comparação
        final msg = norm.substring(i, _idx(norm, 'p_lote_id using errcode', desde: i) + 40);
        for (final termo in [
          'documento',
          'itens',
          'versão esperada',
          'observação',
          'confirmação de limpeza',
          'usuário',
        ]) {
          expect(msg, contains(termo), reason: termo);
        }
      },
    );

    test('o INSERT final grava os 6 campos comparados no retry (senão um deles nunca seria comparável)', () {
      final i = _idx(norm, 'insert into public.documentos_sei_lotes_conclusao (');
      final fechamento = _idx(norm, ');', desde: i);
      final insert = norm.substring(i, fechamento);
      for (final coluna in [
        'lote_id',
        'documento_id',
        'item_ids',
        'versao_esperada',
        'observacao',
        'confirmar_limpeza_destino',
        'criado_por',
        'resultado',
      ]) {
        expect(insert, contains(coluna), reason: coluna);
      }
      expect(
        insert,
        contains(
          'p_lote_id, p_documento_id, v_item_ids, p_versao_esperada, v_observacao, '
          'p_confirmar_limpeza_destino, auth.uid(), v_resultado',
        ),
      );
    });
  });

  group('locks: ordem determinística DOCUMENTO -> ITENS -> (dentro da individual) PATRIMÔNIO', () {
    test('documento travado antes dos itens; itens com ORDER BY id + FOR UPDATE', () {
      _emOrdem(norm, [
        'select * into v_documento from public.documentos_sei where id = p_documento_id for update;',
        'perform 1 from public.documentos_sei_itens where id = any (v_item_ids) and documento_id = p_documento_id '
            'order by id for update;',
      ]);
    });

    test('confere existência/pertencimento dos itens DEPOIS de travar (P0002 se algum faltar)', () {
      final travaItens = _idx(norm, 'order by id for update;');
      final i = _idx(norm, 'if v_qtd_encontrados <> cardinality(v_item_ids) then');
      expect(travaItens, lessThan(i));
      expect(norm.substring(i, i + 220), contains('errcode = \'P0002\''));
    });

    test('nenhum lock de patrimônio nesta função — só dentro de concluir_item_documento_sei, no laço', () {
      expect(norm, isNot(contains('from public.patrimonios')));
      // exatamente 2 `for update`: o DOCUMENTO e os ITENS — nenhum terceiro
      // (o de PATRIMÔNIO só existe dentro da função individual, chamada
      // pelo laço, nunca duplicado aqui).
      expect(RegExp('for update').allMatches(norm).length, 2);
      expect(norm, contains('where id = p_documento_id for update;'));
    });

    test('o laço itera pelo patrimonio_id resolvido (não pela ordem recebida do cliente)', () {
      expect(
        norm,
        contains(
          'for v_item_id in select i.id from public.documentos_sei_itens i where i.id = any (v_item_ids) '
          'order by i.patrimonio_id, i.id loop',
        ),
      );
    });
  });

  group('validação do conjunto completo ANTES de concluir qualquer item', () {
    test('todos precisam estar PENDENTE (P0036) — checado antes do laço', () {
      final i = _idx(norm, 'if v_qtd_nao_pendente > 0 then');
      final msg = _idx(norm, 'Um ou mais itens do lote não estão PENDENTE: %');
      expect(norm.substring(msg, msg + 100), contains('errcode = \'P0036\''));
      expect(i, lessThan(_idx(norm, 'for v_item_id in select i.id')));
    });

    test('nenhum patrimônio duplicado no lote (P0001) — checado antes do laço', () {
      final i = _idx(norm, 'Dois ou mais itens deste lote apontam para o mesmo patrimônio');
      expect(norm.substring(i, i + 220), contains('errcode = \'P0001\''));
      expect(_idx(norm, 'having count(*) > 1'), lessThan(_idx(norm, 'for v_item_id in select i.id')));
      // só considera itens com patrimonio_id resolvido
      expect(norm, contains('and patrimonio_id is not null group by patrimonio_id having count(*) > 1'));
    });

    test('versão inicial do documento (P0010), checada antes do laço', () {
      final i = _idx(norm, 'if v_documento.versao <> p_versao_esperada then');
      final trecho = norm.substring(i, i + 320);
      expect(trecho, contains('Conflito de edição: versão % informada, versão atual %'));
      expect(trecho, contains('errcode = \'P0010\''));
      expect(i, lessThan(_idx(norm, 'for v_item_id in select i.id')));
    });

    test(
      'ORDEM completa: perfil -> parâmetros -> canoniza -> advisory lock -> retry/P0037 -> lock documento -> '
      'lock itens -> existência -> PENDENTE/P0036 -> patrimônio duplicado -> versão/P0010 -> laço -> INSERT -> retorno',
      () {
        _emOrdem(norm, [
          'if private.has_perfil(',
          'if p_documento_id is null or p_item_ids is null',
          'select array_agg(x.id order by x.id) into v_item_ids',
          'perform pg_advisory_xact_lock(',
          'select * into v_lote from public.documentos_sei_lotes_conclusao where lote_id = p_lote_id;',
          'errcode = \'P0037\'',
          'select * into v_documento from public.documentos_sei where id = p_documento_id for update;',
          'order by id for update;',
          'if v_qtd_encontrados <> cardinality(v_item_ids) then',
          'if v_qtd_nao_pendente > 0 then',
          'having count(*) > 1',
          'if v_documento.versao <> p_versao_esperada then',
          'for v_item_id in select i.id',
          'insert into public.documentos_sei_lotes_conclusao (',
          'return v_resultado;',
        ]);
      },
    );
  });

  group('chamada da RPC individual e encadeamento de versão', () {
    test('chama public.concluir_item_documento_sei com os 5 parâmetros de hoje, sem nenhum parâmetro novo', () {
      expect(
        norm,
        contains(
          'select public.concluir_item_documento_sei( p_documento_id, v_item_id, v_versao_atual, p_observacao, '
          'p_confirmar_limpeza_destino ) into v_resultado_item;',
        ),
      );
      // a assinatura da individual, na migration dela, continua exatamente com 5 parâmetros
      final individualNorm = _norm(individualBruto);
      expect(
        individualNorm,
        contains(
          'create or replace function public.concluir_item_documento_sei( p_documento_id uuid, p_item_id uuid, '
          'p_versao_esperada integer, p_observacao text default null, p_confirmar_limpeza_destino boolean default false )',
        ),
      );
    });

    test('encadeia a versão: começa em p_versao_esperada e é atualizada pelo retorno de CADA chamada', () {
      expect(norm, contains('v_versao_atual := p_versao_esperada;'));
      expect(norm, contains('v_versao_atual := (v_resultado_item -> \'documento\' ->> \'versao\')::int;'));
      // usada na PRÓXIMA chamada do laço (mesma variável, reatribuída dentro do loop)
      final iLoop = _idx(norm, 'loop select public.concluir_item_documento_sei(');
      final iReatribui = _idx(norm, 'v_versao_atual := (v_resultado_item');
      expect(iLoop, lessThan(iReatribui));
    });

    test('nenhuma regra de negócio (patrimônio/localização/responsável/limpeza) é duplicada nesta função', () {
      for (final proibido in [
        'registrar_movimentacao',
        'localizacao_destino_id',
        'responsavel_destino',
        'limpa_localizacao',
        'DISPONIVEL',
        'TRANSFERENCIA',
      ]) {
        expect(norm, isNot(contains(proibido)), reason: 'regra de $proibido pertence só à função individual');
      }
    });

    test('o resultado de cada item é agregado num array, indexado por item_id', () {
      expect(
        norm,
        contains(
          'v_itens_resultado := v_itens_resultado || jsonb_build_object(\'item_id\', v_item_id, \'resultado\', v_resultado_item);',
        ),
      );
      expect(norm, contains('v_itens_resultado jsonb := \'[]\'::jsonb;'));
    });
  });

  group('PROMPT 11.5.2.1 — compatibilidade confirmada contra o SQL real de 20260925140000', () {
    late String individualNorm;

    setUpAll(() {
      individualNorm = _norm(individualBruto);
    });

    test('assinatura EXATA de concluir_item_documento_sei: 5 parâmetros, tipos e defaults', () {
      expect(
        individualNorm,
        contains(
          'create or replace function public.concluir_item_documento_sei( p_documento_id uuid, p_item_id uuid, '
          'p_versao_esperada integer, p_observacao text default null, p_confirmar_limpeza_destino boolean default false ) '
          'returns jsonb language plpgsql security definer set search_path = \'\' as \$\$',
        ),
      );
    });

    test('a chamada do lote é posicionalmente compatível: uuid, uuid, integer, text, boolean — nessa ordem', () {
      // tipos dos argumentos enviados pelo laço, na mesma ordem da assinatura real
      final chamada = _idx(norm, 'select public.concluir_item_documento_sei(');
      final trecho = norm.substring(
        chamada,
        _idx(norm, 'into v_resultado_item;', desde: chamada) + 'into v_resultado_item;'.length,
      );
      expect(
        trecho,
        contains(
          '( p_documento_id, v_item_id, v_versao_atual, p_observacao, p_confirmar_limpeza_destino ) '
          'into v_resultado_item;',
        ),
      );
      // p_documento_id (uuid, do parâmetro do lote) / v_item_id (uuid, do laço) /
      // v_versao_atual (integer) / p_observacao (text, do parâmetro do lote) /
      // p_confirmar_limpeza_destino (boolean, do parâmetro do lote) — mesmos
      // tipos declarados na assinatura da individual, na mesma posição.
      expect(norm, contains('v_item_id uuid;'));
      expect(norm, contains('v_versao_atual integer;'));
      expect(
        norm,
        contains(
          'create or replace function public.concluir_itens_documento_sei_lote( p_documento_id uuid, '
          'p_item_ids uuid[], p_versao_esperada integer, p_lote_id uuid, p_observacao text default null, '
          'p_confirmar_limpeza_destino boolean default false )',
        ),
      );
    });

    test('estrutura do JSON retornado: chave "documento" é to_jsonb(v_documento), com a coluna versao', () {
      // as DUAS ramificações de retorno da individual (nova conclusão e
      // idempotente) devolvem 'documento', 'item' e 'movimentacao' como
      // to_jsonb(row) — 'documento' é sempre a linha inteira de
      // documentos_sei, que tem a coluna `versao`.
      expect(individualNorm, contains('\'ja_concluido\', false, \'documento\', to_jsonb(v_documento)'));
      expect(individualNorm, contains('\'ja_concluido\', true, \'documento\', to_jsonb(v_documento)'));
      // a coluna existe de fato na tabela (mesmo helper de checagem do PROMPT 11.4.2)
      final schema = _norm(_ler(_sei));
      expect(schema, contains('versao integer not null default 1,'));
    });

    test('o lote lê essa mesma chave (documento -> versao) para encadear a próxima chamada', () {
      expect(norm, contains('v_versao_atual := (v_resultado_item -> \'documento\' ->> \'versao\')::int;'));
    });

    test('public.normalize_text existe, com a assinatura (text) returns text, strict', () {
      final schema = _norm(_ler('${_dir}20260910120000_initial_schema.sql'));
      expect(
        schema,
        contains(
          'create or replace function public.normalize_text(p_valor text) returns text language sql immutable strict '
          'set search_path = \'\' as \$\$ select nullif(btrim(p_valor, E\' \\t\\r\\n\'), \'\'); \$\$;',
        ),
      );
    });

    test('o lote chama public.normalize_text(p_observacao) — mesma função e mesmo argumento que a individual usa', () {
      expect(norm, contains('public.normalize_text(p_observacao)'));
      expect(individualNorm, contains('v_observacao text := public.normalize_text(p_observacao);'));
    });
  });

  group('normalização de p_observacao e a comparação de idempotência', () {
    test('v_observacao é o valor NORMALIZADO (não o texto cru) — mesma chamada que a individual faz internamente', () {
      expect(norm, contains('v_observacao text := public.normalize_text(p_observacao);'));
    });

    test('o retry compara pelo valor NORMALIZADO gravado (v_lote.observacao), nunca por p_observacao cru', () {
      final i = _idx(norm, 'if found then');
      final fim = _idx(norm, 'end if;', desde: _idx(norm, 'errcode = \'P0037\''));
      final ramo = norm.substring(i, fim);
      expect(ramo, contains('v_lote.observacao is not distinct from v_observacao'));
      expect(ramo, isNot(contains('v_lote.observacao is not distinct from p_observacao')));
    });

    test('o valor gravado no INSERT é v_observacao (normalizado), não p_observacao', () {
      final i = _idx(norm, 'insert into public.documentos_sei_lotes_conclusao (');
      final valores = norm.substring(i, _idx(norm, ');', desde: i));
      expect(valores, contains('v_observacao'));
      expect(valores, isNot(contains(', p_observacao,')));
    });
  });

  group('rollback completo (tudo ou nada)', () {
    test('nenhum bloco EXCEPTION/WHEN OTHERS: qualquer erro do laço propaga e aborta a transação inteira', () {
      expect(norm, isNot(contains('exception when')));
      expect(norm, isNot(contains('when others')));
    });

    test('o INSERT do registro de lote só acontece DEPOIS do laço inteiro terminar com sucesso', () {
      final fimLoop = _idx(norm, 'end loop;');
      final insert = _idx(norm, 'insert into public.documentos_sei_lotes_conclusao (');
      expect(fimLoop, lessThan(insert));
    });

    test(
      'nenhuma escrita própria antes do laço (documento/item/movimentação só mudam dentro da chamada individual)',
      () {
        // só o CORPO DA FUNÇÃO (a partir de "as $$") — antes disso vem a
        // `CREATE TABLE`, que legitimamente tem "on delete restrict" nas FKs.
        final inicioFuncao = _idx(norm, 'as \$\$ declare');
        final iLoop = _idx(norm, 'for v_item_id in select i.id', desde: inicioFuncao);
        final antes = norm.substring(inicioFuncao, iLoop);
        expect(antes, isNot(contains('insert into')));
        expect(RegExp(r'update public\.').hasMatch(antes), isFalse);
        for (final efeito in ['delete ', 'execute ', 'nextval', 'set_config', 'notify ']) {
          expect(antes, isNot(contains(efeito)), reason: efeito);
        }
      },
    );

    test('não escreve direto em movimentacoes/patrimonios/documentos_sei_itens (só via a função individual)', () {
      expect(norm, isNot(contains('insert into public.movimentacoes')));
      expect(norm, isNot(contains('update public.patrimonios')));
      expect(norm, isNot(contains('update public.movimentacoes')));
      expect(norm, isNot(contains('update public.documentos_sei_itens')));
      expect(norm, isNot(contains('insert into public.documentos_sei_eventos')));
    });
  });

  group('retorno: distinção entre primeiro sucesso e retry', () {
    test('primeira conclusão: ja_executado=false, documento final e a lista de itens', () {
      final i = _idx(norm, '\'ja_executado\', false');
      final trecho = norm.substring(i - 30, i + 220);
      expect(trecho, contains('\'documento\', to_jsonb(v_documento)'));
      expect(trecho, contains('\'itens\', v_itens_resultado'));
    });

    test('retry idêntico: ja_executado=true, resultado é o MESMO gravado (nunca recalculado)', () {
      expect(norm, contains('return v_lote.resultado || jsonb_build_object(\'ja_executado\', true);'));
      // não há nenhum outro `jsonb_build_object('ja_executado'` fora dos dois casos (false na 1ª vez, true no retry)
      expect(RegExp('\'ja_executado\'').allMatches(norm).length, 2);
    });

    test('o documento devolvido na 1ª execução é relido DEPOIS do laço (reflete a versão final, não a inicial)', () {
      final fimLoop = _idx(norm, 'end loop;');
      final releitura = _idx(
        norm,
        'select * into v_documento from public.documentos_sei where id = p_documento_id;',
        desde: fimLoop,
      );
      expect(releitura, greaterThan(fimLoop));
    });
  });

  group('códigos de erro', () {
    test('define exatamente P0036 e P0037 como novos, e propaga os demais só via a chamada individual', () {
      final codigosProprios = RegExp('errcode = \'([A-Z0-9]{5})\'').allMatches(norm).map((m) => m.group(1)!).toSet();
      expect(codigosProprios, {'42501', 'P0001', 'P0002', 'P0010', 'P0036', 'P0037'});
      // P0030-P0035 nunca são levantados por ESTA função — só pela individual, chamada dentro do laço
      for (final codigo in ['P0030', 'P0031', 'P0032', 'P0033', 'P0034', 'P0035']) {
        expect(codigosProprios, isNot(contains(codigo)), reason: codigo);
      }
    });
  });

  group('apoio: colunas referenciadas existem no schema (mesmo helper de checagem já usado no PROMPT 11.4.2)', () {
    Set<String> colunas(String tabela) {
      final todo = [_sei, _localizacoes].map(_ler).join('\n');
      final bloco = RegExp('create table public\\.$tabela \\(\n([\\s\\S]*?)\n\\);').firstMatch(todo)?.group(1);
      final resultado = <String>{};
      if (bloco != null) {
        for (final m in RegExp(r'^  ([a-z_]+) ', multiLine: true).allMatches(bloco)) {
          final nome = m.group(1)!;
          if (nome != 'constraint' && nome != 'unique' && nome != 'primary') resultado.add(nome);
        }
      }
      return resultado;
    }

    test('documentos_sei_itens tem patrimonio_id e status, usados na checagem de consistência do lote', () {
      expect(colunas('documentos_sei_itens'), containsAll(['patrimonio_id', 'status', 'documento_id']));
    });

    test('a tabela de lote não referencia nenhuma coluna nova em documentos_sei/documentos_sei_itens/eventos', () {
      // esta migration não altera nenhuma das 3 tabelas SEI existentes
      expect(norm, isNot(contains('alter table public.documentos_sei ')));
      expect(norm, isNot(contains('alter table public.documentos_sei_itens')));
      expect(norm, isNot(contains('alter table public.documentos_sei_eventos')));
    });
  });
}
