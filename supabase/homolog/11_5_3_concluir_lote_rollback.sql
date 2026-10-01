-- =============================================================================
-- PROMPT 11.5.3 — HOMOLOGAÇÃO TRANSACIONAL de
-- public.concluir_itens_documento_sei_lote (roda de verdade a RPC de LOTE e a
-- RPC individual, mas NÃO persiste NADA: termina em ROLLBACK)
-- =============================================================================
-- STATUS: PREPARADO PARA REVISÃO — NÃO EXECUTADO por quem o escreveu.
--
-- REGRA ABSOLUTA: um único BEGIN (logo abaixo) e um único ROLLBACK (última
-- linha do arquivo). Este arquivo NUNCA contém COMMIT. Sem COMMIT, nada do
-- que ele cria (setores, localizações, tipo, patrimônios, documentos, itens,
-- eventos, MOVIMENTAÇÕES, registros de lote) pode virar dado permanente —
-- nem se uma assertiva passar, nem se falhar (uma transação abortada não
-- consegue commitar: um COMMIT nela vira ROLLBACK). Nada aqui usa o Despacho
-- 577, os 33 itens dele, nenhum patrimônio existente, nenhum setor/
-- localização existente, nem o documento fictício já encerrado: TODOS os
-- objetos são novos e começam por ZZHOMOLOG-11.5.3 (prefixo NUNCA usado por
-- 11.4.4 nem por qualquer homologação anterior — "não reaproveitar fixtures
-- ou lote_id de homologações anteriores").
--
-- COMO USAR
--   1. Rode os BLOCOS 1 a 4 de 11_5_3_00_prerequisitos_somente_leitura.sql;
--      anote a "foto antes" (BLOCO 3) e escolha um user_id (BLOCO 2).
--   2. Troque __USER_ID_HOMOLOGACAO__ (aparece UMA vez, no PASSO 0 abaixo)
--      pelo UUID escolhido. Não altere mais nada.
--   3. No SQL Editor, com Role = postgres, cole o arquivo INTEIRO e clique em
--      Run UMA vez (BEGIN e ROLLBACK precisam estar na MESMA execução).
--   4. Depois, rode 11_5_3_99_verificacao_pos_rollback.sql.
--
-- SE ALGO FALHAR NO MEIO, FORA de um bloco de cenário com EXCEPTION (ver
-- abaixo) — por exemplo, uma assertiva de guarda ou de fixture:
--   * o Postgres aborta a transação e PULA o resto do script — inclusive a
--     linha ROLLBACK final. A transação fica "aberta e abortada". Execute
--     IMEDIATAMENTE, sozinho, numa nova execução:   ROLLBACK;
--     (está pronto no arquivo 99, BLOCO A). Confira com o arquivo 99 que
--     nada ficou.
--   * a mensagem de erro começa com "HOMOLOG 11.5.3 - ASSERT FALHOU: ..." e
--     diz qual verificação falhou.
--
-- SOBRE OS BLOCOS QUE ESPERAM ERRO (cenários B, C, D, E e F, abaixo): cada um
-- usa um bloco `DO $$ ... EXCEPTION WHEN sqlstate '...' THEN ... END; $$`
-- para CAPTURAR o erro esperado da RPC e continuar o script (sem isso, o erro
-- abortaria a transação inteira e nenhum cenário seguinte rodaria). Dois
-- cuidados, seguidos à risca em TODOS esses blocos:
--   (a) NUNCA mascarar falha: o `WHEN sqlstate` captura SÓ o código exato
--       esperado; qualquer outro erro cai em `WHEN OTHERS` e é relançado como
--       um `ASSERT FALHOU` (nunca silenciado). Se a chamada tiver sucesso
--       (não deveria), um `raise exception` explícito logo depois do
--       `perform` também vira um `ASSERT FALHOU` — nenhum dos dois desvios
--       passa despercebido.
--   (b) NUNCA reverter fixture por engano: um bloco `EXCEPTION` em PL/pgSQL
--       estabelece um SAVEPOINT implícito no INÍCIO do bloco, e capturar o
--       erro faz ROLLBACK TO SAVEPOINT — desfazendo qualquer escrita feita
--       DENTRO do bloco (é assim que a RPC que falhou deixa de ter efeito,
--       mesmo já tendo processado um item, ver cenário F). Por isso as
--       FIXTURES de cada cenário são sempre criadas numa instrução anterior,
--       SEPARADA, fora do bloco `EXCEPTION` — nunca dentro dele — para não
--       serem desfeitas junto com o erro capturado.
--
-- O QUE É REAL e o que é simulado: as duas RPCs (lote e individual) e
-- `registrar_movimentacao` rodam de verdade, com o papel `authenticated` e um
-- `auth.uid()` real (o usuário do passo 0). Fixtures são inseridos direto
-- como `postgres` (o app não tem INSERT direto — só pelas RPCs — e usar as
-- RPCs de criação aqui acrescentaria evento/regras que este teste não quer
-- misturar).
--
-- MAPA DOS 8 CENÁRIOS PEDIDOS (PROMPT 11.5.3, seção 2):
--   1. primeira conclusão de lote (≥2 patrimônios)      -> CENÁRIO A, chamada 1
--   2. retry com mesmo lote_id/parâmetros                -> CENÁRIO A, chamada 2
--   3. mesmo lote_id, seleção diferente                  -> CENÁRIO B (P0037)
--   4. mesmo lote_id, observação diferente                -> CENÁRIO C (P0037)
--   5. mesmo lote_id, confirmação de limpeza diferente    -> CENÁRIO D (P0037)
--   6. item já concluído por outra operação               -> CENÁRIO E (P0036)
--   7. falha no 2º item após o 1º ser processado           -> CENÁRIO F (P0035)
--   8. RPC individual preservada                           -> CENÁRIO G
--
-- LIMITES (o ROLLBACK não desfaz): estatísticas do banco (contadores de
-- pg_stat_*, linhas mortas que o autovacuum limpa) e nenhuma sequence é usada
-- (todos os ids são gen_random_uuid()). Detalhes no relatório do PROMPT 11.5.3.
-- =============================================================================

BEGIN;

-- =============================================================================
-- PASSO 0 — usuário da homologação (ÚNICO ponto a editar)
-- =============================================================================
-- Troque o texto __USER_ID_HOMOLOGACAO__ pelo UUID de um profile ATIVO com
-- perfil ADMIN, GESTOR ou OPERADOR (BLOCO 2 do arquivo 00). Não crie usuário e
-- não invente UUID: o passo seguinte confere que ele existe e tem perfil.
select set_config('zzhomolog.user_id', '30d7f437-0b40-459f-9145-e2cc6f6808b0', true);

-- =============================================================================
-- PASSO 1 — ferramentas temporárias (somem no ROLLBACK): snapshot de totais e
-- assert. Ficam no schema pg_temp — não tocam o banco de verdade.
-- =============================================================================
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
    union all select 'documentos_sei_lotes_conclusao', count(*) from public.documentos_sei_lotes_conclusao
    union all select 'setores', count(*) from public.setores
    union all select 'localizacoes', count(*) from public.localizacoes
    union all select 'tipos_patrimonio', count(*) from public.tipos_patrimonio
  ) v;
