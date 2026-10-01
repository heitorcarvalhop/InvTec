-- =============================================================================
-- PROMPT 11.4.4 — HOMOLOGAÇÃO TRANSACIONAL de public.concluir_item_documento_sei
-- (roda de verdade a RPC, mas NÃO persiste NADA: termina em ROLLBACK)
-- =============================================================================
-- STATUS: PREPARADO PARA REVISÃO — NÃO EXECUTADO por quem o escreveu.
--
-- REGRA ABSOLUTA: este arquivo NUNCA contém COMMIT. A única instrução que
-- encerra a transação é o ROLLBACK da última linha. Sem COMMIT, nada do que
-- ele cria (setores, localizações, tipo, patrimônio, documento, item, evento,
-- MOVIMENTAÇÃO) pode virar dado permanente — nem se uma assertiva passar, nem
-- se falhar (uma transação abortada não consegue commitar: um COMMIT nela vira
-- ROLLBACK). Nada aqui usa o Despacho 577, os itens dele, patrimônio existente,
-- setor/localização existente ou o documento TESTE-PROMPT1137: TODOS os objetos
-- são novos e começam por ZZHOMOLOG.
--
-- COMO USAR
--   1. Rode os BLOCOS 1 a 4 de 11_4_4_00_prerequisitos_somente_leitura.sql;
--      anote a "foto antes" (BLOCO 3) e escolha um user_id (BLOCO 2).
--   2. Troque __USER_ID_HOMOLOGACAO__ (aparece UMA vez, no PASSO 0 abaixo)
--      pelo UUID escolhido. Não altere mais nada.
--   3. No SQL Editor, com Role = postgres, cole o arquivo INTEIRO e clique em
--      Run UMA vez (BEGIN e ROLLBACK precisam estar na MESMA execução).
--   4. Depois, rode 11_4_4_99_rollback_e_verificacao.sql.
--
-- SE ALGO FALHAR NO MEIO (assertiva, erro da RPC, erro de fixture):
--   * o Postgres aborta a transação e PULA o resto do script — inclusive a
--     linha ROLLBACK final. A transação fica "aberta e abortada" (nada foi
--     confirmado, nada é visível a outras sessões). Execute IMEDIATAMENTE,
--     sozinho, numa nova execução:   ROLLBACK;
--     (está pronto no arquivo 99). Se o editor descartar a conexão, o servidor
--     também faz ROLLBACK sozinho ao fechá-la. Em ambos os casos, confira com o
--     arquivo 99 que nada ficou.
--   * a mensagem de erro começa com "HOMOLOG 11.4.4 - ASSERT FALHOU: ..." e diz
--     qual verificação falhou.
--
-- O QUE É REAL e o que é simulado: a RPC concluir_item_documento_sei e a
-- registrar_movimentacao rodam de verdade, com o papel `authenticated` e um
-- auth.uid() real (o usuário do passo 0). Fixtures são inseridos direto como
-- `postgres` (o app não tem INSERT direto — só pelas RPCs — e usar a RPC de
-- criação aqui acrescentaria evento/regras que este teste não quer misturar).
--
-- LIMITES (o ROLLBACK não desfaz): estatísticas do banco (contadores de
-- pg_stat_*, linhas mortas que o autovacuum limpa) e nenhuma sequence é usada
-- (todos os ids são gen_random_uuid()). Detalhes no relatório do PROMPT 11.4.4.
-- =============================================================================

BEGIN;

-- =============================================================================
-- PASSO 0 — usuário da homologação (ÚNICO ponto a editar)
-- =============================================================================
-- Troque o texto __USER_ID_HOMOLOGACAO__ pelo UUID de um profile ATIVO com
-- perfil ADMIN, GESTOR ou OPERADOR (BLOCO 2 do arquivo 00). Não crie usuário e
-- não invente UUID: o passo seguinte confere que ele existe e tem perfil.
select set_config('zzhomolog.user_id', '30d7f437-0b40-459f-9145-e2cc6f6808b0', true);

-- Ferramentas temporárias (somem no ROLLBACK): tabela de totais, snapshot,
-- delta e assert. Ficam no schema pg_temp — não tocam o banco de verdade.
create temp table zzh_totais (
  fase text not null,
  tabela text not null,
  total bigint not null,
  primary key (fase, tabela)
);

