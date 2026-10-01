import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PROMPT 11.4.2 — testes ESTRUTURAIS das duas migrations preparadas (NÃO
/// aplicadas) da conclusão de entrega SEI:
///
///  * `20260925130000_editar_documento_sei_resolver_patrimonio.sql` — mantém
///    `patrimonio_id` coerente com `numero_patrimonio_corrigido`;
///  * `20260925140000_add_concluir_item_documento_sei.sql` — a RPC atômica
///    `concluir_item_documento_sei`.
///
/// Não há Postgres neste ambiente (nem local nem remoto foi tocado): os testes
/// leem o TEXTO dos arquivos. Cada cenário pedido no prompt vira uma asserção
/// sobre o guard, o código de erro, a ORDEM dos passos ou a ausência de
/// escrita — o que o SQL faz de fato quando roda só pode ser provado em
/// homologação (ver relatório).
const _dir = 'supabase/migrations/';
const _bloqueio = '${_dir}20260925120000_block_edit_documento_sei_encerrado.sql';
const _edicao = '${_dir}20260925130000_editar_documento_sei_resolver_patrimonio.sql';
const _conclusao = '${_dir}20260925140000_add_concluir_item_documento_sei.sql';
const _inicial = '${_dir}20260910120000_initial_schema.sql';
const _localizacoes = '${_dir}20260914140000_add_localizacoes.sql';
const _sei = '${_dir}20260921170000_add_documentos_sei.sql';

String _ler(String caminho) => File(caminho).readAsStringSync().replaceAll('\r\n', '\n');

String _semComentarios(String sql) => sql.replaceAll(RegExp(r'--[^\n]*'), '');

/// SQL sem comentários e com o espaço em branco colapsado — comparação
/// semântica (ignora indentação, quebras de linha, CRLF/LF e comentários).
String _norm(String sql) => _semComentarios(sql).replaceAll(RegExp(r'\s+'), ' ').trim();

final _blocoMarcado = RegExp(
  r'^[ \t]*-- >>> 11\.4\.2-A[ \t]*\n[\s\S]*?^[ \t]*-- <<< 11\.4\.2-A[ \t]*\n',
  multiLine: true,
);

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

Set<String> _colunas(String tabela) {
  final todo = [_inicial, _localizacoes, _sei].map(_ler).join('\n');
  final bloco = RegExp('create table public\\.$tabela \\(\n([\\s\\S]*?)\n\\);').firstMatch(todo)!.group(1)!;
  final colunas = <String>{};
  for (final m in RegExp(r'^  ([a-z_]+) ', multiLine: true).allMatches(bloco)) {
    final nome = m.group(1)!;
    if (nome != 'constraint' && nome != 'unique' && nome != 'primary') colunas.add(nome);
  }
  for (final alter in RegExp('alter table public\\.$tabela\\b([^;]*);').allMatches(todo)) {
    for (final m in RegExp(r'add column ([a-z_]+)').allMatches(alter.group(1)!)) {
      colunas.add(m.group(1)!);
    }
  }
  return colunas;
}

void main() {
  group('PARTE A — editar_documento_sei_pendente re-resolve patrimonio_id', () {
    late String bruto;
    late String norm;

    setUpAll(() {
      bruto = _ler(_edicao);
      norm = _norm(bruto);
    });

    test('uma única função, sem GRANT/REVOKE/DROP/ALTER/DELETE (CREATE OR REPLACE preserva ACL)', () {
      expect(RegExp('create or replace function ').allMatches(norm).length, 1);
      expect(norm, contains('create or replace function public.editar_documento_sei_pendente('));
      for (final proibido in ['grant ', 'revoke ', 'drop ', 'alter ', 'delete ', 'create table', 'create trigger']) {
        expect(norm, isNot(contains(proibido)), reason: 'não deveria conter "$proibido"');
      }
    });

    test('mesmo nome, parâmetros, retorno, SECURITY DEFINER e search_path da função anterior', () {
      expect(
        norm,
        contains(
          'create or replace function public.editar_documento_sei_pendente( p_documento_id uuid, '
          'p_versao_esperada integer, p_motivo text, p_alteracoes jsonb default \'{}\'::jsonb, '
          'p_itens_alterados jsonb default \'[]\'::jsonb ) returns public.documentos_sei language plpgsql '
          'security definer set search_path = \'\' as \$\$',
        ),
      );
    });

    test('fora dos blocos marcados, o corpo é IDÊNTICO ao da migration 20260925120000 (com o guard de 11.3.13)', () {
      final anterior = _norm(_ler(_bloqueio));
      final semBlocos = _norm(bruto.replaceAll(_blocoMarcado, ''));
      expect(semBlocos, anterior);
    });

    test('há exatamente 3 blocos novos (declare, validação, update) e nada além deles', () {
      final aberturas = RegExp(r'^[ \t]*-- >>> 11\.4\.2-A[ \t]*$', multiLine: true).allMatches(bruto).length;
      final fechamentos = RegExp(r'^[ \t]*-- <<< 11\.4\.2-A[ \t]*$', multiLine: true).allMatches(bruto).length;
      expect(aberturas, 3);
      expect(fechamentos, 3);
      expect(_blocoMarcado.allMatches(bruto).length, 3);
    });

    test('mantém o guard de documento encerrado da 11.3.13, antes de qualquer validação de payload', () {
      _emOrdem(norm, [
        'if v_qtd_concluidos > 0 then',
        'encerrado (nenhum item pendente)',
        'if jsonb_typeof(p_alteracoes) <> \'object\'',
        'v_ids_itens_alterados := array[]::uuid[];',
      ]);
    });

    test('só re-resolve quando o payload traz numero_patrimonio_corrigido', () {
      expect(norm, contains('if v_item_edicao ? \'numero_patrimonio_corrigido\' then v_corrigido_novo :='));
    });

    test('número efetivo = corrigido, ou original quando a correção é removida; mesma normalização do banco', () {
      expect(
        norm,
        contains(
          'v_numero_efetivo := upper(public.normalize_text(coalesce(v_corrigido_novo, '
          'v_item_check.numero_patrimonio_original)));',
        ),
      );
      // a regra real do banco: CHECK + trigger normalize_patrimonio + índice único
      final inicial = _norm(_ler(_inicial));
      expect(
        inicial,
        contains('numero_patrimonio is not distinct from upper(public.normalize_text(numero_patrimonio))'),
      );
      expect(inicial, contains('new.numero_patrimonio := upper(public.normalize_text(new.numero_patrimonio));'));
      expect(
        inicial,
        contains('create unique index patrimonios_numero_patrimonio_key on public.patrimonios (numero_patrimonio)'),
      );
    });

    test('busca em public.patrimonios pelo número normalizado e recusa mais de um resultado', () {
      expect(
        norm,
        contains(
          'select array_agg(p.id) into v_ids_encontrados from public.patrimonios p where p.numero_patrimonio = v_numero_efetivo;',
        ),
      );
      expect(norm, contains('if cardinality(v_ids_encontrados) > 1 then'));
    });

    test(
      'correção informada + patrimônio inexistente bloqueia (P0002); correção removida sem original volta a nulo',
      () {
        expect(
          norm,
          contains(
            'if v_patrimonio_resolvido is null and v_corrigido_novo is not null then raise exception '
            '\'Patrimônio % não encontrado no InvTec',
          ),
        );
        final i = _idx(norm, 'não encontrado no InvTec — a correção do item % não foi aplicada');
        expect(norm.substring(i, i + 200), contains('errcode = \'P0002\''));
        // sem a condição `v_corrigido_novo is not null` nunca haveria caminho para "voltar a nulo"
        expect(norm, contains('v_patrimonio_resolvido := null;'));
      },
    );

    test('a re-resolução acontece na VALIDAÇÃO (antes de qualquer escrita), depois do lock do item', () {
      final posicoes = _emOrdem(norm, [
        'select * into v_item_check from public.documentos_sei_itens where id = v_item_id for update;',
        'if v_item_edicao ? \'numero_patrimonio_corrigido\' then v_corrigido_novo :=',
        'v_vinculos := v_vinculos || jsonb_build_object(v_item_id::text, v_patrimonio_resolvido);',
        'v_dados_antes := jsonb_build_object(',
        'select coalesce(jsonb_agg(to_jsonb(i.*)), \'[]\'::jsonb) into v_itens_antes',
        'update public.documentos_sei set',
        'update public.documentos_sei_itens set',
        'select coalesce(jsonb_agg(to_jsonb(i.*)), \'[]\'::jsonb) into v_itens_depois',
        'insert into public.documentos_sei_eventos',
      ]);
      expect(posicoes, orderedEquals([...posicoes]..sort()));
    });

    test('o UPDATE do item grava patrimonio_id só para itens re-resolvidos e NUNCA toca origem_setor_id', () {
      expect(
        norm,
        contains(
          'patrimonio_id = case when v_vinculos ? ((v_item_edicao ->> \'item_id\')::uuid)::text then '
          'nullif(v_vinculos ->> ((v_item_edicao ->> \'item_id\')::uuid)::text, \'\')::uuid else patrimonio_id end,',
        ),
      );
      expect(norm, isNot(contains('origem_setor_id =')));
    });

    test('o vínculo entra no MESMO evento EDICAO: antes/depois são a linha inteira do item (inclui patrimonio_id)', () {
      expect(RegExp("'EDICAO'").allMatches(norm).length, 1);
      expect(RegExp(r'insert into public\.documentos_sei_eventos').allMatches(norm).length, 1);
      expect(norm, contains("jsonb_build_object('documento', v_dados_antes, 'itens', v_itens_antes)"));
      expect(_colunas('documentos_sei_itens'), contains('patrimonio_id'));
      expect(norm, contains('select coalesce(jsonb_agg(to_jsonb(i.*)), \'[]\'::jsonb) into v_itens_depois'));
    });

    test('correção removida sem original existente: item continua PENDENTE (a edição nunca muda status)', () {
      for (final update in RegExp(r'update public\.documentos_sei_itens set (.*?) where').allMatches(norm)) {
        expect(update.group(1), isNot(contains('status =')), reason: 'a edição não pode mudar o status do item');
      }
      // só vira erro quando HÁ correção informada; sem correção o vínculo segue como nulo, sem exceção
      expect(norm, contains('if v_patrimonio_resolvido is null and v_corrigido_novo is not null then'));
      expect(
        norm,
        contains('v_vinculos := v_vinculos || jsonb_build_object(v_item_id::text, v_patrimonio_resolvido);'),
      );
      // e o item sem vínculo é barrado pela futura conclusão
      expect(_norm(_ler(_conclusao)), contains('if v_item.patrimonio_id is null then raise exception'));
    });

    test('não adiciona nenhum lock novo (só lê patrimonios)', () {
      final antes = RegExp('for update').allMatches(_norm(_ler(_bloqueio))).length;
      expect(RegExp('for update').allMatches(norm).length, antes);
      expect(norm, isNot(contains('for share')));
      expect(norm, isNot(contains('for key share')));
    });
  });

  group('PARTE B — concluir_item_documento_sei', () {
    late String bruto;
    late String norm;

    setUpAll(() {
      bruto = _ler(_conclusao);
      norm = _norm(bruto);
    });

    test('assinatura: parâmetros e defaults aprovados, sem p_data_entrega, retorna jsonb', () {
      expect(
        norm,
        contains(
          'create or replace function public.concluir_item_documento_sei( p_documento_id uuid, p_item_id uuid, '
          'p_versao_esperada integer, p_observacao text default null, p_confirmar_limpeza_destino boolean default false ) '
          'returns jsonb language plpgsql security definer set search_path = \'\' as \$\$',
        ),
      );
      expect(norm, isNot(contains('p_data_entrega')));
      expect(RegExp('create or replace function ').allMatches(norm).length, 1);
    });

    test('permissões: REVOKE de tudo e GRANT EXECUTE só para authenticated (nunca anon)', () {
      expect(
        norm,
        contains('revoke all on function public.concluir_item_documento_sei from public, anon, authenticated;'),
      );
      expect(norm, contains('grant execute on function public.concluir_item_documento_sei to authenticated;'));
      expect(RegExp('grant ').allMatches(norm).length, 1);
    });

    test('só cria a função: nada de DROP/ALTER/DELETE/criação de tabela, trigger ou índice', () {
      for (final proibido in [
        'drop ',
        'alter ',
        'delete ',
        'create table',
        'create trigger',
        'create index',
        'truncate',
      ]) {
        expect(norm, isNot(contains(proibido)), reason: 'não deveria conter "$proibido"');
      }
    });

    test('perfil ADMIN/GESTOR/OPERADOR verificado primeiro (42501)', () {
      expect(norm, contains('if private.has_perfil(\'ADMIN\', \'GESTOR\', \'OPERADOR\') is not true then'));
      final i = _idx(norm, 'Usuário sem permissão para concluir item de documento SEI');
      expect(norm.substring(i, i + 120), contains('errcode = \'42501\''));
    });

    test('ORDEM: perfil -> lock DOCUMENTO -> lock ITEM -> idempotência -> versão -> tipo -> destino/decisões '
        '-> número efetivo -> lock PATRIMÔNIO -> UUID -> origem -> status -> movimento posterior -> duplicidade '
        '-> limpeza -> registrar_movimentacao -> item -> documento -> evento -> retorno', () {
      _emOrdem(norm, [
        'if private.has_perfil(',
        'from public.documentos_sei where id = p_documento_id for update;',
        'where id = p_item_id and documento_id = p_documento_id for update;',
        'if v_item.status = \'CONCLUIDO\' then',
        '\'ja_concluido\', true',
        'if v_item.status = \'PENDENTE\' and v_item.movimentacao_id is not null then',
        'if v_item.status <> \'PENDENTE\' then',
        'if v_documento.versao <> p_versao_esperada then',
        'if v_documento.tipo_operacao_pretendida <> \'TRANSFERENCIA\' then',
        'if v_item.destino_setor_id is null then',
        'if v_item.decisao_localizacao = \'PENDENTE\' then',
        'if v_item.decisao_responsavel = \'PENDENTE\' then',
        'v_numero_efetivo := upper(public.normalize_text(',
        'from public.patrimonios where id = v_item.patrimonio_id for update;',
        'if v_patrimonio.numero_patrimonio is distinct from v_numero_efetivo then',
        'if v_patrimonio.setor_atual_id <> v_item.origem_setor_id then',
        'if v_patrimonio.status not in (\'DISPONIVEL\', \'EM_USO\') then',
        'm.criado_em > v_item.criado_em',
        'or m.data_movimentacao > v_item.criado_em',
        'and public.normalize_text(m.numero_documento) = v_numero_documento',
        'v_limpa_localizacao := ',
        'and p_confirmar_limpeza_destino is not true then',
        'from public.registrar_movimentacao(',
        'update public.documentos_sei_itens set status = \'CONCLUIDO\', movimentacao_id = v_movimentacao.id',
        'update public.documentos_sei set versao = versao + 1, atualizado_em = now()',
        'insert into public.documentos_sei_eventos',
        '\'ja_concluido\', false',
      ]);
    });

    test('locks: DOCUMENTO, ITEM e PATRIMÔNIO com FOR UPDATE, nessa ordem, e nenhum outro lock', () {
      final travas = RegExp(
        'from public\\.([a-z_]+)[^;]*?for update;',
      ).allMatches(norm).map((m) => m.group(1)).toList();
      expect(travas, ['documentos_sei', 'documentos_sei_itens', 'patrimonios']);
      expect(RegExp('for update').allMatches(norm).length, 3);
      expect(norm, isNot(contains('for share')));
    });

    test('cenário clique duplo / item já CONCLUIDO: devolve o estado existente, sem escrever e sem checar versão', () {
      final ini = _idx(norm, 'if v_item.status = \'CONCLUIDO\' then');
      final fim = _idx(norm, 'end if;', desde: _idx(norm, '\'ja_concluido\', true'));
      final ramo = norm.substring(ini, fim);
      expect(ramo, contains('\'ja_concluido\', true'));
      expect(ramo, contains('\'documento\', to_jsonb(v_documento)'));
      expect(ramo, contains('\'item\', to_jsonb(v_item)'));
      expect(ramo, contains('\'movimentacao\', to_jsonb(v_movimentacao)'));
      expect(ramo, contains('from public.movimentacoes where id = v_item.movimentacao_id'));
      expect(ramo, isNot(contains('insert into')));
      expect(ramo, isNot(contains('update public.')));
      expect(ramo, isNot(contains('registrar_movimentacao')));
      // idempotência ANTES da versão: a repetição envia a versão antiga
      expect(ini, lessThan(_idx(norm, 'if v_documento.versao <> p_versao_esperada then')));
    });

    group('idempotência: o retry nunca devolve movimentação/item/documento incompatível', () {
      late String ramo;

      setUp(() {
        final ini = _idx(norm, 'if v_item.status = \'CONCLUIDO\' then');
        ramo = norm.substring(ini, _idx(norm, 'end if;', desde: _idx(norm, '\'ja_concluido\', true')));
      });

      test('antes do retorno, documento e item já foram localizados E TRAVADOS (nessa ordem)', () {
        _emOrdem(norm, [
          'from public.documentos_sei where id = p_documento_id for update;',
          'from public.documentos_sei_itens where id = p_item_id and documento_id = p_documento_id for update;',
          'if v_item.status = \'CONCLUIDO\' then',
          '\'ja_concluido\', true',
        ]);
      });

      test('documento errado: o item só é encontrado dentro do documento informado; de outro documento -> P0001', () {
        // a busca já filtra `documento_id = p_documento_id`: um item de outro documento nunca chega ao ramo idempotente
        expect(norm, contains('where id = p_item_id and documento_id = p_documento_id for update;'));
        final i = _idx(norm, 'Item % não pertence ao documento %');
        expect(norm.substring(i, i + 160), contains('errcode = \'P0001\''));
        expect(i, lessThan(_idx(norm, 'if v_item.status = \'CONCLUIDO\' then')));
      });

      test('status CONCLUIDO com movimentacao_id nulo -> P0030 (nunca retorna)', () {
        final i = _idx(ramo, 'if v_item.movimentacao_id is null then');
        expect(ramo.substring(i, i + 260), contains('errcode = \'P0030\''));
        expect(i, lessThan(_idx(ramo, '\'ja_concluido\', true')));
      });

      test('movimentação vinculada INEXISTENTE -> P0030 (nunca retorna)', () {
        final busca = _idx(ramo, 'from public.movimentacoes where id = v_item.movimentacao_id;');
        final i = _idx(ramo, 'if not found then', desde: busca);
        expect(ramo.substring(i, i + 260), contains('errcode = \'P0030\''));
        expect(i, lessThan(_idx(ramo, '\'ja_concluido\', true')));
      });

      test('movimentação de PATRIMÔNIO incompatível com o do item (ou item sem patrimônio) -> P0030', () {
        final i = _idx(
          ramo,
          'if v_item.patrimonio_id is null or v_movimentacao.patrimonio_id is distinct from v_item.patrimonio_id then',
        );
        expect(ramo.substring(i, i + 320), contains('errcode = \'P0030\''));
        expect(i, lessThan(_idx(ramo, '\'ja_concluido\', true')));
        // a coluna comparada existe em movimentacoes
        expect(_colunas('movimentacoes'), contains('patrimonio_id'));
      });

      test('o retorno idempotente só traz o item/documento/movimentação que acabaram de ser validados', () {
        final retorno = ramo.substring(_idx(ramo, 'return jsonb_build_object('));
        expect(retorno, contains('\'documento\', to_jsonb(v_documento)'));
        expect(retorno, contains('\'item\', to_jsonb(v_item)'));
        expect(retorno, contains('\'movimentacao\', to_jsonb(v_movimentacao)'));
      });
    });

    test('estados inconsistentes: CONCLUIDO sem movimentação e PENDENTE com movimentação -> P0030', () {
      for (final msg in [
        'está CONCLUIDO sem movimentação vinculada',
        'está PENDENTE mas já tem movimentação vinculada',
        'vinculada ao item % não encontrada',
        'não pertence ao patrimônio vinculado ao item',
      ]) {
        final i = _idx(norm, msg);
        expect(norm.substring(i, i + 260), contains('errcode = \'P0030\''), reason: msg);
      }
    });

    test('a constraint de coerência e o índice único de movimentacao_id continuam sendo a rede final', () {
      final sei = _norm(_ler(_sei));
      expect(
        sei,
        contains(
          'create unique index documentos_sei_itens_movimentacao_unica on public.documentos_sei_itens (movimentacao_id) where movimentacao_id is not null;',
        ),
      );
      expect(sei, contains('constraint documentos_sei_itens_status_coerente check ('));
      expect(sei, contains('(status = \'CONCLUIDO\' and movimentacao_id is not null and motivo_cancelamento is null)'));
    });

    test('cenário versão divergente -> P0010 (mesma mensagem/código de editar_documento_sei_pendente)', () {
      final i = _idx(norm, 'if v_documento.versao <> p_versao_esperada then');
      final trecho = norm.substring(i, i + 320);
      expect(trecho, contains('Conflito de edição: versão % informada, versão atual %'));
      expect(trecho, contains('errcode = \'P0010\''));
    });

    test('só TRANSFERENCIA (V1) e sem data manual: p_data_movimentacao => null', () {
      final i = _idx(norm, 'tipo_operacao_pretendida <> \'TRANSFERENCIA\'');
      expect(norm.substring(i, i + 260), contains('errcode = \'P0001\''));
      expect(norm, contains('p_tipo => \'TRANSFERENCIA\''));
      expect(norm, contains('p_data_movimentacao => null'));
    });

    test('cenário decisão PENDENTE (localização ou responsável) bloqueia — PENDENTE nunca vira null sozinho', () {
      for (final campo in ['localizacao', 'responsavel']) {
        final i = _idx(norm, 'if v_item.decisao_$campo = \'PENDENTE\' then');
        expect(norm.substring(i, i + 200), contains('errcode = \'P0001\''), reason: campo);
      }
      expect(norm, contains('if v_item.destino_setor_id is null then'));
    });

    test('cenário patrimônio inexistente -> P0002; UUID incoerente com o número efetivo -> P0031', () {
      expect(
        norm,
        contains(
          'v_numero_efetivo := upper(public.normalize_text( coalesce(v_item.numero_patrimonio_corrigido, v_item.numero_patrimonio_original) ));',
        ),
      );
      final naoEncontrado = _idx(
        norm,
        'Patrimônio % não encontrado no InvTec — o patrimônio vinculado ao item agora tem outro número',
      );
      expect(norm.substring(naoEncontrado, naoEncontrado + 220), contains('errcode = \'P0002\''));
      final incoerente = _idx(norm, 'Vínculo incoerente:');
      expect(norm.substring(incoerente, incoerente + 320), contains('errcode = \'P0031\''));
      for (final msg in ['não tem número de patrimônio', 'não está vinculado a um patrimônio']) {
        final i = _idx(norm, msg);
        expect(norm.substring(i, i + 200), contains('errcode = \'P0031\''), reason: msg);
      }
    });

    test(
      'o patrimônio é travado PELO patrimonio_id do item (nunca uma linha alheia) e o número é reconferido sob lock',
      () {
        final i = _idx(
          norm,
          'select * into v_patrimonio from public.patrimonios where id = v_item.patrimonio_id for update;',
        );
        expect(i, greaterThan(0));
        // patrimonios.numero_patrimonio é único: "número efetivo = número do patrimônio travado" prova UUID = patrimonio_id
        expect(_norm(_ler(_inicial)), contains('create unique index patrimonios_numero_patrimonio_key'));
      },
    );

    test('cenário origem divergente / status inválido -> P0032; sem origem resolvida também bloqueia', () {
      for (final msg in [
        'não tem origem resolvida',
        'Origem divergente: o setor atual do patrimônio',
        'não pode ser transferido',
      ]) {
        final i = _idx(norm, msg);
        expect(norm.substring(i, i + 260), contains('errcode = \'P0032\''), reason: msg);
      }
    });

    group('movimentação posterior ao item (P0033)', () {
      const predicado =
          'if exists ( select 1 from public.movimentacoes m where m.patrimonio_id = v_patrimonio.id and ( '
          'm.criado_em > v_item.criado_em or m.data_movimentacao > v_item.criado_em ) ) then '
          'raise exception \'O patrimônio % foi movimentado depois da criação desta pendência';

      test('predicado exato: MESMO patrimônio E (criado_em > item OU data_movimentacao > item) — com parênteses', () {
        expect(norm, contains(predicado));
        // sem os parênteses o AND/OR mudaria de sentido e olharia movimentações de outros patrimônios
        expect(norm, isNot(contains('and m.criado_em > v_item.criado_em or m.data_movimentacao')));
      });

      test('só criado_em posterior: a primeira condição sozinha já basta (OR)', () {
        expect(norm, contains('m.criado_em > v_item.criado_em or m.data_movimentacao > v_item.criado_em'));
        expect(RegExp('m\\.criado_em > v_item\\.criado_em').allMatches(norm).length, 1);
      });

      test('só data_movimentacao posterior: a segunda condição sozinha já basta (OR)', () {
        expect(RegExp('m\\.data_movimentacao > v_item\\.criado_em').allMatches(norm).length, 1);
        // o horário efetivo gravado por registrar_movimentacao é clock_timestamp() (mais tardio que now())
        final reg = _norm(_ler(_localizacoes));
        expect(reg, contains('v_agora := clock_timestamp();'));
        expect(reg, contains('numero_documento, numero_chamado, realizado_por, data_movimentacao'));
      });

      test('as duas condições verdadeiras também bloqueiam (mesmo raise, P0033)', () {
        final msg = _idx(norm, 'foi movimentado depois da criação desta pendência');
        expect(norm.substring(msg, msg + 200), contains('errcode = \'P0033\''));
      });

      test('nenhuma movimentação posterior: só bloqueia quando EXISTE uma (comparação estrita, sem >=)', () {
        expect(norm, isNot(contains('m.criado_em >= v_item.criado_em')));
        expect(norm, isNot(contains('m.data_movimentacao >= v_item.criado_em')));
        expect(
          norm,
          contains('if exists ( select 1 from public.movimentacoes m where m.patrimonio_id = v_patrimonio.id'),
        );
        expect(norm, isNot(contains('if not exists ( select 1 from public.movimentacoes')));
      });

      test('as colunas comparadas existem em movimentacoes e em documentos_sei_itens', () {
        expect(_colunas('movimentacoes'), containsAll(['criado_em', 'data_movimentacao']));
        expect(_colunas('documentos_sei_itens'), contains('criado_em'));
      });

      test('o limite (não é ordenação absoluta por commit; retrodatação manual) está documentado', () {
        final comentarios = RegExp(r'--[^\n]*').allMatches(bruto).map((m) => m.group(0)!).join(' ');
        expect(comentarios, contains('NÃO é uma ordenação absoluta por commit'));
        expect(comentarios, contains('RETRODATADA manualmente'));
      });

      test('as validações de estado atual continuam obrigatórias (setor = origem, status, vínculo UUID/número)', () {
        _emOrdem(norm, [
          'if v_patrimonio.numero_patrimonio is distinct from v_numero_efetivo then',
          'if v_patrimonio.setor_atual_id <> v_item.origem_setor_id then',
          'if v_patrimonio.status not in (\'DISPONIVEL\', \'EM_USO\') then',
          'foi movimentado depois da criação desta pendência',
        ]);
      });
    });

    test('cenário documento duplicado: mesma movimentação do patrimônio com o mesmo número SEI -> P0034', () {
      expect(
        norm,
        contains(
          'v_numero_documento := coalesce( public.normalize_text(v_documento.numero_documento_sei), public.normalize_text(v_documento.numero_documento_formatado) );',
        ),
      );
      final msg = _idx(norm, 'Já existe movimentação do patrimônio % com o documento %');
      expect(norm.substring(msg, msg + 260), contains('errcode = \'P0034\''));
      // o mesmo valor é o que a conclusão grava em movimentacoes.numero_documento
      expect(norm, contains('p_numero_documento => v_numero_documento'));
    });

    test(
      'mesmo documento em patrimônios DIFERENTES não é duplicidade: toda busca em movimentacoes filtra por patrimônio',
      () {
        final buscas = RegExp(
          r'from public\.movimentacoes m where (.*?)\)',
        ).allMatches(norm).map((m) => m.group(1)!).toList();
        expect(buscas, hasLength(2), reason: 'movimento posterior + duplicidade');
        for (final filtro in buscas) {
          expect(filtro, startsWith('m.patrimonio_id = v_patrimonio.id'));
        }
        // o número do documento é o EFETIVO do Documento SEI (sei, com fallback ao formatado) — nunca de outro documento
        final i = _idx(norm, 'public.normalize_text(m.numero_documento) = v_numero_documento');
        expect(norm.substring(i - 120, i), contains('m.patrimonio_id = v_patrimonio.id and'));
        expect(norm, contains('if v_numero_documento is not null and exists ('));
      },
    );

    test('CONFIRMADO_SEM_INFORMACAO envia null DE PROPÓSITO; DEFINIDO envia o valor', () {
      expect(
        norm,
        contains(
          'if v_item.decisao_localizacao = \'DEFINIDO\' then v_localizacao_destino := v_item.localizacao_destino_id; else v_localizacao_destino := null; end if;',
        ),
      );
      expect(
        norm,
        contains(
          'if v_item.decisao_responsavel = \'DEFINIDO\' then v_responsavel_destino := v_item.responsavel_destino; else v_responsavel_destino := null; end if;',
        ),
      );
      expect(norm, contains('p_localizacao_destino_id => v_localizacao_destino'));
      expect(norm, contains('p_responsavel_destino => v_responsavel_destino'));
      expect(norm, contains('p_limpar_localizacao => false'));
    });

    test('cenário limpeza SEM confirmação bloqueia (P0035) e a mensagem diz que o patrimônio ficará DISPONIVEL', () {
      expect(
        norm,
        contains(
          'v_limpa_localizacao := v_localizacao_destino is null and v_patrimonio.localizacao_atual_id is not null;',
        ),
      );
      expect(
        norm,
        contains(
          'v_limpa_responsavel := v_responsavel_destino is null and v_patrimonio.responsavel_atual is not null;',
        ),
      );
      expect(
        norm,
        contains('if (v_limpa_localizacao or v_limpa_responsavel) and p_confirmar_limpeza_destino is not true then'),
      );
      final i = _idx(norm, 'A conclusão limparia %');
      final trecho = norm.substring(i, i + 520);
      expect(trecho, contains('o patrimônio ficará DISPONIVEL'));
      expect(trecho, contains('errcode = \'P0035\''));
    });

    test(
      'cenário limpeza CONFIRMADA prossegue e fica registrada no evento; sem nada a limpar não exige confirmação',
      () {
        // só exige confirmação quando há valor atual a apagar (`is not null`)
        expect(norm, contains('v_patrimonio.localizacao_atual_id is not null'));
        expect(norm, contains('v_patrimonio.responsavel_atual is not null'));
        expect(norm, contains('\'limpeza_confirmada\', (v_limpa_localizacao or v_limpa_responsavel)'));
      },
    );

    test('cenário movimentação interna: sem localização DEFINIDA não é aceito; localização igual à atual também não', () {
      expect(
        norm,
        contains(
          'if v_item.destino_setor_id = v_patrimonio.setor_atual_id then if v_item.decisao_localizacao <> \'DEFINIDO\' '
          'or v_localizacao_destino is null then',
        ),
      );
      final i = _idx(norm, 'Movimentação interna (mesmo setor) exige localização de destino DEFINIDA');
      expect(norm.substring(i, i + 220), contains('errcode = \'P0001\''));
      expect(norm, contains('if v_localizacao_destino is not distinct from v_patrimonio.localizacao_atual_id then'));
      // a regra real de registrar_movimentacao que motiva estas checagens
      final reg = _norm(_ler(_localizacoes));
      expect(reg, contains('Movimentação interna (mesmo setor) exige localizacao_destino_id'));
      expect(reg, contains('A localização de destino precisa ser diferente da localização atual'));
    });

    test('chama registrar_movimentacao (11 parâmetros vigentes) só com parâmetros que ela realmente tem', () {
      final loc = _ler(_localizacoes);
      final assinatura = RegExp(
        r'create function public\.registrar_movimentacao\(([\s\S]*?)\)\s*returns public\.movimentacoes',
      ).firstMatch(loc)!.group(1)!;
      final parametros = RegExp(
        r'^\s*(p_[a-z_]+) ',
        multiLine: true,
      ).allMatches(assinatura).map((m) => m.group(1)!).toSet();
      expect(parametros, hasLength(11));
      final chamada = RegExp(
        r'from public\.registrar_movimentacao\(([\s\S]*?)\n  \);',
      ).firstMatch(bruto.replaceAll('\r\n', '\n'))!.group(1)!;
      final enviados = RegExp(r'(p_[a-z_]+) =>').allMatches(chamada).map((m) => m.group(1)!).toList();
      expect(enviados.toSet().difference(parametros), isEmpty, reason: 'parâmetro inexistente na assinatura vigente');
      expect(enviados, hasLength(11));
      expect(norm, contains('p_numero_chamado => v_numero_chamado'));
      expect(norm, contains('p_motivo => v_motivo'));
    });

    test(
      'cenário ROLLBACK quando registrar_movimentacao falha: nada é escrito antes dela e nenhum erro é engolido',
      () {
        final chamada = _idx(norm, 'from public.registrar_movimentacao(');
        final antes = norm.substring(0, chamada);
        expect(antes, isNot(contains('insert into')));
        expect(RegExp(r'update public\.').hasMatch(antes), isFalse);
        // nem por outras vias de escrita/efeito colateral (DML dinâmico, PERFORM, advisory locks, DELETE)
        for (final efeito in ['delete ', 'perform ', 'execute ', 'pg_advisory', 'nextval', 'set_config', 'notify ']) {
          expect(antes, isNot(contains(efeito)), reason: efeito);
        }
        // o único `return` antes da chamada é o do ramo idempotente (que não escreve)
        expect(RegExp(r'\breturn\b').allMatches(antes).length, 1);
        expect(RegExp(r'\breturn\b').firstMatch(antes)!.start, greaterThan(_idx(antes, '\'ja_concluido\', true') - 40));
        expect(norm, isNot(contains('exception when')));
        expect(norm, isNot(contains('when others')));
        // toda escrita do item/documento/evento vem DEPOIS
        final depois = norm.substring(chamada);
        expect(depois, contains('update public.documentos_sei_itens set'));
        expect(depois, contains('update public.documentos_sei set'));
        expect(depois, contains('insert into public.documentos_sei_eventos'));
      },
    );

    test('nunca escreve direto em movimentacoes/patrimonios nem altera origem/destino do item', () {
      expect(norm, isNot(contains('insert into public.movimentacoes')));
      expect(norm, isNot(contains('update public.patrimonios')));
      expect(norm, isNot(contains('update public.movimentacoes')));
      expect(norm, isNot(contains('origem_setor_id =')));
      // a conclusão nunca reescreve o vínculo: nenhum UPDATE (até o `where`) menciona patrimonio_id
      for (final update in RegExp(r'update public\.[a-z_]+ set (.*?) where').allMatches(norm)) {
        expect(update.group(1), isNot(contains('patrimonio_id')), reason: 'UPDATE não pode reescrever patrimonio_id');
      }
      // o único UPDATE em itens grava apenas status e movimentacao_id
      expect(
        norm,
        contains(
          'update public.documentos_sei_itens set status = \'CONCLUIDO\', movimentacao_id = v_movimentacao.id where id = v_item.id returning * into v_item;',
        ),
      );
    });

    test(
      'evento ITEM_CONCLUIDO: item_id, autor, dados_antes/dados_depois com movimentacao_id e resultado patrimonial',
      () {
        final i = _idx(norm, 'insert into public.documentos_sei_eventos');
        final evento = norm.substring(i, _idx(norm, 'auth.uid() );', desde: i));
        expect(evento, contains('(documento_id, item_id, tipo, descricao, dados_antes, dados_depois, autor_id)'));
        expect(evento, contains('\'ITEM_CONCLUIDO\''));
        expect(evento, contains('\'movimentacao_id\', v_movimentacao.id'));
        expect(
          evento,
          contains('\'patrimonio\', jsonb_build_object( \'setor_atual_id\', v_patrimonio_depois.setor_atual_id'),
        );
        expect(evento, contains('\'item\', v_item_antes'));
        // o tipo já é aceito pelo CHECK existente — nenhuma migration de tabela necessária
        expect(_norm(_ler(_sei)), contains('\'ITEM_CONCLUIDO\''));
      },
    );

    test('retorno jsonb: ja_concluido, documento, item, movimentacao', () {
      final i = _idx(norm, '\'ja_concluido\', false');
      final retorno = norm.substring(i - 30, i + 200);
      expect(retorno, contains('\'documento\', to_jsonb(v_documento)'));
      expect(retorno, contains('\'item\', to_jsonb(v_item)'));
      expect(retorno, contains('\'movimentacao\', to_jsonb(v_movimentacao)'));
    });

    test(
      'todo campo referenciado (v_item.x, v_documento.x, v_patrimonio.x, v_movimentacao.x, m.x) existe no schema',
      () {
        final mapa = <String, Set<String>>{
          'v_item': _colunas('documentos_sei_itens'),
          'v_documento': _colunas('documentos_sei'),
          'v_patrimonio': _colunas('patrimonios'),
          'v_patrimonio_depois': _colunas('patrimonios'),
          'v_movimentacao': _colunas('movimentacoes'),
          'm': _colunas('movimentacoes'),
        };
        expect(
          mapa['v_item'],
          containsAll(['origem_setor_id', 'criado_em', 'numero_chamado_corrigido', 'decisao_responsavel']),
        );
        mapa.forEach((variavel, colunas) {
          final usados = RegExp('\\b$variavel\\.([a-z_]+)').allMatches(norm).map((m) => m.group(1)!).toSet();
          expect(usados, isNotEmpty, reason: variavel);
          expect(usados.difference(colunas), isEmpty, reason: 'coluna inexistente usada via $variavel');
        });
      },
    );

    test('códigos de erro definidos: 42501, P0001, P0002, P0010 e P0030–P0035', () {
      final codigos = RegExp('errcode = \'([A-Z0-9]{5})\'').allMatches(norm).map((m) => m.group(1)!).toSet();
      expect(codigos, {'42501', 'P0001', 'P0002', 'P0010', 'P0030', 'P0031', 'P0032', 'P0033', 'P0034', 'P0035'});
    });
  });
}