end;
$f$;

-- Falha ALTO (raise exception) quando a condição não é TRUE — inclusive NULL.
-- Nunca "engole" nada: a exceção derruba a transação (ou o bloco EXCEPTION
-- mais próximo, quando existir — ver cabeçalho), nunca é ignorada em silêncio.
create function pg_temp.zzh_assert(p_ok boolean, p_msg text)
returns void
language plpgsql
as $f$
begin
  if p_ok is not true then
    raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: %', p_msg using errcode = 'P0001';
  end if;
  raise notice 'HOMOLOG 11.5.3 - ok: %', p_msg;
end;
$f$;

-- =============================================================================
-- PASSO 2 — guardas (nada é escrito aqui)
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
    raise exception 'HOMOLOG 11.5.3 - troque __USER_ID_HOMOLOGACAO__ pelo UUID de um usuario ativo ADMIN/GESTOR/OPERADOR (BLOCO 2 do arquivo 00) e rode de novo. Nada foi escrito; execute ROLLBACK;'
      using errcode = 'P0001';
  end if;

  begin
    v_user := v_txt::uuid;
  exception when invalid_text_representation then
    raise exception 'HOMOLOG 11.5.3 - "%" nao e um UUID valido. Execute ROLLBACK;', v_txt
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

  -- as DUAS RPCs existem, com as assinaturas certas, e authenticated executa
  perform pg_temp.zzh_assert(
    to_regprocedure('public.concluir_item_documento_sei(uuid,uuid,integer,text,boolean)') is not null,
    'public.concluir_item_documento_sei(uuid,uuid,integer,text,boolean) esta instalada — 5 parametros, INALTERADA');
  perform pg_temp.zzh_assert(
    has_function_privilege('authenticated', 'public.concluir_item_documento_sei(uuid,uuid,integer,text,boolean)', 'execute'),
    'authenticated tem EXECUTE na RPC individual');
  perform pg_temp.zzh_assert(
    to_regprocedure('public.concluir_itens_documento_sei_lote(uuid,uuid[],integer,uuid,text,boolean)') is not null,
    'public.concluir_itens_documento_sei_lote(uuid,uuid[],integer,uuid,text,boolean) esta instalada — 6 parametros');
  perform pg_temp.zzh_assert(
    has_function_privilege(
      'authenticated', 'public.concluir_itens_documento_sei_lote(uuid,uuid[],integer,uuid,text,boolean)', 'execute'
    ),
    'authenticated tem EXECUTE na RPC de lote');
  perform pg_temp.zzh_assert(
    to_regclass('public.documentos_sei_lotes_conclusao') is not null,
    'a tabela de controle documentos_sei_lotes_conclusao existe');

  -- nenhuma sobra de uma tentativa anterior desta etapa (os fixtures são únicos)
  select
    (select count(*) from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-11.5.3%')
    + (select count(*) from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.5.3%')
    + (select count(*) from public.setores where nome like 'ZZHOMOLOG-11.5.3%' or sigla like 'ZZHOMOLOG-11.5.3%')
    + (select count(*) from public.tipos_patrimonio where nome like 'ZZHOMOLOG-11.5.3%')
    + (select count(*) from public.movimentacoes
        where numero_documento like 'ZZHOMOLOG-SEI-11.5.3%' or numero_chamado like 'ZZHOMOLOG-4556-11.5.3%')
  into v_sobras;
  perform pg_temp.zzh_assert(v_sobras = 0,
    format('nenhuma sobra ZZHOMOLOG-11.5.3 de tentativa anterior (achou %s)', v_sobras));
end;
$guardas$;

-- totais REAIS antes de qualquer fixture
select pg_temp.zzh_snapshot('1_inicio');

-- =============================================================================
-- PASSO 3 — fixtures COMPARTILHADAS: 2 setores fictícios, 1 localização em
-- cada, 1 tipo — reaproveitados por TODOS os cenários abaixo (só leitura
-- depois de criados; nenhum cenário os altera). Tudo com prefixo
-- ZZHOMOLOG-11.5.3, nunca usado antes.
-- =============================================================================
do $fixtures_compartilhadas$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_so uuid;
  v_sd uuid;
  v_lo uuid;
  v_ld uuid;
  v_tipo uuid;
begin
  insert into public.setores (nome, sigla, descricao)
  values ('ZZHOMOLOG-11.5.3 SETOR ORIGEM', 'ZZHOMOLOG-11.5.3-O', 'Fixture ficticia PROMPT 11.5.3 - some no ROLLBACK')
  returning id into v_so;

  insert into public.setores (nome, sigla, descricao)
  values ('ZZHOMOLOG-11.5.3 SETOR DESTINO', 'ZZHOMOLOG-11.5.3-D', 'Fixture ficticia PROMPT 11.5.3 - some no ROLLBACK')
  returning id into v_sd;

  insert into public.localizacoes (setor_id, nome, sigla)
  values (v_so, 'ZZHOMOLOG-11.5.3 SALA ORIGEM', 'ZZHOMOLOG-11.5.3-LO')
  returning id into v_lo;

  insert into public.localizacoes (setor_id, nome, sigla)
  values (v_sd, 'ZZHOMOLOG-11.5.3 SALA DESTINO', 'ZZHOMOLOG-11.5.3-LD')
  returning id into v_ld;

  insert into public.tipos_patrimonio (nome, descricao)
  values ('ZZHOMOLOG-11.5.3 TIPO', 'Fixture ficticia PROMPT 11.5.3')
  returning id into v_tipo;

  perform set_config('zzhomolog.setor_origem', v_so::text, true);
  perform set_config('zzhomolog.setor_destino', v_sd::text, true);
  perform set_config('zzhomolog.loc_origem', v_lo::text, true);
  perform set_config('zzhomolog.loc_destino', v_ld::text, true);
  perform set_config('zzhomolog.tipo', v_tipo::text, true);

  raise notice 'HOMOLOG 11.5.3 - fixtures compartilhadas: setor_origem=% setor_destino=%', v_so, v_sd;
end;
$fixtures_compartilhadas$;

-- =============================================================================
-- PASSO 4 — simular a sessão `authenticated` do usuário do PASSO 0, e
-- verificar perfil/auth.uid ANTES de qualquer cenário de escrita.
-- =============================================================================
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
    'private.has_perfil(ADMIN, GESTOR, OPERADOR) = true para esse usuario — verificado ANTES de qualquer escrita');
end;
$diag$;

-- =============================================================================
-- CENÁRIO A — cenários 1 e 2 do prompt: primeira conclusão de um lote com 2
-- patrimônios, e retry com o MESMO lote_id e os MESMOS parâmetros.
-- Documento com 3 itens: a1/a2 são concluídos pelo lote; a3 fica PENDENTE, de
-- propósito, para o cenário B (seleção diferente) reaproveitar sem precisar
-- de fixtures novas.
-- =============================================================================
do $fixtures_a$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_so uuid := current_setting('zzhomolog.setor_origem')::uuid;
  v_sd uuid := current_setting('zzhomolog.setor_destino')::uuid;
  v_lo uuid := current_setting('zzhomolog.loc_origem')::uuid;
  v_ld uuid := current_setting('zzhomolog.loc_destino')::uuid;
  v_tipo uuid := current_setting('zzhomolog.tipo')::uuid;
  v_doc uuid;
  v_pat1 uuid;
  v_pat2 uuid;
  v_pat3 uuid;
  v_item1 uuid;
  v_item2 uuid;
  v_item3 uuid;
begin
  insert into public.documentos_sei (
    numero_documento_sei, numero_documento_formatado, assunto,
    tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por
  ) values (
    'ZZHOMOLOG-SEI-11.5.3-A', 'ZZHOMOLOG-SEI-11.5.3-A/2026', 'Documento fictício PROMPT 11.5.3 (cenário A)',
    'TRANSFERENCIA', 'ZZHOMOLOG-11.5.3-A.pdf', 'zzhomolog-11-5-3-a-hash-ficticio', v_user
  )
  returning id into v_doc;

  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.5.3-001', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (A1) - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.5.3 Responsavel A1 Origem', v_user
  )
  returning id into v_pat1;

  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.5.3-002', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (A2) - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.5.3 Responsavel A2 Origem', v_user
  )
  returning id into v_pat2;

  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.5.3-003', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (A3) - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.5.3 Responsavel A3 Origem', v_user
  )
  returning id into v_pat3;

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 1, v_pat1, 'ZZHOMOLOG-11.5.3-001',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-A1', 'ZZHOMOLOG-11.5.3 NOTEBOOK A1',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel A1 Destino', 'DEFINIDO'
  )
  returning id into v_item1;

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 2, v_pat2, 'ZZHOMOLOG-11.5.3-002',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-A2', 'ZZHOMOLOG-11.5.3 MONITOR A2',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel A2 Destino', 'DEFINIDO'
  )
  returning id into v_item2;

  -- item 3: fica PENDENTE de propósito (nunca entra na chamada 1/2 do
  -- cenário A) — só é usado pelo CENÁRIO B, para provar "seleção diferente".
  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 3, v_pat3, 'ZZHOMOLOG-11.5.3-003',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-A3', 'ZZHOMOLOG-11.5.3 TECLADO A3',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel A3 Destino', 'DEFINIDO'
  )
  returning id into v_item3;

  perform set_config('zzhomolog.a_doc', v_doc::text, true);
  perform set_config('zzhomolog.a_pat1', v_pat1::text, true);
  perform set_config('zzhomolog.a_pat2', v_pat2::text, true);
  perform set_config('zzhomolog.a_pat3', v_pat3::text, true);
  perform set_config('zzhomolog.a_item1', v_item1::text, true);
  perform set_config('zzhomolog.a_item2', v_item2::text, true);
  perform set_config('zzhomolog.a_item3', v_item3::text, true);
  -- lote_id NOVO, gerado uma única vez para todo o cenário A/B/C/D — nunca
  -- reaproveitado de uma homologação anterior.
  perform set_config('zzhomolog.lote_a', gen_random_uuid()::text, true);
  perform set_config('zzhomolog.a_observacao', 'ZZHOMOLOG-11.5.3 observação do lote A', true);

  raise notice 'HOMOLOG 11.5.3 - cenário A: documento=% item1=% item2=% item3=% lote_id=%',
    v_doc, v_item1, v_item2, v_item3, current_setting('zzhomolog.lote_a');