create function pg_temp.zzh_snapshot(p_fase text)
returns void
language plpgsql
as $f$
begin
  insert into pg_temp.zzh_totais (fase, tabela, total)
  select p_fase, v.tabela, v.total
  from (
    select 'patrimonios' as tabela, count(*) as total from public.patrimonios
    union all select 'movimentacoes', count(*) from public.movimentacoes
    union all select 'documentos_sei', count(*) from public.documentos_sei
    union all select 'documentos_sei_itens', count(*) from public.documentos_sei_itens
    union all select 'documentos_sei_eventos', count(*) from public.documentos_sei_eventos
    union all select 'setores', count(*) from public.setores
    union all select 'localizacoes', count(*) from public.localizacoes
    union all select 'tipos_patrimonio', count(*) from public.tipos_patrimonio
  ) v;
end;
$f$;

create function pg_temp.zzh_delta(p_tabela text, p_de text, p_para text)
returns bigint
language plpgsql
as $f$
declare
  v_de bigint;
  v_para bigint;
begin
  select total into v_de from pg_temp.zzh_totais where fase = p_de and tabela = p_tabela;
  select total into v_para from pg_temp.zzh_totais where fase = p_para and tabela = p_tabela;
  return v_para - v_de;
end;
$f$;

-- Falha ALTO (raise exception) quando a condição não é TRUE — inclusive NULL.
-- Nunca "engole" nada: a exceção derruba a transação, que só pode terminar em
-- ROLLBACK.
create function pg_temp.zzh_assert(p_ok boolean, p_msg text)
returns void
language plpgsql
as $f$
begin
  if p_ok is not true then
    raise exception 'HOMOLOG 11.4.4 - ASSERT FALHOU: %', p_msg using errcode = 'P0001';
  end if;
  raise notice 'HOMOLOG 11.4.4 - ok: %', p_msg;
end;
$f$;

-- =============================================================================
-- PASSO 1 — guardas (nada é escrito aqui)
-- =============================================================================
do $guardas$
declare
  v_txt text := current_setting('zzhomolog.user_id', true);
  v_user uuid;
  v_perfil text;
  v_ativo boolean;
  v_sobras bigint;