end;
$fixtures_a$;

select pg_temp.zzh_snapshot('2_apos_fixtures_a');

-- ---- CENÁRIO A / chamada 1 — cenário 1 do prompt: primeira conclusão -------
set local role authenticated;
select set_config('zzhomolog.a_r1',
  public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.a_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.a_item1')::uuid, current_setting('zzhomolog.a_item2')::uuid],
    p_versao_esperada => 1,
    p_lote_id => current_setting('zzhomolog.lote_a')::uuid,
    p_observacao => current_setting('zzhomolog.a_observacao'),
    p_confirmar_limpeza_destino => false
  )::text,
  true);
reset role;

select pg_temp.zzh_snapshot('3_apos_a_chamada1');

do $apos_a_chamada1$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_doc uuid := current_setting('zzhomolog.a_doc')::uuid;
  v_pat1 uuid := current_setting('zzhomolog.a_pat1')::uuid;
  v_pat2 uuid := current_setting('zzhomolog.a_pat2')::uuid;
  v_r1 jsonb := current_setting('zzhomolog.a_r1')::jsonb;
  v_qtd_mov bigint;
  v_qtd_evt bigint;
  v_qtd_lote bigint;
  v_i1 public.documentos_sei_itens;
  v_i2 public.documentos_sei_itens;
  v_i3 public.documentos_sei_itens;
  v_d public.documentos_sei;
begin
  perform pg_temp.zzh_assert(current_user not in ('anon', 'authenticated'), 'assertivas rodam como dono (postgres)');

  perform pg_temp.zzh_assert((v_r1 ->> 'ja_executado')::boolean is false, 'CENÁRIO 1: ja_executado = false na 1ª conclusão');

  select count(*) into v_qtd_mov from public.movimentacoes where patrimonio_id in (v_pat1, v_pat2);
  perform pg_temp.zzh_assert(v_qtd_mov = 2, format('CENÁRIO 1: exatamente 2 movimentações (achou %s)', v_qtd_mov));

  select count(*) into v_qtd_evt
  from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_qtd_evt = 2, format('CENÁRIO 1: exatamente 2 eventos ITEM_CONCLUIDO (achou %s)', v_qtd_evt));

  select count(*) into v_qtd_lote
  from public.documentos_sei_lotes_conclusao where lote_id = current_setting('zzhomolog.lote_a')::uuid;
  perform pg_temp.zzh_assert(v_qtd_lote = 1, format('CENÁRIO 1: exatamente 1 registro de lote (achou %s)', v_qtd_lote));

  select * into v_i1 from public.documentos_sei_itens where id = current_setting('zzhomolog.a_item1')::uuid;
  select * into v_i2 from public.documentos_sei_itens where id = current_setting('zzhomolog.a_item2')::uuid;
  select * into v_i3 from public.documentos_sei_itens where id = current_setting('zzhomolog.a_item3')::uuid;
  perform pg_temp.zzh_assert(v_i1.status = 'CONCLUIDO' and v_i2.status = 'CONCLUIDO' and v_i1.movimentacao_id is not null
    and v_i2.movimentacao_id is not null, 'CENÁRIO 1: item1 e item2 CONCLUIDOS, com movimentacao_id');
  perform pg_temp.zzh_assert(v_i3.status = 'PENDENTE',
    'CENÁRIO 1: item3 continua PENDENTE (nunca fez parte da seleção do lote)');

  select * into v_d from public.documentos_sei where id = v_doc;
  perform pg_temp.zzh_assert(v_d.versao = 3,
    format('CENÁRIO 1: versão do documento avançou 1 -> 3 (2 itens concluídos, um incremento por item; está em %s)', v_d.versao));

  perform set_config('zzhomolog.a_mov1', v_i1.movimentacao_id::text, true);
  perform set_config('zzhomolog.a_mov2', v_i2.movimentacao_id::text, true);