begin
  -- o placeholder é montado por concatenação para que um "substituir tudo" no
  -- editor não desarme esta guarda
  if v_txt is null or v_txt = '__USER_ID_' || 'HOMOLOGACAO__' then
    raise exception 'HOMOLOG 11.4.4 - troque __USER_ID_HOMOLOGACAO__ pelo UUID de um usuario ativo ADMIN/GESTOR/OPERADOR (BLOCO 2 do arquivo 00) e rode de novo. Nada foi escrito; execute ROLLBACK;'
      using errcode = 'P0001';
  end if;

  begin
    v_user := v_txt::uuid;
  exception when invalid_text_representation then
    raise exception 'HOMOLOG 11.4.4 - "%" nao e um UUID valido. Execute ROLLBACK;', v_txt
      using errcode = 'P0001';
  end;

  select p.perfil::text, p.ativo into v_perfil, v_ativo from public.profiles p where p.id = v_user;
  perform pg_temp.zzh_assert(v_perfil is not null, 'o usuario informado existe em public.profiles');
  perform pg_temp.zzh_assert(v_ativo is true, 'o usuario informado esta ativo');
  perform pg_temp.zzh_assert(v_perfil in ('ADMIN', 'GESTOR', 'OPERADOR'),
    format('o usuario informado tem perfil ADMIN/GESTOR/OPERADOR (tem %s)', v_perfil));

  -- o script insere fixtures direto: precisa rodar como dono/postgres
  perform pg_temp.zzh_assert(current_user not in ('anon', 'authenticated'),
    format('o SQL Editor esta com o papel %s (use postgres)', current_user));
  perform pg_temp.zzh_assert(coalesce((select rolbypassrls from pg_roles where rolname = current_user), false),
    'o papel do editor ignora RLS (necessario para inserir as fixtures)');
  perform pg_temp.zzh_assert(pg_has_role(current_user, 'authenticated', 'member'),
    'o papel do editor pode assumir authenticated (SET LOCAL ROLE)');

  -- a RPC existe, com a assinatura de 5 parametros, e authenticated executa
  perform pg_temp.zzh_assert(
    to_regprocedure('public.concluir_item_documento_sei(uuid,uuid,integer,text,boolean)') is not null,
    'public.concluir_item_documento_sei(uuid,uuid,integer,text,boolean) esta instalada');
  perform pg_temp.zzh_assert(
    has_function_privilege('authenticated', 'public.concluir_item_documento_sei(uuid,uuid,integer,text,boolean)', 'execute'),
    'authenticated tem EXECUTE na RPC');

  -- nenhuma sobra de uma tentativa anterior (os fixtures sao unicos)
  select
    (select count(*) from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-11.4.4%')
    + (select count(*) from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.4.4%')
    + (select count(*) from public.setores where nome like 'ZZHOMOLOG-11.4.4%' or sigla like 'ZZHOMOLOG-11.4.4%')
    + (select count(*) from public.tipos_patrimonio where nome like 'ZZHOMOLOG-11.4.4%')
    + (select count(*) from public.movimentacoes
        where numero_documento like 'ZZHOMOLOG-SEI-11.4.4%' or numero_chamado like 'ZZHOMOLOG-4556%')
  into v_sobras;
  perform pg_temp.zzh_assert(v_sobras = 0,
    format('nenhuma sobra ZZHOMOLOG-11.4.4 de tentativa anterior (achou %s)', v_sobras));
end;
$guardas$;

-- totais REAIS antes de qualquer fixture
select pg_temp.zzh_snapshot('1_antes');

-- =============================================================================
-- PASSO 2 — FIXTURES 100% fictícios (todos com prefixo ZZHOMOLOG)
-- =============================================================================
-- Cenário: TRANSFERENCIA entre dois setores diferentes, sem limpeza.
--   patrimônio ZZHOMOLOG-11.4.4-001: EM_USO, setor ORIGEM, localização de
--   origem, responsável de origem
--   item PENDENTE: destino = outro setor, localização DEFINIDA (do destino),
--   responsável DEFINIDO
-- Setores/localizações/tipo são criados aqui (não reaproveita nenhum real):
-- assim a RPC não toma nenhum lock em linha de dado real, exceto a FK do
-- usuário (profiles) que só leva um lock de leitura de chave.
do $fixtures$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_so uuid;  -- setor de origem
  v_sd uuid;  -- setor de destino
  v_lo uuid;  -- localização de origem (pertence ao setor de origem)
  v_ld uuid;  -- localização de destino (pertence ao setor de destino)
  v_tipo uuid;
  v_pat uuid;
  v_doc uuid;
  v_item uuid;
begin
  insert into public.setores (nome, sigla, descricao)
  values ('ZZHOMOLOG-11.4.4 SETOR ORIGEM', 'ZZHOMOLOG-11.4.4-O', 'Fixture ficticia PROMPT 11.4.4 - some no ROLLBACK')
  returning id into v_so;

  insert into public.setores (nome, sigla, descricao)
  values ('ZZHOMOLOG-11.4.4 SETOR DESTINO', 'ZZHOMOLOG-11.4.4-D', 'Fixture ficticia PROMPT 11.4.4 - some no ROLLBACK')
  returning id into v_sd;

  insert into public.localizacoes (setor_id, nome, sigla)
  values (v_so, 'ZZHOMOLOG-11.4.4 SALA ORIGEM', 'ZZHOMOLOG-11.4.4-LO')
  returning id into v_lo;

  insert into public.localizacoes (setor_id, nome, sigla)
  values (v_sd, 'ZZHOMOLOG-11.4.4 SALA DESTINO', 'ZZHOMOLOG-11.4.4-LD')
  returning id into v_ld;

  insert into public.tipos_patrimonio (nome, descricao)
  values ('ZZHOMOLOG-11.4.4 TIPO', 'Fixture ficticia PROMPT 11.4.4')
  returning id into v_tipo;

  -- patrimônio inserido DIRETO (não via cadastrar_patrimonio): assim o
  -- patrimônio nasce SEM nenhuma movimentação, e a única movimentação do teste
  -- é a criada pela RPC. status/responsável coerentes (EM_USO exige responsável).
  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id,
    localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.4.4-001', v_tipo, 'Patrimonio ficticio PROMPT 11.4.4 - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.4.4 Responsavel Origem', v_user
  )
  returning id into v_pat;

  insert into public.documentos_sei (
    numero_documento_sei, numero_documento_formatado, assunto,
    tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por
  ) values (
    'ZZHOMOLOG-SEI-11.4.4', 'ZZHOMOLOG-SEI-11.4.4/2026', 'Documento ficticio PROMPT 11.4.4',
    'TRANSFERENCIA', 'ZZHOMOLOG-11.4.4.pdf', 'zzhomolog-11-4-4-hash-ficticio', v_user
  )
  returning id into v_doc;

  -- item PENDENTE ligado ao patrimônio; número original = número do patrimônio;
  -- origem = setor atual do patrimônio; destino = outro setor; decisões
  -- DEFINIDO com valores coerentes (localização do próprio setor de destino).
  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id,
    destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao,
    responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 1, v_pat, 'ZZHOMOLOG-11.4.4-001',
    'ZZHOMOLOG-11.4.4-O', v_so,
    'ZZHOMOLOG-11.4.4-D', v_sd,
    'ZZHOMOLOG-4556', 'ZZHOMOLOG-11.4.4 NOTEBOOK',
    v_ld, 'DEFINIDO',
    'ZZHOMOLOG-11.4.4 Responsavel Destino', 'DEFINIDO'
  )
  returning id into v_item;

  perform set_config('zzhomolog.setor_origem', v_so::text, true);
  perform set_config('zzhomolog.setor_destino', v_sd::text, true);
  perform set_config('zzhomolog.loc_origem', v_lo::text, true);
  perform set_config('zzhomolog.loc_destino', v_ld::text, true);
  perform set_config('zzhomolog.pat_id', v_pat::text, true);
  perform set_config('zzhomolog.doc_id', v_doc::text, true);
  perform set_config('zzhomolog.item_id', v_item::text, true);
  perform set_config('zzhomolog.resp_origem', 'ZZHOMOLOG-11.4.4 Responsavel Origem', true);
  perform set_config('zzhomolog.resp_destino', 'ZZHOMOLOG-11.4.4 Responsavel Destino', true);

  raise notice 'HOMOLOG 11.4.4 - fixtures: patrimonio=% documento=% item=%', v_pat, v_doc, v_item;
end;
$fixtures$;

select pg_temp.zzh_snapshot('2_fixtures');

-- estado inicial dos fixtures: prova que o cenário é o desejado ANTES da RPC
do $inicial$
declare
  v_pat uuid := current_setting('zzhomolog.pat_id')::uuid;
  v_doc uuid := current_setting('zzhomolog.doc_id')::uuid;
  v_item uuid := current_setting('zzhomolog.item_id')::uuid;
  v_p public.patrimonios;
  v_i public.documentos_sei_itens;
  v_d public.documentos_sei;
begin
  select * into v_p from public.patrimonios where id = v_pat;
  select * into v_i from public.documentos_sei_itens where id = v_item;
  select * into v_d from public.documentos_sei where id = v_doc;

  perform pg_temp.zzh_assert(v_p.status = 'EM_USO' and v_p.setor_atual_id = current_setting('zzhomolog.setor_origem')::uuid
    and v_p.localizacao_atual_id = current_setting('zzhomolog.loc_origem')::uuid
    and v_p.responsavel_atual = current_setting('zzhomolog.resp_origem'),
    'inicio: patrimonio EM_USO, no setor/localizacao/responsavel de origem');
  perform pg_temp.zzh_assert((select count(*) from public.movimentacoes where patrimonio_id = v_pat) = 0,
    'inicio: patrimonio ficticio sem nenhuma movimentacao');
  perform pg_temp.zzh_assert(v_i.status = 'PENDENTE' and v_i.movimentacao_id is null,
    'inicio: item PENDENTE, sem movimentacao');
  perform pg_temp.zzh_assert(v_i.patrimonio_id = v_pat and v_i.origem_setor_id = v_p.setor_atual_id
    and v_i.destino_setor_id <> v_i.origem_setor_id,
    'inicio: item ligado ao patrimonio, origem = setor atual, destino diferente da origem');
  perform pg_temp.zzh_assert(v_i.decisao_localizacao = 'DEFINIDO' and v_i.decisao_responsavel = 'DEFINIDO',
    'inicio: decisoes DEFINIDO (nenhuma limpeza envolvida)');
  perform pg_temp.zzh_assert(v_d.versao = 1, 'inicio: documento na versao 1');

  perform pg_temp.zzh_assert(pg_temp.zzh_delta('patrimonios', '1_antes', '2_fixtures') = 1
    and pg_temp.zzh_delta('documentos_sei', '1_antes', '2_fixtures') = 1
    and pg_temp.zzh_delta('documentos_sei_itens', '1_antes', '2_fixtures') = 1
    and pg_temp.zzh_delta('setores', '1_antes', '2_fixtures') = 2
    and pg_temp.zzh_delta('localizacoes', '1_antes', '2_fixtures') = 2
    and pg_temp.zzh_delta('tipos_patrimonio', '1_antes', '2_fixtures') = 1
    and pg_temp.zzh_delta('movimentacoes', '1_antes', '2_fixtures') = 0
    and pg_temp.zzh_delta('documentos_sei_eventos', '1_antes', '2_fixtures') = 0,
    'fixtures criaram exatamente: 1 patrimonio, 1 documento, 1 item, 2 setores, 2 localizacoes, 1 tipo (0 movimentacoes, 0 eventos)');