end;
$apos_a_chamada1$;

-- ---- CENÁRIO A / chamada 2 — cenário 2 do prompt: retry idêntico ----------
set local role authenticated;
select set_config('zzhomolog.a_r2',
  public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.a_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.a_item1')::uuid, current_setting('zzhomolog.a_item2')::uuid],
    p_versao_esperada => 1,
    p_lote_id => current_setting('zzhomolog.lote_a')::uuid,
    p_observacao => current_setting('zzhomolog.a_observacao'),
    p_confirmar_limpeza_destino => false
  )::text,
  true);
reset role;

select pg_temp.zzh_snapshot('4_apos_a_retry');

do $apos_a_retry$
declare
  v_doc uuid := current_setting('zzhomolog.a_doc')::uuid;
  v_pat1 uuid := current_setting('zzhomolog.a_pat1')::uuid;
  v_pat2 uuid := current_setting('zzhomolog.a_pat2')::uuid;
  v_r2 jsonb := current_setting('zzhomolog.a_r2')::jsonb;
  v_qtd_mov bigint;
  v_qtd_evt bigint;
  v_qtd_lote bigint;
  v_d public.documentos_sei;
  v_alterou bigint;
begin
  perform pg_temp.zzh_assert((v_r2 ->> 'ja_executado')::boolean is true, 'CENÁRIO 2: retry devolve ja_executado = true');

  select count(*) into v_qtd_mov from public.movimentacoes where patrimonio_id in (v_pat1, v_pat2);
  perform pg_temp.zzh_assert(v_qtd_mov = 2, format('CENÁRIO 2: continuam exatamente 2 movimentações (achou %s)', v_qtd_mov));

  select count(*) into v_qtd_evt
  from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_qtd_evt = 2, format('CENÁRIO 2: continuam exatamente 2 eventos (achou %s)', v_qtd_evt));

  select count(*) into v_qtd_lote
  from public.documentos_sei_lotes_conclusao where lote_id = current_setting('zzhomolog.lote_a')::uuid;
  perform pg_temp.zzh_assert(v_qtd_lote = 1, format('CENÁRIO 2: continua exatamente 1 registro de lote (achou %s)', v_qtd_lote));

  select * into v_d from public.documentos_sei where id = v_doc;
  perform pg_temp.zzh_assert(v_d.versao = 3, format('CENÁRIO 2: versão do documento NÃO incrementou de novo (está em %s)', v_d.versao));

  -- nenhuma das 9 tabelas mudou de tamanho entre a chamada 1 e o retry
  select count(*) into v_alterou
  from pg_temp.zzh_totais a
  join pg_temp.zzh_totais b on b.tabela = a.tabela and b.fase = '4_apos_a_retry'
  where a.fase = '3_apos_a_chamada1' and a.total <> b.total;
  perform pg_temp.zzh_assert(v_alterou = 0, format('CENÁRIO 2: nenhuma tabela mudou de tamanho no retry (%s mudaram)', v_alterou));
end;
$apos_a_retry$;

-- =============================================================================
-- CENÁRIO B — cenário 3 do prompt: mesmo lote_id, SELEÇÃO diferente (troca
-- item2 por item3, que ainda está PENDENTE) -> P0037, sem nenhuma escrita.
-- =============================================================================
do $cenario_b$
begin
  set local role authenticated;
  perform public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.a_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.a_item1')::uuid, current_setting('zzhomolog.a_item3')::uuid],
    p_versao_esperada => 1,
    p_lote_id => current_setting('zzhomolog.lote_a')::uuid,
    p_observacao => current_setting('zzhomolog.a_observacao'),
    p_confirmar_limpeza_destino => false
  );
  reset role;
  raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 3 (seleção diferente) deveria falhar com P0037, mas teve sucesso';
exception
  when sqlstate 'P0037' then
    reset role;
    raise notice 'HOMOLOG 11.5.3 - ok: CENÁRIO 3 recebeu P0037 (seleção diferente) como esperado';
  when others then
    reset role;
    raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 3 esperava P0037, recebeu SQLSTATE=% (%)', sqlstate, sqlerrm;
end;
$cenario_b$;

select pg_temp.zzh_snapshot('5_apos_b');

do $apos_b$
declare
  v_alterou bigint;
  v_item3 public.documentos_sei_itens;
begin
  select count(*) into v_alterou
  from pg_temp.zzh_totais a
  join pg_temp.zzh_totais b on b.tabela = a.tabela and b.fase = '5_apos_b'
  where a.fase = '4_apos_a_retry' and a.total <> b.total;
  perform pg_temp.zzh_assert(v_alterou = 0, format('CENÁRIO 3: nenhuma tabela mudou de tamanho (%s mudaram)', v_alterou));

  select * into v_item3 from public.documentos_sei_itens where id = current_setting('zzhomolog.a_item3')::uuid;
  perform pg_temp.zzh_assert(v_item3.status = 'PENDENTE', 'CENÁRIO 3: item3 continua PENDENTE (nunca chegou a ser travado/tocado)');
end;
$apos_b$;

-- =============================================================================
-- CENÁRIO C — cenário 4 do prompt: mesmo lote_id, OBSERVAÇÃO diferente (itens
-- e confirmação de limpeza iguais aos da chamada original) -> P0037.
-- =============================================================================
do $cenario_c$
begin
  set local role authenticated;
  perform public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.a_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.a_item1')::uuid, current_setting('zzhomolog.a_item2')::uuid],
    p_versao_esperada => 1,
    p_lote_id => current_setting('zzhomolog.lote_a')::uuid,
    p_observacao => 'ZZHOMOLOG-11.5.3 observação DIFERENTE da original',
    p_confirmar_limpeza_destino => false
  );
  reset role;
  raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 4 (observação diferente) deveria falhar com P0037, mas teve sucesso';
exception
  when sqlstate 'P0037' then
    reset role;
    raise notice 'HOMOLOG 11.5.3 - ok: CENÁRIO 4 recebeu P0037 (observação diferente) como esperado';
  when others then
    reset role;
    raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 4 esperava P0037, recebeu SQLSTATE=% (%)', sqlstate, sqlerrm;