end;
$inicial$;

-- =============================================================================
-- PASSO 3 — simular a sessão `authenticated` do usuário do PASSO 0
-- =============================================================================
-- auth.uid() (Supabase) lê o claim `sub` de request.jwt.claims (JSON) e, nas
-- versões antigas, de request.jwt.claim.sub. Setamos os dois (is_local = true:
-- valem só nesta transação). private.has_perfil() usa auth.uid() contra
-- public.profiles (ativo + perfil), sem nenhum outro estado de sessão.
select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('zzhomolog.user_id'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('zzhomolog.user_id'), true);
select set_config('request.jwt.claim.role', 'authenticated', true);

set local role authenticated;
select set_config('zzhomolog.diag_papel', current_user::text, true);
select set_config('zzhomolog.diag_uid', coalesce(auth.uid()::text, 'NULL'), true);
select set_config('zzhomolog.diag_perfil',
  coalesce(private.has_perfil('ADMIN', 'GESTOR', 'OPERADOR')::text, 'NULL'), true);
reset role;

do $diag$
begin
  perform pg_temp.zzh_assert(current_setting('zzhomolog.diag_papel') = 'authenticated',
    'SET LOCAL ROLE: a sessao simulada roda como authenticated');
  perform pg_temp.zzh_assert(current_setting('zzhomolog.diag_uid') = current_setting('zzhomolog.user_id'),
    format('auth.uid() = usuario da homologacao (viu %s)', current_setting('zzhomolog.diag_uid')));
  perform pg_temp.zzh_assert(current_setting('zzhomolog.diag_perfil') = 'true',
    'private.has_perfil(ADMIN, GESTOR, OPERADOR) = true para esse usuario');
end;
$diag$;

-- =============================================================================
-- PASSO 4 — PRIMEIRA chamada da RPC (UMA vez), como authenticated
-- =============================================================================
-- p_versao_esperada = 1 (o documento nasceu na versão 1). Sem limpeza:
-- p_confirmar_limpeza_destino = false (nada a limpar neste cenário).
set local role authenticated;
select set_config('zzhomolog.r1',
  public.concluir_item_documento_sei(
    p_documento_id => current_setting('zzhomolog.doc_id')::uuid,
    p_item_id => current_setting('zzhomolog.item_id')::uuid,
    p_versao_esperada => 1,
    p_observacao => 'ZZHOMOLOG-11.4.4 observacao de homologacao',
    p_confirmar_limpeza_destino => false
  )::text,
  true);
reset role;

select pg_temp.zzh_snapshot('3_apos_conclusao');

-- =============================================================================
-- PASSO 5 — ASSERTIVAS da primeira chamada (rodam como postgres, lendo tudo)
-- =============================================================================
do $apos_conclusao$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_doc uuid := current_setting('zzhomolog.doc_id')::uuid;
  v_item uuid := current_setting('zzhomolog.item_id')::uuid;
  v_pat uuid := current_setting('zzhomolog.pat_id')::uuid;
  v_so uuid := current_setting('zzhomolog.setor_origem')::uuid;
  v_sd uuid := current_setting('zzhomolog.setor_destino')::uuid;
  v_lo uuid := current_setting('zzhomolog.loc_origem')::uuid;
  v_ld uuid := current_setting('zzhomolog.loc_destino')::uuid;
  v_r jsonb := current_setting('zzhomolog.r1')::jsonb;
  v_qtd bigint;
  v_mov public.movimentacoes;
  v_p public.patrimonios;
  v_i public.documentos_sei_itens;
  v_d public.documentos_sei;
  v_ev public.documentos_sei_eventos;
begin
  perform pg_temp.zzh_assert(current_user not in ('anon', 'authenticated'), 'assertivas rodam como dono (postgres)');

  -- resultado devolvido pela RPC
  perform pg_temp.zzh_assert((v_r ->> 'ja_concluido')::boolean is false, '1a chamada: ja_concluido = false');

  -- movimentação: exatamente UMA, correta
  select count(*) into v_qtd from public.movimentacoes where patrimonio_id = v_pat;
  perform pg_temp.zzh_assert(v_qtd = 1, format('exatamente 1 movimentacao do patrimonio ficticio (achou %s)', v_qtd));
  select * into v_mov from public.movimentacoes where patrimonio_id = v_pat;
  perform pg_temp.zzh_assert(v_mov.tipo = 'TRANSFERENCIA', 'movimentacao: tipo = TRANSFERENCIA');
  perform pg_temp.zzh_assert(v_mov.origem_id = v_so, 'movimentacao: origem_id = setor de origem');
  perform pg_temp.zzh_assert(v_mov.destino_id = v_sd, 'movimentacao: destino_id = setor de destino');
  perform pg_temp.zzh_assert(v_mov.localizacao_origem_id = v_lo, 'movimentacao: localizacao_origem_id = sala de origem');
  perform pg_temp.zzh_assert(v_mov.localizacao_destino_id = v_ld, 'movimentacao: localizacao_destino_id = sala de destino');
  perform pg_temp.zzh_assert(v_mov.responsavel_origem = current_setting('zzhomolog.resp_origem'),
    'movimentacao: responsavel_origem = responsavel de origem');
  perform pg_temp.zzh_assert(v_mov.responsavel_destino = current_setting('zzhomolog.resp_destino'),
    'movimentacao: responsavel_destino = responsavel de destino');
  perform pg_temp.zzh_assert(v_mov.realizado_por = v_user, 'movimentacao: realizado_por = usuario da homologacao');
  perform pg_temp.zzh_assert(v_mov.numero_documento = 'ZZHOMOLOG-SEI-11.4.4', 'movimentacao: numero_documento = numero do documento SEI');
  perform pg_temp.zzh_assert(v_mov.numero_chamado = 'ZZHOMOLOG-4556', 'movimentacao: numero_chamado = chamado do item');
  perform pg_temp.zzh_assert(v_mov.motivo = 'Despacho SEI ZZHOMOLOG-SEI-11.4.4/2026', 'movimentacao: motivo = Despacho SEI <numero formatado>');
  perform pg_temp.zzh_assert(v_mov.observacao = 'ZZHOMOLOG-11.4.4 observacao de homologacao', 'movimentacao: observacao repassada');
  perform pg_temp.zzh_assert(v_mov.data_movimentacao <= clock_timestamp(), 'movimentacao: data nao esta no futuro');
  perform pg_temp.zzh_assert((v_r -> 'movimentacao' ->> 'id')::uuid = v_mov.id, 'resultado da RPC: movimentacao.id = movimentacao gravada');

  -- patrimônio
  select * into v_p from public.patrimonios where id = v_pat;
  perform pg_temp.zzh_assert(v_p.setor_atual_id = v_sd, 'patrimonio: setor_atual_id = destino');
  perform pg_temp.zzh_assert(v_p.localizacao_atual_id = v_ld, 'patrimonio: localizacao_atual_id = sala de destino');
  perform pg_temp.zzh_assert(v_p.responsavel_atual = current_setting('zzhomolog.resp_destino'), 'patrimonio: responsavel_atual = responsavel de destino');
  perform pg_temp.zzh_assert(v_p.status = 'EM_USO', 'patrimonio: status EM_USO (responsavel definido)');

  -- item
  select * into v_i from public.documentos_sei_itens where id = v_item;
  perform pg_temp.zzh_assert(v_i.status = 'CONCLUIDO', 'item: status = CONCLUIDO');
  perform pg_temp.zzh_assert(v_i.movimentacao_id = v_mov.id, 'item: movimentacao_id = movimentacao criada');
  perform pg_temp.zzh_assert(v_i.patrimonio_id = v_pat, 'item: continua ligado ao patrimonio ficticio');
  perform pg_temp.zzh_assert(v_r -> 'item' ->> 'status' = 'CONCLUIDO'
    and (v_r -> 'item' ->> 'movimentacao_id')::uuid = v_mov.id,
    'resultado da RPC: item CONCLUIDO com a movimentacao_id correta');

  -- documento: versão incrementada
  select * into v_d from public.documentos_sei where id = v_doc;
  perform pg_temp.zzh_assert(v_d.versao = 2, format('documento: versao 1 -> 2 (esta em %s)', v_d.versao));
  perform pg_temp.zzh_assert((v_r -> 'documento' ->> 'versao')::int = 2, 'resultado da RPC: documento.versao = 2');
  perform pg_temp.zzh_assert((select situacao from public.documentos_sei_com_situacao where id = v_doc) = 'CONCLUIDO',
    'view documentos_sei_com_situacao: situacao = CONCLUIDO (unico item concluido)');

  -- evento ITEM_CONCLUIDO: único, com autor e dados corretos
  select count(*) into v_qtd from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_qtd = 1, format('exatamente 1 evento ITEM_CONCLUIDO (achou %s)', v_qtd));
  select count(*) into v_qtd from public.documentos_sei_eventos where documento_id = v_doc;
  perform pg_temp.zzh_assert(v_qtd = 1, format('o documento ficticio tem so esse evento (achou %s)', v_qtd));
  select * into v_ev from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_ev.autor_id = v_user, 'evento: autor_id = usuario da homologacao');
  perform pg_temp.zzh_assert(v_ev.item_id = v_item, 'evento: item_id = item concluido');
  perform pg_temp.zzh_assert((v_ev.dados_depois ->> 'movimentacao_id')::uuid = v_mov.id, 'evento: dados_depois.movimentacao_id = movimentacao criada');
  perform pg_temp.zzh_assert(v_ev.dados_depois ->> 'numero_patrimonio_efetivo' = 'ZZHOMOLOG-11.4.4-001', 'evento: numero_patrimonio_efetivo');
  perform pg_temp.zzh_assert((v_ev.dados_depois -> 'movimentacao' ->> 'origem_id')::uuid = v_so
    and (v_ev.dados_depois -> 'movimentacao' ->> 'destino_id')::uuid = v_sd,
    'evento: movimentacao origem -> destino');
  perform pg_temp.zzh_assert((v_ev.dados_antes -> 'patrimonio' ->> 'setor_atual_id')::uuid = v_so
    and (v_ev.dados_depois -> 'patrimonio' ->> 'setor_atual_id')::uuid = v_sd,
    'evento: patrimonio antes (origem) e depois (destino)');
  perform pg_temp.zzh_assert(v_ev.dados_depois ->> 'limpeza_confirmada' = 'false', 'evento: limpeza_confirmada = false (nao houve limpeza)');

  -- totais: a 1a chamada criou exatamente 1 movimentação e 1 evento
  perform pg_temp.zzh_assert(pg_temp.zzh_delta('movimentacoes', '2_fixtures', '3_apos_conclusao') = 1
    and pg_temp.zzh_delta('documentos_sei_eventos', '2_fixtures', '3_apos_conclusao') = 1
    and pg_temp.zzh_delta('patrimonios', '2_fixtures', '3_apos_conclusao') = 0
    and pg_temp.zzh_delta('documentos_sei', '2_fixtures', '3_apos_conclusao') = 0
    and pg_temp.zzh_delta('documentos_sei_itens', '2_fixtures', '3_apos_conclusao') = 0
    and pg_temp.zzh_delta('setores', '2_fixtures', '3_apos_conclusao') = 0
    and pg_temp.zzh_delta('localizacoes', '2_fixtures', '3_apos_conclusao') = 0,
    'a 1a chamada criou exatamente +1 movimentacao e +1 evento (nenhuma outra tabela cresceu)');

  perform set_config('zzhomolog.mov_id', v_mov.id::text, true);