end;
$cenario_c$;

select pg_temp.zzh_snapshot('6_apos_c');

do $apos_c$
declare
  v_alterou bigint;
begin
  select count(*) into v_alterou
  from pg_temp.zzh_totais a
  join pg_temp.zzh_totais b on b.tabela = a.tabela and b.fase = '6_apos_c'
  where a.fase = '5_apos_b' and a.total <> b.total;
  perform pg_temp.zzh_assert(v_alterou = 0, format('CENÁRIO 4: nenhuma tabela mudou de tamanho (%s mudaram)', v_alterou));
end;
$apos_c$;

-- =============================================================================
-- CENÁRIO D — cenário 5 do prompt: mesmo lote_id, CONFIRMAÇÃO DE LIMPEZA
-- diferente (itens e observação iguais aos da chamada original) -> P0037.
-- =============================================================================
do $cenario_d$
begin
  set local role authenticated;
  perform public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.a_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.a_item1')::uuid, current_setting('zzhomolog.a_item2')::uuid],
    p_versao_esperada => 1,
    p_lote_id => current_setting('zzhomolog.lote_a')::uuid,
    p_observacao => current_setting('zzhomolog.a_observacao'),
    p_confirmar_limpeza_destino => true
  );
  reset role;
  raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 5 (confirmação de limpeza diferente) deveria falhar com P0037, mas teve sucesso';
exception
  when sqlstate 'P0037' then
    reset role;
    raise notice 'HOMOLOG 11.5.3 - ok: CENÁRIO 5 recebeu P0037 (confirmação de limpeza diferente) como esperado';
  when others then
    reset role;
    raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 5 esperava P0037, recebeu SQLSTATE=% (%)', sqlstate, sqlerrm;
end;
$cenario_d$;

select pg_temp.zzh_snapshot('7_apos_d');

do $apos_d$
declare
  v_alterou bigint;
begin
  select count(*) into v_alterou
  from pg_temp.zzh_totais a
  join pg_temp.zzh_totais b on b.tabela = a.tabela and b.fase = '7_apos_d'
  where a.fase = '6_apos_c' and a.total <> b.total;
  perform pg_temp.zzh_assert(v_alterou = 0, format('CENÁRIO 5: nenhuma tabela mudou de tamanho (%s mudaram)', v_alterou));
end;
$apos_d$;

-- =============================================================================
-- CENÁRIO E — cenário 6 do prompt: um NOVO lote (lote_id nunca usado antes)
-- tenta incluir um item que já foi concluído por OUTRA operação (uma
-- conclusão INDIVIDUAL, chamada direto — simula outra sessão/tela) -> P0036.
-- =============================================================================
do $fixtures_e$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_so uuid := current_setting('zzhomolog.setor_origem')::uuid;
  v_sd uuid := current_setting('zzhomolog.setor_destino')::uuid;
  v_lo uuid := current_setting('zzhomolog.loc_origem')::uuid;
  v_ld uuid := current_setting('zzhomolog.loc_destino')::uuid;
  v_tipo uuid := current_setting('zzhomolog.tipo')::uuid;
  v_doc uuid;
  v_pat1 uuid;
  v_pat2 uuid;
  v_item1 uuid;
  v_item2 uuid;
begin
  insert into public.documentos_sei (
    numero_documento_sei, numero_documento_formatado, assunto,
    tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por
  ) values (
    'ZZHOMOLOG-SEI-11.5.3-E', 'ZZHOMOLOG-SEI-11.5.3-E/2026', 'Documento fictício PROMPT 11.5.3 (cenário E)',
    'TRANSFERENCIA', 'ZZHOMOLOG-11.5.3-E.pdf', 'zzhomolog-11-5-3-e-hash-ficticio', v_user
  )
  returning id into v_doc;

  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.5.3-004', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (E1) - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.5.3 Responsavel E1 Origem', v_user
  )
  returning id into v_pat1;

  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.5.3-005', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (E2) - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.5.3 Responsavel E2 Origem', v_user
  )
  returning id into v_pat2;

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 1, v_pat1, 'ZZHOMOLOG-11.5.3-004',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-E1', 'ZZHOMOLOG-11.5.3 NOTEBOOK E1',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel E1 Destino', 'DEFINIDO'
  )
  returning id into v_item1;

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 2, v_pat2, 'ZZHOMOLOG-11.5.3-005',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-E2', 'ZZHOMOLOG-11.5.3 MONITOR E2',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel E2 Destino', 'DEFINIDO'
  )
  returning id into v_item2;

  perform set_config('zzhomolog.e_doc', v_doc::text, true);
  perform set_config('zzhomolog.e_pat1', v_pat1::text, true);
  perform set_config('zzhomolog.e_item1', v_item1::text, true);
  perform set_config('zzhomolog.e_item2', v_item2::text, true);
  perform set_config('zzhomolog.lote_e', gen_random_uuid()::text, true);

  raise notice 'HOMOLOG 11.5.3 - cenário E: documento=% item1=% item2=%', v_doc, v_item1, v_item2;
end;
$fixtures_e$;

-- item1 é concluído INDIVIDUALMENTE (fora de qualquer lote) — simula "outra
-- operação" já ter concluído este item antes do lote tentar incluí-lo.
set local role authenticated;
select set_config('zzhomolog.e_r_individual',
  public.concluir_item_documento_sei(
    current_setting('zzhomolog.e_doc')::uuid,
    current_setting('zzhomolog.e_item1')::uuid,
    1,
    'ZZHOMOLOG-11.5.3 conclusão individual prévia (cenário E)',
    false
  )::text,
  true);
reset role;

select pg_temp.zzh_snapshot('8_apos_e_individual');

do $apos_e_individual$
declare
  v_i1 public.documentos_sei_itens;
begin
  select * into v_i1 from public.documentos_sei_itens where id = current_setting('zzhomolog.e_item1')::uuid;
  perform pg_temp.zzh_assert(v_i1.status = 'CONCLUIDO' and v_i1.movimentacao_id is not null,
    'CENÁRIO 6 (preparo): item1 concluído INDIVIDUALMENTE antes de qualquer lote');
end;
$apos_e_individual$;

-- agora um lote NOVO (lote_id nunca usado) tenta incluir item1 (já
-- CONCLUIDO por fora) + item2 (ainda PENDENTE) -> P0036.
do $cenario_e$
begin
  set local role authenticated;
  perform public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.e_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.e_item1')::uuid, current_setting('zzhomolog.e_item2')::uuid],
    p_versao_esperada => 2, -- o documento já foi para a versão 2 pela conclusão individual do item1
    p_lote_id => current_setting('zzhomolog.lote_e')::uuid,
    p_observacao => 'ZZHOMOLOG-11.5.3 tentativa de lote sobre item já concluído (cenário E)',
    p_confirmar_limpeza_destino => false
  );
  reset role;
  raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 6 (item já concluído por outra operação) deveria falhar com P0036, mas teve sucesso';