end;
$apos_conclusao$;

-- =============================================================================
-- PASSO 6 — IDEMPOTÊNCIA: MESMA chamada, mesmos ids, mesma versão esperada (1)
-- =============================================================================
-- Simula o clique duplo / a repetição após timeout: o cliente ainda envia a
-- versão ANTIGA (1; o documento já está na 2). A RPC precisa devolver
-- ja_concluido = true SEM conflito de versão e SEM escrever nada.
set local role authenticated;
select set_config('zzhomolog.r2',
  public.concluir_item_documento_sei(
    p_documento_id => current_setting('zzhomolog.doc_id')::uuid,
    p_item_id => current_setting('zzhomolog.item_id')::uuid,
    p_versao_esperada => 1,
    p_observacao => 'ZZHOMOLOG-11.4.4 observacao de homologacao',
    p_confirmar_limpeza_destino => false
  )::text,
  true);
reset role;

select pg_temp.zzh_snapshot('4_apos_retry');

do $apos_retry$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_doc uuid := current_setting('zzhomolog.doc_id')::uuid;
  v_item uuid := current_setting('zzhomolog.item_id')::uuid;
  v_pat uuid := current_setting('zzhomolog.pat_id')::uuid;
  v_sd uuid := current_setting('zzhomolog.setor_destino')::uuid;
  v_ld uuid := current_setting('zzhomolog.loc_destino')::uuid;
  v_mov_id uuid := current_setting('zzhomolog.mov_id')::uuid;
  v_r2 jsonb := current_setting('zzhomolog.r2')::jsonb;
  v_qtd bigint;
  v_p public.patrimonios;
  v_d public.documentos_sei;
  v_alterou bigint;
begin
  perform pg_temp.zzh_assert(current_user not in ('anon', 'authenticated'), 'assertivas do retry rodam como dono (postgres)');

  -- resultado do retry
  perform pg_temp.zzh_assert((v_r2 ->> 'ja_concluido')::boolean is true, 'retry: ja_concluido = true');
  perform pg_temp.zzh_assert((v_r2 -> 'movimentacao' ->> 'id')::uuid = v_mov_id, 'retry: devolve a MESMA movimentacao da 1a chamada');
  perform pg_temp.zzh_assert(v_r2 -> 'item' ->> 'status' = 'CONCLUIDO'
    and (v_r2 -> 'item' ->> 'movimentacao_id')::uuid = v_mov_id,
    'retry: item CONCLUIDO com a mesma movimentacao_id');
  perform pg_temp.zzh_assert((v_r2 -> 'documento' ->> 'versao')::int = 2, 'retry: documento continua na versao 2 (sem conflito de versao, sem novo incremento)');

  -- nada novo foi escrito
  select count(*) into v_qtd from public.movimentacoes where patrimonio_id = v_pat;
  perform pg_temp.zzh_assert(v_qtd = 1, format('retry: continua exatamente 1 movimentacao do patrimonio (achou %s)', v_qtd));
  select count(*) into v_qtd from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_qtd = 1, format('retry: continua exatamente 1 evento ITEM_CONCLUIDO (achou %s)', v_qtd));
  select count(*) into v_qtd from public.documentos_sei_eventos where documento_id = v_doc;
  perform pg_temp.zzh_assert(v_qtd = 1, format('retry: nenhum evento novo de qualquer tipo (achou %s)', v_qtd));

  select * into v_d from public.documentos_sei where id = v_doc;
  perform pg_temp.zzh_assert(v_d.versao = 2, 'retry: versao do documento inalterada (2)');

  select * into v_p from public.patrimonios where id = v_pat;
  perform pg_temp.zzh_assert(v_p.setor_atual_id = v_sd and v_p.localizacao_atual_id = v_ld
    and v_p.responsavel_atual = current_setting('zzhomolog.resp_destino') and v_p.status = 'EM_USO',
    'retry: patrimonio inalterado (destino, sala, responsavel, EM_USO)');
  perform pg_temp.zzh_assert((select realizado_por from public.movimentacoes where id = v_mov_id) = v_user,
    'retry: a movimentacao continua sendo do usuario da homologacao');

  -- nenhuma tabela mudou de tamanho entre a 1a chamada e o retry
  select count(*) into v_alterou
  from pg_temp.zzh_totais a
  join pg_temp.zzh_totais b on b.tabela = a.tabela and b.fase = '4_apos_retry'
  where a.fase = '3_apos_conclusao' and a.total <> b.total;
  perform pg_temp.zzh_assert(v_alterou = 0, format('retry: nenhuma das 8 tabelas mudou de tamanho (%s mudaram)', v_alterou));

  raise notice 'HOMOLOG 11.4.4 - TODAS AS ASSERTIVAS PASSARAM. O ROLLBACK final descarta tudo.';
end;
$apos_retry$;

-- =============================================================================
-- RELATÓRIO (ainda dentro da transação; some no ROLLBACK). Se o editor mostrar
-- só o resultado da última instrução, o sinal de sucesso é: nenhuma mensagem
-- "ASSERT FALHOU" e o ROLLBACK abaixo executou.
-- =============================================================================
select
  tabela,
  max(total) filter (where fase = '1_antes') as antes,
  max(total) filter (where fase = '2_fixtures') as apos_fixtures,
  max(total) filter (where fase = '3_apos_conclusao') as apos_conclusao,
  max(total) filter (where fase = '4_apos_retry') as apos_retry
from pg_temp.zzh_totais
group by tabela
order by tabela;

-- =============================================================================
-- FIM — descarta TUDO (fixtures, movimentação, evento, versão). NUNCA COMMIT.
-- =============================================================================
ROLLBACK;