exception
  when sqlstate 'P0036' then
    reset role;
    raise notice 'HOMOLOG 11.5.3 - ok: CENÁRIO 6 recebeu P0036 (item já concluído por outra operação) como esperado';
  when others then
    reset role;
    raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 6 esperava P0036, recebeu SQLSTATE=% (%)', sqlstate, sqlerrm;
end;
$cenario_e$;

select pg_temp.zzh_snapshot('9_apos_e');

do $apos_e$
declare
  v_pat1 uuid := current_setting('zzhomolog.e_pat1')::uuid;
  v_i2 public.documentos_sei_itens;
  v_qtd_mov bigint;
  v_qtd_lote bigint;
begin
  select * into v_i2 from public.documentos_sei_itens where id = current_setting('zzhomolog.e_item2')::uuid;
  perform pg_temp.zzh_assert(v_i2.status = 'PENDENTE',
    'CENÁRIO 6: item2 continua PENDENTE (o lote falhou antes de sequer entrar no laço de conclusão)');

  select count(*) into v_qtd_mov from public.movimentacoes where patrimonio_id = v_pat1;
  perform pg_temp.zzh_assert(v_qtd_mov = 1,
    format('CENÁRIO 6: item1 continua com exatamente 1 movimentação (a da conclusão individual prévia; achou %s)', v_qtd_mov));

  select count(*) into v_qtd_lote
  from public.documentos_sei_lotes_conclusao where lote_id = current_setting('zzhomolog.lote_e')::uuid;
  perform pg_temp.zzh_assert(v_qtd_lote = 0, 'CENÁRIO 6: nenhum registro de lote foi criado para a tentativa fracassada');
end;
$apos_e$;

-- =============================================================================
-- CENÁRIO F — cenário 7 do prompt: ATOMICIDADE. Um lote com 2 itens: f1 é
-- válido (concluiria sem problema); f2 exige confirmação de limpeza que o
-- lote NÃO envia (p_confirmar_limpeza_destino = false) — isso só é detectado
-- DENTRO de concluir_item_documento_sei (P0035), depois que o laço já
-- processou o outro item.
--
-- PROMPT 11.5.3.1 — ORDEM GARANTIDA (não mais aleatória): a RPC de lote
-- processa os itens em `order by i.patrimonio_id, i.id` (ver
-- 20260928100000_add_concluir_itens_documento_sei_lote.sql). Antes de
-- qualquer INSERT, geramos DOIS UUIDs exclusivos para esta fixture
-- (`gen_random_uuid()`, nunca reaproveitados de outro cenário) e atribuímos
-- explicitamente: o MENOR vira o id de F1 (válido), o MAIOR vira o id de F2
-- (exige limpeza) — o INSERT de `patrimonios` aceita `id` explícito no lugar
-- do default. Isso garante, por construção, que F1 é SEMPRE o primeiro item
-- do laço e F2 é SEMPRE o segundo — nunca depende de sorte na geração
-- default do UUID. Uma assertiva logo abaixo confirma F1.patrimonio_id <
-- F2.patrimonio_id antes de qualquer chamada à RPC.
-- =============================================================================
do $fixtures_f$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_so uuid := current_setting('zzhomolog.setor_origem')::uuid;
  v_sd uuid := current_setting('zzhomolog.setor_destino')::uuid;
  v_lo uuid := current_setting('zzhomolog.loc_origem')::uuid;
  v_ld uuid := current_setting('zzhomolog.loc_destino')::uuid;
  v_tipo uuid := current_setting('zzhomolog.tipo')::uuid;
  v_doc uuid;
  v_pat1 uuid;
  v_pat2 uuid;
  v_item1 uuid;
  v_item2 uuid;
  v_gerado_a uuid;
  v_gerado_b uuid;
begin
  insert into public.documentos_sei (
    numero_documento_sei, numero_documento_formatado, assunto,
    tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por
  ) values (
    'ZZHOMOLOG-SEI-11.5.3-F', 'ZZHOMOLOG-SEI-11.5.3-F/2026', 'Documento fictício PROMPT 11.5.3 (cenário F)',
    'TRANSFERENCIA', 'ZZHOMOLOG-11.5.3-F.pdf', 'zzhomolog-11-5-3-f-hash-ficticio', v_user
  )
  returning id into v_doc;

  -- gera 2 UUIDs EXCLUSIVOS desta fixture e ordena ANTES de qualquer INSERT
  -- (regenera no improvável caso de colisão — 1 em 2^122 — só por rigor).
  v_gerado_a := gen_random_uuid();
  v_gerado_b := gen_random_uuid();
  while v_gerado_a = v_gerado_b loop
    v_gerado_b := gen_random_uuid();
  end loop;
  if v_gerado_a < v_gerado_b then
    v_pat1 := v_gerado_a; -- F1 (válido): sempre o MENOR
    v_pat2 := v_gerado_b; -- F2 (exige limpeza): sempre o MAIOR
  else
    v_pat1 := v_gerado_b;
    v_pat2 := v_gerado_a;
  end if;
  perform pg_temp.zzh_assert(v_pat1 < v_pat2,
    'CENÁRIO 7 (setup): F1.patrimonio_id < F2.patrimonio_id — ordem do laço garantida ANTES de qualquer INSERT');

  -- f1: válido, sem limpeza nenhuma (destino DEFINIDO nos dois campos)
  insert into public.patrimonios (
    id, numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    v_pat1, 'ZZHOMOLOG-11.5.3-006', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (F1, válido, UUID menor) - some no ROLLBACK',
    'EM_USO', v_so, v_lo, 'ZZHOMOLOG-11.5.3 Responsavel F1 Origem', v_user
  );

  -- f2: TEM localização e responsável atuais -> concluir sem confirmar a
  -- limpeza (destino CONFIRMADO_SEM_INFORMACAO nos dois campos) dispara P0035
  insert into public.patrimonios (
    id, numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    v_pat2, 'ZZHOMOLOG-11.5.3-007', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (F2, exige limpeza, UUID maior) - some no ROLLBACK',
    'EM_USO', v_so, v_lo, 'ZZHOMOLOG-11.5.3 Responsavel F2 Origem', v_user
  );

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 1, v_pat1, 'ZZHOMOLOG-11.5.3-006',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-F1', 'ZZHOMOLOG-11.5.3 NOTEBOOK F1',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel F1 Destino', 'DEFINIDO'
  )
  returning id into v_item1;

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 2, v_pat2, 'ZZHOMOLOG-11.5.3-007',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-F2', 'ZZHOMOLOG-11.5.3 MONITOR F2',
    -- 'sem informação' DE PROPÓSITO nos dois campos: o patrimônio TEM
    -- localização/responsável atuais (acima) -> exige confirmar a limpeza
    null, 'CONFIRMADO_SEM_INFORMACAO', null, 'CONFIRMADO_SEM_INFORMACAO'
  )
  returning id into v_item2;

  perform set_config('zzhomolog.f_doc', v_doc::text, true);
  perform set_config('zzhomolog.f_pat1', v_pat1::text, true);
  perform set_config('zzhomolog.f_pat2', v_pat2::text, true);
  perform set_config('zzhomolog.f_item1', v_item1::text, true);
  perform set_config('zzhomolog.f_item2', v_item2::text, true);
  perform set_config('zzhomolog.lote_f', gen_random_uuid()::text, true);

  raise notice 'HOMOLOG 11.5.3 - cenário F: documento=% item1(válido, patrimonio=%, MENOR)=% item2(exige limpeza, patrimonio=%, MAIOR)=%',
    v_doc, v_pat1, v_item1, v_pat2, v_item2;
end;
$fixtures_f$;

select pg_temp.zzh_snapshot('10_apos_fixtures_f');

do $cenario_f$
begin
  set local role authenticated;
  -- p_confirmar_limpeza_destino => false: como F1.patrimonio_id < F2.
  -- patrimonio_id (garantido no setup acima), o laço da RPC PRECISA
  -- processar F1 primeiro — ele é concluído normalmente (registrar_
  -- movimentacao, item -> CONCLUIDO, evento ITEM_CONCLUIDO, tudo dentro
  -- desta mesma transação) — só então o laço chega a F2, que dispara P0035.
  -- O erro derruba TUDO, inclusive o que F1 já tinha feito.
  perform public.concluir_itens_documento_sei_lote(
    p_documento_id => current_setting('zzhomolog.f_doc')::uuid,
    p_item_ids => array[current_setting('zzhomolog.f_item1')::uuid, current_setting('zzhomolog.f_item2')::uuid],
    p_versao_esperada => 1,
    p_lote_id => current_setting('zzhomolog.lote_f')::uuid,
    p_observacao => 'ZZHOMOLOG-11.5.3 tentativa de lote com item inválido (cenário F)',
    p_confirmar_limpeza_destino => false
  );
  reset role;
  raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 7 (item inválido no lote) deveria falhar com P0035, mas teve sucesso';
exception
  when sqlstate 'P0035' then
    reset role;
    raise notice 'HOMOLOG 11.5.3 - ok: CENÁRIO 7 recebeu P0035 (limpeza não confirmada no 2º item) como esperado';
  when others then
    reset role;
    raise exception 'HOMOLOG 11.5.3 - ASSERT FALHOU: CENÁRIO 7 esperava P0035, recebeu SQLSTATE=% (%)', sqlstate, sqlerrm;
end;
$cenario_f$;

select pg_temp.zzh_snapshot('11_apos_f');

do $apos_f$
declare
  v_doc uuid := current_setting('zzhomolog.f_doc')::uuid;
  v_pat1 uuid := current_setting('zzhomolog.f_pat1')::uuid;
  v_pat2 uuid := current_setting('zzhomolog.f_pat2')::uuid;
  v_i1 public.documentos_sei_itens;
  v_i2 public.documentos_sei_itens;
  v_d public.documentos_sei;
  v_qtd_mov bigint;
  v_qtd_evt bigint;
  v_qtd_lote bigint;
begin
  -- ATOMICIDADE: F1.patrimonio_id < F2.patrimonio_id é GARANTIDO desde o
  -- setup (não mais por sorte de UUID aleatório) — logo o laço da RPC
  -- OBRIGATORIAMENTE processou F1 (o item válido) com sucesso ANTES de
  -- chegar a F2 e falhar com P0035. As asserções abaixo provam que, mesmo
  -- assim, NENHUM efeito de F1 (o que já tinha sido processado) sobreviveu
  -- — nem dele, nem de F2.
  select * into v_i1 from public.documentos_sei_itens where id = current_setting('zzhomolog.f_item1')::uuid;
  select * into v_i2 from public.documentos_sei_itens where id = current_setting('zzhomolog.f_item2')::uuid;
  perform pg_temp.zzh_assert(v_i1.status = 'PENDENTE' and v_i1.movimentacao_id is null,
    'CENÁRIO 7 (atomicidade): item1 (válido, processado PRIMEIRO) continua PENDENTE, sem movimentacao_id — revertido');
  perform pg_temp.zzh_assert(v_i2.status = 'PENDENTE' and v_i2.movimentacao_id is null,
    'CENÁRIO 7 (atomicidade): item2 (inválido, processado SEGUNDO) continua PENDENTE, sem movimentacao_id');

  -- os dois continuam pertencendo EXCLUSIVAMENTE ao documento fictício F —
  -- a tentativa fracassada não reatribuiu nem corrompeu o vínculo item/documento
  perform pg_temp.zzh_assert(v_i1.documento_id = v_doc and v_i2.documento_id = v_doc,
    'CENÁRIO 7: item1 e item2 continuam pertencendo exclusivamente ao documento fictício F');

  select count(*) into v_qtd_mov from public.movimentacoes where patrimonio_id in (v_pat1, v_pat2);
  perform pg_temp.zzh_assert(v_qtd_mov = 0,
    format('CENÁRIO 7 (atomicidade): NENHUMA movimentação para f1 ou f2 (achou %s)', v_qtd_mov));

  select count(*) into v_qtd_evt
  from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_qtd_evt = 0,
    format('CENÁRIO 7 (atomicidade): NENHUM evento ITEM_CONCLUIDO para este documento (achou %s)', v_qtd_evt));

  select * into v_d from public.documentos_sei where id = v_doc;
  perform pg_temp.zzh_assert(v_d.versao = 1,
    format('CENÁRIO 7 (atomicidade): versão do documento continua 1 — nenhum incremento sobreviveu (está em %s)', v_d.versao));

  select count(*) into v_qtd_lote
  from public.documentos_sei_lotes_conclusao where lote_id = current_setting('zzhomolog.lote_f')::uuid;
  perform pg_temp.zzh_assert(v_qtd_lote = 0, 'CENÁRIO 7 (atomicidade): nenhum registro de lote foi criado para a tentativa fracassada');
end;
$apos_f$;

-- =============================================================================
-- CENÁRIO G — cenário 8 do prompt: a RPC INDIVIDUAL continua funcionando,
-- sozinha, do mesmo jeito que no PROMPT 11.4.4 — prova de que a migration do
-- lote não quebrou/alterou o comportamento dela. (Repetição ENXUTA: a
-- homologação completa da individual já foi feita no PROMPT 11.4.4; aqui só
-- se confirma que ela SEGUE funcionando depois da migration nova.)
-- =============================================================================
do $fixtures_g$
declare
  v_user uuid := current_setting('zzhomolog.user_id')::uuid;
  v_so uuid := current_setting('zzhomolog.setor_origem')::uuid;
  v_sd uuid := current_setting('zzhomolog.setor_destino')::uuid;
  v_lo uuid := current_setting('zzhomolog.loc_origem')::uuid;
  v_ld uuid := current_setting('zzhomolog.loc_destino')::uuid;
  v_tipo uuid := current_setting('zzhomolog.tipo')::uuid;
  v_doc uuid;
  v_pat uuid;
  v_item uuid;
begin
  insert into public.documentos_sei (
    numero_documento_sei, numero_documento_formatado, assunto,
    tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por
  ) values (
    'ZZHOMOLOG-SEI-11.5.3-G', 'ZZHOMOLOG-SEI-11.5.3-G/2026', 'Documento fictício PROMPT 11.5.3 (cenário G)',
    'TRANSFERENCIA', 'ZZHOMOLOG-11.5.3-G.pdf', 'zzhomolog-11-5-3-g-hash-ficticio', v_user
  )
  returning id into v_doc;

  insert into public.patrimonios (
    numero_patrimonio, tipo_id, descricao, status, setor_atual_id, localizacao_atual_id, responsavel_atual, criado_por
  ) values (
    'ZZHOMOLOG-11.5.3-008', v_tipo, 'Patrimônio fictício PROMPT 11.5.3 (G1) - some no ROLLBACK', 'EM_USO', v_so,
    v_lo, 'ZZHOMOLOG-11.5.3 Responsavel G1 Origem', v_user
  )
  returning id into v_pat;

  insert into public.documentos_sei_itens (
    documento_id, linha, patrimonio_id, numero_patrimonio_original,
    origem_texto_original, origem_setor_id, destino_texto_original, destino_setor_id,
    numero_chamado_original, equipamento_texto_original,
    localizacao_destino_id, decisao_localizacao, responsavel_destino, decisao_responsavel
  ) values (
    v_doc, 1, v_pat, 'ZZHOMOLOG-11.5.3-008',
    'ZZHOMOLOG-11.5.3-O', v_so, 'ZZHOMOLOG-11.5.3-D', v_sd,
    'ZZHOMOLOG-4556-11.5.3-G1', 'ZZHOMOLOG-11.5.3 NOTEBOOK G1',
    v_ld, 'DEFINIDO', 'ZZHOMOLOG-11.5.3 Responsavel G1 Destino', 'DEFINIDO'
  )
  returning id into v_item;

  perform set_config('zzhomolog.g_doc', v_doc::text, true);
  perform set_config('zzhomolog.g_pat', v_pat::text, true);
  perform set_config('zzhomolog.g_item', v_item::text, true);

  raise notice 'HOMOLOG 11.5.3 - cenário G: documento=% item=%', v_doc, v_item;
end;
$fixtures_g$;

-- chamada DIRETA à RPC individual — nunca passa pela função de lote
set local role authenticated;
select set_config('zzhomolog.g_r',
  public.concluir_item_documento_sei(
    current_setting('zzhomolog.g_doc')::uuid,
    current_setting('zzhomolog.g_item')::uuid,
    1,
    'ZZHOMOLOG-11.5.3 observação (cenário G, RPC individual isolada)',
    false
  )::text,
  true);
reset role;

select pg_temp.zzh_snapshot('12_apos_g');

do $apos_g$
declare
  v_doc uuid := current_setting('zzhomolog.g_doc')::uuid;
  v_pat uuid := current_setting('zzhomolog.g_pat')::uuid;
  v_r jsonb := current_setting('zzhomolog.g_r')::jsonb;
  v_i public.documentos_sei_itens;
  v_d public.documentos_sei;
  v_qtd_mov bigint;
  v_qtd_evt bigint;
begin
  perform pg_temp.zzh_assert((v_r ->> 'ja_concluido')::boolean is false, 'CENÁRIO 8: RPC individual devolve ja_concluido = false');

  select * into v_i from public.documentos_sei_itens where id = current_setting('zzhomolog.g_item')::uuid;
  perform pg_temp.zzh_assert(v_i.status = 'CONCLUIDO' and v_i.movimentacao_id is not null,
    'CENÁRIO 8: item concluído normalmente pela RPC individual (assinatura/comportamento preservados)');

  select count(*) into v_qtd_mov from public.movimentacoes where patrimonio_id = v_pat;
  perform pg_temp.zzh_assert(v_qtd_mov = 1, format('CENÁRIO 8: exatamente 1 movimentação (achou %s)', v_qtd_mov));

  select count(*) into v_qtd_evt from public.documentos_sei_eventos where documento_id = v_doc and tipo = 'ITEM_CONCLUIDO';
  perform pg_temp.zzh_assert(v_qtd_evt = 1, format('CENÁRIO 8: exatamente 1 evento ITEM_CONCLUIDO (achou %s)', v_qtd_evt));

  select * into v_d from public.documentos_sei where id = v_doc;
  perform pg_temp.zzh_assert(v_d.versao = 2, format('CENÁRIO 8: versão do documento 1 -> 2 (está em %s)', v_d.versao));

  -- esta conclusão foi INDIVIDUAL: não pode existir nenhum registro de lote
  -- associado a este documento
  perform pg_temp.zzh_assert(
    not exists (select 1 from public.documentos_sei_lotes_conclusao where documento_id = v_doc),
    'CENÁRIO 8: nenhum registro de lote é criado por uma conclusão individual');

  raise notice 'HOMOLOG 11.5.3 - TODOS OS 8 CENÁRIOS PASSARAM. O ROLLBACK final descarta tudo.';
end;
$apos_g$;

-- =============================================================================
-- RELATÓRIO FINAL (ainda dentro da transação; some no ROLLBACK) — compara as
-- contagens do INÍCIO com as de AGORA (antes do ROLLBACK), só para conferência
-- visual de quanto cada fase acrescentou.
-- =============================================================================
select pg_temp.zzh_snapshot('13_fim_antes_do_rollback');

select
  tabela,
  max(total) filter (where fase = '1_inicio') as inicio,
  max(total) filter (where fase = '3_apos_a_chamada1') as apos_cenario_a_chamada1,
  max(total) filter (where fase = '4_apos_a_retry') as apos_cenario_a_retry,
  max(total) filter (where fase = '9_apos_e') as apos_cenario_e,
  max(total) filter (where fase = '11_apos_f') as apos_cenario_f,
  max(total) filter (where fase = '12_apos_g') as apos_cenario_g,
  max(total) filter (where fase = '13_fim_antes_do_rollback') as fim_antes_do_rollback
from pg_temp.zzh_totais
group by tabela
order by tabela;

-- =============================================================================
-- FIM — descarta TUDO (as 4 fixtures de documento/itens/patrimônios, as 3
-- movimentações reais criadas — A1/A2/G1 —, os 3 eventos, os setores/
-- localizações/tipo compartilhados, e o único registro de lote gravado).
-- NUNCA COMMIT.
-- =============================================================================
ROLLBACK;
