-- =============================================================================
-- PROMPT 11.3.4 — Roteiro de testes SEQUENCIAIS (uma única conexão) da
-- migration de Documentos SEI, contra o projeto de HOMOLOGAÇÃO.
--
-- SÓ RODAR DEPOIS DE, NESTA ORDEM (PROMPT 11.3.4.1):
--   1. `00_check_target_not_producao.sh env/homologacao.env` (Git Bash) OU
--      `00_check_target_not_producao.ps1 -HomologEnvFile env\homologacao.env`
--      (PowerShell) ter impresso "LIBERADO", incluindo a confirmação
--      visual do ref do Dashboard;
--   2. As 4 migrations terem sido aplicadas, NESTA ORDEM, neste projeto:
--        20260910120000_initial_schema.sql
--        20260911130000_update_tipos_patrimonio_catalog.sql
--        20260914140000_add_localizacoes.sql
--        20260921170000_add_documentos_sei.sql
--   3. `01_fixtures_homologacao.sql` ter rodado por completo (setores,
--      localizações, os 5 usuários de teste já criados no Auth E
--      promovidos/deixados como no PASSO 2 daquele arquivo, patrimônios);
--   4. Colar este SQL na MESMA aba do Dashboard cujo ref você confirmou no
--      passo 1 — o script de guarda no terminal NÃO protege sozinho um SQL
--      colado numa aba diferente/antiga do navegador.
--
-- Cada bloco imprime `NOTICE: OK - <descrição>` em caso de sucesso, ou
-- interrompe com `ERROR: FALHA - <descrição>`. Rode do início ao fim; se
-- algo falhar, reporte a última linha "OK" impressa.
--
-- O QUE ESTE ARQUIVO NÃO TESTA: concorrência real (duas conexões
-- independentes) — ver `03_concorrencia_sessaoA.sql` /
-- `03_concorrencia_sessaoB.sql`. Uma sequência de chamadas, mesmo trocando
-- de role no meio, NUNCA prova ausência de corrida — só comportamento
-- funcional single-session.
--
-- DADOS: tudo criado aqui já existe via fixtures (ZZ_HOMOLOG_*/ZZHOMOLOG-)
-- ou é criado dentro deste próprio arquivo com o mesmo prefixo. Nenhuma
-- chamada a `registrar_movimentacao` acontece de verdade neste arquivo,
-- exceto onde EXPLICITAMENTE marcado como "SIMULAÇÃO DE TESTE" (PARTE G),
-- que usa INSERT direto como dono do banco — nunca a RPC real, nunca
-- roteado pelo app.
-- =============================================================================

-- =============================================================================
-- PARTE A — SANITY CHECK: fixtures e objetos da migration existem
-- =============================================================================
do $$
begin
  if (select count(*) from public.setores where sigla like 'ZZH%') < 4 then
    raise exception 'FALHA - SETUP: setores fictícios não encontrados — rode 01_fixtures_homologacao.sql primeiro';
  end if;
  if (select count(*) from public.profiles where email like 'zzhomolog.%@invtec.test' and ativo) < 3 then
    raise exception 'FALHA - SETUP: usuários de teste ADMIN/GESTOR/OPERADOR/CONSULTA não encontrados ativos — confira o PASSO 2 de 01_fixtures_homologacao.sql';
  end if;
  if (select count(*) from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-%') < 5 then
    raise exception 'FALHA - SETUP: patrimônios fictícios não encontrados — rode 01_fixtures_homologacao.sql primeiro';
  end if;
  if to_regclass('public.documentos_sei') is null then
    raise exception 'FALHA - SETUP: tabela documentos_sei não existe — a migration 20260921170000 não foi aplicada';
  end if;
  raise notice 'OK - SETUP: fixtures e schema de Documentos SEI presentes';
end $$;

-- =============================================================================
-- PARTE B — CRIAÇÃO DE DOCUMENTO PENDENTE (como ADMIN)
-- =============================================================================
do $$
declare v_admin uuid;
begin
  select id into v_admin from public.profiles where email = 'zzhomolog.admin@invtec.test';
  perform set_config('request.jwt.claim.sub', v_admin::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, false);
end $$;
set role authenticated;

do $$
declare
  v_qtd_patrimonios_antes integer;
  v_qtd_movimentacoes_antes integer;
  v_qtd_patrimonios_depois integer;
  v_qtd_movimentacoes_depois integer;
  v_doc public.documentos_sei;
  v_pat1 uuid;
  v_pat2 uuid;
  v_getec uuid;
  v_geasi uuid;
begin
  select count(*) into v_qtd_patrimonios_antes from public.patrimonios;
  select count(*) into v_qtd_movimentacoes_antes from public.movimentacoes;

  select id into v_pat1 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001';
  select id into v_pat2 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000002';
  select id into v_getec from public.setores where sigla = 'ZZHGETEC';
  select id into v_geasi from public.setores where sigla = 'ZZHGEASI';

  select public.criar_documento_sei_pendente(
    p_tipo_operacao_pretendida := 'TRANSFERENCIA',
    p_nome_arquivo := 'zz_homolog_despacho.pdf',
    p_hash_sha256 := 'zz-homolog-hash-b',
    p_itens := jsonb_build_array(
      jsonb_build_object('linha', 1, 'patrimonio_id', v_pat1, 'origem_setor_id', v_getec, 'destino_setor_id', v_geasi),
      jsonb_build_object('linha', 2, 'patrimonio_id', v_pat2, 'origem_setor_id', v_getec, 'destino_setor_id', v_geasi)
    ),
    p_numero_documento_sei := 'ZZHOMOLOG-SEI-0001',
    p_numero_processo := null
  ) into v_doc;

  perform set_config('zz.doc_b_id', v_doc.id::text, false);

  if v_doc.versao <> 1 then
    raise exception 'FALHA - PARTE B: documento criado sem versao=1 (veio %)', v_doc.versao;
  end if;
  if (select count(*) from public.documentos_sei_itens where documento_id = v_doc.id and status = 'PENDENTE') <> 2 then
    raise exception 'FALHA - PARTE B: os 2 itens não nasceram PENDENTE';
  end if;

  select count(*) into v_qtd_patrimonios_depois from public.patrimonios;
  select count(*) into v_qtd_movimentacoes_depois from public.movimentacoes;
  if v_qtd_patrimonios_depois <> v_qtd_patrimonios_antes then
    raise exception 'FALHA - PARTE B: contagem de patrimonios mudou (%->%) — criar pendência NUNCA pode alterar patrimônio', v_qtd_patrimonios_antes, v_qtd_patrimonios_depois;
  end if;
  if v_qtd_movimentacoes_depois <> v_qtd_movimentacoes_antes then
    raise exception 'FALHA - PARTE B: contagem de movimentacoes mudou (%->%) — criar pendência NUNCA pode registrar movimentação', v_qtd_movimentacoes_antes, v_qtd_movimentacoes_depois;
  end if;

  raise notice 'OK - PARTE B: documento % criado com 2 itens PENDENTE, patrimonios/movimentacoes intocados', v_doc.id;
end $$;

-- =============================================================================
-- PARTE C — EDIÇÃO incrementa versão e produz auditoria
-- =============================================================================
do $$
declare
  v_doc_id uuid := current_setting('zz.doc_b_id')::uuid;
  v_versao_antes integer;
  v_versao_depois integer;
  v_qtd_eventos_antes integer;
  v_qtd_eventos_depois integer;
  v_item1 uuid;
  v_resultado public.documentos_sei;
begin
  select versao into v_versao_antes from public.documentos_sei where id = v_doc_id;
  select count(*) into v_qtd_eventos_antes from public.documentos_sei_eventos where documento_id = v_doc_id;
  select id into v_item1 from public.documentos_sei_itens where documento_id = v_doc_id order by linha limit 1;

  select public.editar_documento_sei_pendente(
    p_documento_id := v_doc_id,
    p_versao_esperada := v_versao_antes,
    p_motivo := 'ZZ_HOMOLOG teste de edição',
    p_alteracoes := jsonb_build_object('assunto', 'Assunto corrigido ZZ_HOMOLOG'),
    p_itens_alterados := jsonb_build_array(jsonb_build_object('item_id', v_item1, 'destino_texto_corrigido', 'GESOL (corrigido)'))
  ) into v_resultado;

  select versao into v_versao_depois from public.documentos_sei where id = v_doc_id;
  select count(*) into v_qtd_eventos_depois from public.documentos_sei_eventos where documento_id = v_doc_id;

  if v_versao_depois <> v_versao_antes + 1 then
    raise exception 'FALHA - PARTE C: versao não incrementou (antes % depois %)', v_versao_antes, v_versao_depois;
  end if;
  if v_qtd_eventos_depois <= v_qtd_eventos_antes then
    raise exception 'FALHA - PARTE C: nenhum evento novo gravado pela edição';
  end if;
  if not exists (
    select 1 from public.documentos_sei_eventos
    where documento_id = v_doc_id and tipo = 'EDICAO' and criado_em >= now() - interval '1 minute'
  ) then
    raise exception 'FALHA - PARTE C: evento EDICAO não encontrado';
  end if;

  raise notice 'OK - PARTE C: edição incrementou versão (%->%) e gravou evento EDICAO', v_versao_antes, v_versao_depois;
end $$;

-- =============================================================================
-- PARTE D — ROLLBACK INTEGRAL em payload de edição parcialmente inválido
-- =============================================================================
do $$
declare
  v_doc_id uuid := current_setting('zz.doc_b_id')::uuid;
  v_versao_antes integer;
  v_assunto_antes text;
  v_item1 uuid;
  v_falhou boolean := false;
begin
  select versao, assunto into v_versao_antes, v_assunto_antes from public.documentos_sei where id = v_doc_id;
  select id into v_item1 from public.documentos_sei_itens where documento_id = v_doc_id order by linha limit 1;

  begin
    perform public.editar_documento_sei_pendente(
      p_documento_id := v_doc_id,
      p_versao_esperada := v_versao_antes,
      p_motivo := 'ZZ_HOMOLOG teste de rollback (item inexistente misturado)',
      p_alteracoes := jsonb_build_object('assunto', 'ISTO NAO DEVERIA SER SALVO'),
      p_itens_alterados := jsonb_build_array(
        jsonb_build_object('item_id', v_item1, 'destino_texto_corrigido', 'ISTO TAMBEM NAO DEVERIA SER SALVO'),
        jsonb_build_object('item_id', gen_random_uuid(), 'destino_texto_corrigido', 'item inexistente')
      )
    );
  exception when others then
    v_falhou := true;
  end;

  if not v_falhou then
    raise exception 'FALHA - PARTE D: a edição com item inexistente NÃO lançou exceção';
  end if;
  if (select versao from public.documentos_sei where id = v_doc_id) <> v_versao_antes then
    raise exception 'FALHA - PARTE D: versao mudou mesmo com rollback esperado';
  end if;
  if (select assunto from public.documentos_sei where id = v_doc_id) <> v_assunto_antes then
    raise exception 'FALHA - PARTE D: assunto foi alterado mesmo com rollback esperado';
  end if;

  raise notice 'OK - PARTE D: payload parcialmente inválido rejeitou a operação INTEIRA, nada foi salvo';
end $$;

-- =============================================================================
-- PARTE E — CANCELAMENTO INDIVIDUAL DE ITEM
-- =============================================================================
do $$
declare
  v_doc_id uuid := current_setting('zz.doc_b_id')::uuid;
  v_item2 uuid;
begin
  select id into v_item2 from public.documentos_sei_itens where documento_id = v_doc_id order by linha desc limit 1;

  perform public.cancelar_item_sei_pendente(p_item_id := v_item2, p_motivo := 'ZZ_HOMOLOG cancelamento individual');

  if (select status from public.documentos_sei_itens where id = v_item2) <> 'CANCELADO' then
    raise exception 'FALHA - PARTE E: item não ficou CANCELADO';
  end if;
  if (select motivo_cancelamento from public.documentos_sei_itens where id = v_item2) is null then
    raise exception 'FALHA - PARTE E: motivo_cancelamento ausente';
  end if;

  raise notice 'OK - PARTE E: cancelamento individual de item funcionou';
end $$;

-- =============================================================================
-- PARTE F — CANCELAMENTO DO RESTANTE DO DOCUMENTO (documento à parte, para
-- não interferir com o documento usado nas partes B-E)
-- =============================================================================
do $$
declare
  v_doc public.documentos_sei;
  v_pat3 uuid;
  v_getec uuid;
  v_geasi uuid;
  v_qtd_cancelados integer;
begin
  select id into v_pat3 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000003';
  select id into v_getec from public.setores where sigla = 'ZZHGETEC';
  select id into v_geasi from public.setores where sigla = 'ZZHGEASI';

  select public.criar_documento_sei_pendente(
    p_tipo_operacao_pretendida := 'TRANSFERENCIA',
    p_nome_arquivo := 'zz_homolog_despacho_f.pdf',
    p_hash_sha256 := 'zz-homolog-hash-f',
    p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', v_pat3, 'origem_setor_id', v_getec, 'destino_setor_id', v_geasi)),
    p_numero_documento_sei := 'ZZHOMOLOG-SEI-0006'
  ) into v_doc;

  select count(*) into v_qtd_cancelados from public.cancelar_pendentes_documento_sei(p_documento_id := v_doc.id, p_motivo := 'ZZ_HOMOLOG cancela restante');

  if v_qtd_cancelados <> 1 then
    raise exception 'FALHA - PARTE F: esperava 1 item cancelado, veio %', v_qtd_cancelados;
  end if;
  if (select situacao from public.documentos_sei_com_situacao where id = v_doc.id) <> 'CANCELADO' then
    raise exception 'FALHA - PARTE F: documento com todos os itens cancelados não ficou CANCELADO na view';
  end if;

  raise notice 'OK - PARTE F: cancelamento de todos os pendentes funcionou, situação = CANCELADO';
end $$;

-- =============================================================================
-- PARTE G — TENTATIVA DE EDIÇÃO APÓS PRIMEIRA CONCLUSÃO SIMULADA
-- =============================================================================
-- SIMULAÇÃO DE TESTE: a RPC de conclusão real NÃO existe nesta etapa
-- (seção 7 do PROMPT 11.3.4 — fora de escopo). Para testar a regra "documento
-- com item concluído fica bloqueado para edição" precisamos de UM item em
-- estado CONCLUIDO — produzido aqui por INSERT/UPDATE diretos como DONO DO
-- BANCO (nunca como authenticated, nunca via app), exatamente equivalente
-- ao helper `marcarItemConcluidoParaTeste` do fake Dart. NUNCA rode isto
-- fora deste roteiro de teste.
reset role;
do $$
declare
  v_doc public.documentos_sei;
  v_item uuid;
  v_pat4 uuid;
  v_admin uuid;
  v_mov uuid;
  v_getec uuid;
  v_geasi uuid;
begin
  select id into v_pat4 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000004';
  select id into v_admin from public.profiles where email = 'zzhomolog.admin@invtec.test';
  select id into v_getec from public.setores where sigla = 'ZZHGETEC';
  select id into v_geasi from public.setores where sigla = 'ZZHGEASI';

  -- Documento pendente criado normalmente (como ADMIN, via RPC real).
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select public.criar_documento_sei_pendente(
    p_tipo_operacao_pretendida := 'TRANSFERENCIA',
    p_nome_arquivo := 'zz_homolog_despacho_g.pdf',
    p_hash_sha256 := 'zz-homolog-hash-g',
    p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', v_pat4, 'origem_setor_id', v_getec, 'destino_setor_id', v_geasi)),
    p_numero_documento_sei := 'ZZHOMOLOG-SEI-0007'
  ) into v_doc;

  reset role;

  select id into v_item from public.documentos_sei_itens where documento_id = v_doc.id limit 1;

  -- SIMULAÇÃO: cria uma movimentação FICTÍCIA "manualmente" (nunca via
  -- registrar_movimentacao) e vincula o item a ela, como o dono do banco
  -- faria numa futura RPC de conclusão — só para exercitar o bloqueio.
  insert into public.movimentacoes (patrimonio_id, tipo, origem_id, destino_id, realizado_por, numero_documento)
  values (v_pat4, 'TRANSFERENCIA', v_getec, v_geasi, v_admin, 'ZZHOMOLOG-SEI-0007')
  returning id into v_mov;

  update public.documentos_sei_itens set status = 'CONCLUIDO', movimentacao_id = v_mov where id = v_item;
  update public.documentos_sei set versao = versao + 1 where id = v_doc.id;

  -- IMPORTANTE: `false` (não `true`) — este valor precisa sobreviver até o
  -- PRÓXIMO bloco `do $$ ... $$;` (uma transação separada, se o SQL
  -- Editor faz autocommit por statement); `true` (SET LOCAL) seria
  -- descartado no fim desta transação e o próximo bloco falharia com
  -- "unrecognized configuration parameter" ao tentar ler zz.doc_g_id.
  perform set_config('zz.doc_g_id', v_doc.id::text, false);
  raise notice 'OK - PARTE G (setup): item % marcado CONCLUIDO por simulação de teste (nunca via app)', v_item;
end $$;

do $$
declare
  v_doc_id uuid := current_setting('zz.doc_g_id')::uuid;
  v_admin uuid;
  v_qtd_eventos_antes integer;
  v_qtd_eventos_depois integer;
  v_falhou boolean := false;
begin
  select id into v_admin from public.profiles where email = 'zzhomolog.admin@invtec.test';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_qtd_eventos_antes from public.documentos_sei_eventos where documento_id = v_doc_id;

  begin
    perform public.editar_documento_sei_pendente(
      p_documento_id := v_doc_id,
      p_versao_esperada := (select versao from public.documentos_sei where id = v_doc_id),
      p_motivo := 'ZZ_HOMOLOG tentativa bloqueada',
      p_alteracoes := jsonb_build_object('assunto', 'NAO DEVERIA SALVAR')
    );
  exception when others then
    v_falhou := true;
  end;

  if not v_falhou then
    raise exception 'FALHA - PARTE G: editar documento com item CONCLUIDO NÃO foi bloqueado';
  end if;

  select count(*) into v_qtd_eventos_depois from public.documentos_sei_eventos where documento_id = v_doc_id;
  if v_qtd_eventos_depois <> v_qtd_eventos_antes then
    raise exception 'FALHA - PARTE G: a tentativa bloqueada gravou % evento(s) novo(s) — deveria gravar ZERO (PROMPT 11.3.2, seção 3)', v_qtd_eventos_depois - v_qtd_eventos_antes;
  end if;
  if exists (select 1 from public.documentos_sei_eventos where documento_id = v_doc_id and tipo = 'TENTATIVA_BLOQUEADA') then
    raise exception 'FALHA - PARTE G: evento TENTATIVA_BLOQUEADA foi persistido (não deveria — ver PROMPT 11.3.2)';
  end if;

  raise notice 'OK - PARTE G: edição pós-conclusão bloqueada, ZERO evento novo persistido (nenhuma promessa falsa de auditoria)';
end $$;
reset role;

-- =============================================================================
-- PARTE H — CONSTRAINTS E TRIGGERS
-- =============================================================================
do $$
declare
  v_doc uuid;
  v_pat5 uuid;
  v_getec uuid;
  v_gesol uuid;
  v_cimeh uuid;
  v_admin uuid;
  v_item uuid;
  v_falhou boolean;
begin
  select id into v_pat5 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000005';
  select id into v_getec from public.setores where sigla = 'ZZHGETEC';
  select id into v_gesol from public.setores where sigla = 'ZZHGESOL';
  select id into v_cimeh from public.setores where sigla = 'ZZHCIMEH';
  select id into v_admin from public.profiles where email = 'zzhomolog.admin@invtec.test';

  -- H1: item CONCLUIDO sem movimentacao_id é rejeitado pela CHECK.
  v_falhou := false;
  begin
    insert into public.documentos_sei (numero_documento_sei, tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por)
    values ('ZZHOMOLOG-SEI-H1', 'TRANSFERENCIA', 'zz.pdf', 'zz-h1', v_admin) returning id into v_doc;
    insert into public.documentos_sei_itens (documento_id, linha, patrimonio_id, status)
    values (v_doc, 1, v_pat5, 'CONCLUIDO');
  exception when check_violation then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - H1: item CONCLUIDO sem movimentacao_id não foi rejeitado'; end if;
  raise notice 'OK - H1: item CONCLUIDO sem movimentacao_id rejeitado pela CHECK';

  -- H2: item CANCELADO sem motivo é rejeitado.
  v_falhou := false;
  begin
    insert into public.documentos_sei_itens (documento_id, linha, patrimonio_id, status)
    values (v_doc, 2, v_pat5, 'CANCELADO');
  exception when check_violation then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - H2: item CANCELADO sem motivo não foi rejeitado'; end if;
  raise notice 'OK - H2: item CANCELADO sem motivo rejeitado pela CHECK';

  -- H3: decisão de localização incoerente (DEFINIDO sem localizacao_destino_id).
  v_falhou := false;
  begin
    insert into public.documentos_sei_itens (documento_id, linha, patrimonio_id, decisao_localizacao)
    values (v_doc, 3, v_pat5, 'DEFINIDO');
  exception when check_violation then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - H3: decisao_localizacao=DEFINIDO sem localização não foi rejeitado'; end if;
  raise notice 'OK - H3: decisão de localização incoerente rejeitada pela CHECK';

  -- H4: localização de OUTRO setor é rejeitada pela trigger.
  v_falhou := false;
  begin
    insert into public.documentos_sei_itens (documento_id, linha, patrimonio_id, destino_setor_id, localizacao_destino_id, decisao_localizacao)
    values (
      v_doc, 4, v_pat5, v_gesol,
      (select id from public.localizacoes where setor_id = v_cimeh limit 1), -- localização do CIMEHGO, destino é GESOL
      'DEFINIDO'
    );
  exception when others then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - H4: localização de outro setor não foi rejeitada'; end if;
  raise notice 'OK - H4: localização de outro setor rejeitada pela trigger';

  -- H5: movimentação de OUTRO patrimônio não pode ser vinculada ao item.
  v_falhou := false;
  declare
    v_outro_pat uuid;
    v_mov_de_outro uuid;
    v_item5 uuid;
  begin
    select id into v_outro_pat from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001';
    insert into public.movimentacoes (patrimonio_id, tipo, destino_id, realizado_por)
    values (v_outro_pat, 'TRANSFERENCIA', v_gesol, v_admin) returning id into v_mov_de_outro;

    insert into public.documentos_sei_itens (documento_id, linha, patrimonio_id, status, motivo_cancelamento)
    values (v_doc, 5, v_pat5, 'PENDENTE', null) returning id into v_item5;

    begin
      update public.documentos_sei_itens set status = 'CONCLUIDO', movimentacao_id = v_mov_de_outro where id = v_item5;
    exception when others then v_falhou := true;
    end;
  end;
  if not v_falhou then raise exception 'FALHA - H5: movimentação de outro patrimônio foi aceita — trigger validate_pendencia_movimentacao_patrimonio não funcionou'; end if;
  raise notice 'OK - H5: movimentação de outro patrimônio rejeitada pela trigger';

  -- H6: payload JSON não-array em p_itens rejeitado.
  v_falhou := false;
  begin
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    perform public.criar_documento_sei_pendente(
      p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-h6',
      p_itens := '{"nao": "e um array"}'::jsonb, p_numero_documento_sei := 'ZZHOMOLOG-SEI-H6'
    );
  exception when others then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - H6: p_itens não-array não foi rejeitado'; end if;
  raise notice 'OK - H6: payload JSON não-array em p_itens rejeitado';

  -- H7: item repetido em p_itens_alterados rejeitado.
  v_falhou := false;
  declare v_doc7 public.documentos_sei; v_item7 uuid;
  begin
    select public.criar_documento_sei_pendente(
      p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-h7',
      p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', v_pat5)),
      p_numero_documento_sei := 'ZZHOMOLOG-SEI-H7'
    ) into v_doc7;
    select id into v_item7 from public.documentos_sei_itens where documento_id = v_doc7.id limit 1;
    begin
      perform public.editar_documento_sei_pendente(
        p_documento_id := v_doc7.id, p_versao_esperada := 1, p_motivo := 'teste item repetido',
        p_itens_alterados := jsonb_build_array(
          jsonb_build_object('item_id', v_item7, 'destino_texto_corrigido', 'A'),
          jsonb_build_object('item_id', v_item7, 'destino_texto_corrigido', 'B')
        )
      );
    exception when others then v_falhou := true;
    end;
  end;
  reset role;
  if not v_falhou then raise exception 'FALHA - H7: item_id repetido em p_itens_alterados não foi rejeitado'; end if;
  raise notice 'OK - H7: item repetido em p_itens_alterados rejeitado';
end $$;

-- =============================================================================
-- PARTE I — DUPLICIDADE (com/sem processo, reimport confirmado)
-- =============================================================================
do $$
declare
  v_admin uuid;
  v_pat1 uuid;
  v_falhou boolean;
begin
  select id into v_admin from public.profiles where email = 'zzhomolog.admin@invtec.test';
  select id into v_pat1 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- I1: cria sem processo.
  perform public.criar_documento_sei_pendente(
    p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-i1',
    p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', v_pat1)),
    p_numero_documento_sei := 'ZZHOMOLOG-SEI-I', p_numero_processo := null
  );

  -- I2: mesmo SEI, AGORA com processo — deve ser rejeitado (PROMPT 11.3.3, seção 3).
  v_falhou := false;
  begin
    perform public.criar_documento_sei_pendente(
      p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-i2',
      p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', v_pat1)),
      p_numero_documento_sei := 'ZZHOMOLOG-SEI-I', p_numero_processo := 'ZZHOMOLOG-PROC-1'
    );
  exception when others then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - I2: duplicata (sem processo -> com processo) não foi rejeitada'; end if;
  raise notice 'OK - I2: duplicata sem processo -> com processo rejeitada';

  -- I3: reimport COM confirmação explícita deve funcionar.
  perform public.criar_documento_sei_pendente(
    p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-i3',
    p_itens := jsonb_build_array(jsonb_build_object('linha', 1, 'patrimonio_id', v_pat1)),
    p_numero_documento_sei := 'ZZHOMOLOG-SEI-I', p_numero_processo := 'ZZHOMOLOG-PROC-1',
    p_confirmar_duplicata := true
  );
  raise notice 'OK - I3: reimport com p_confirmar_duplicata=true funcionou';

  if (select count(*) from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-SEI-I') <> 2 then
    raise exception 'FALHA - I: esperava exatamente 2 documentos ZZHOMOLOG-SEI-I (1 recusado + 1 confirmado)';
  end if;
end $$;
reset role;

-- =============================================================================
-- PARTE J — RLS / GRANTS POR PERFIL
-- =============================================================================
-- J1: CONSULTA consegue SELECT mas NÃO consegue EXECUTE nas funções de escrita.
do $$
declare v_consulta uuid; v_falhou boolean := false;
begin
  select id into v_consulta from public.profiles where email = 'zzhomolog.consulta@invtec.test';
  perform set_config('request.jwt.claim.sub', v_consulta::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_consulta, 'role', 'authenticated')::text, true);
  set local role authenticated;

  if (select count(*) from public.documentos_sei_com_situacao) < 1 then
    raise exception 'FALHA - J1: CONSULTA não conseguiu SELECT na view (deveria conseguir)';
  end if;

  begin
    perform public.criar_documento_sei_pendente(
      p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-j1',
      p_itens := jsonb_build_array(jsonb_build_object('linha', 1))
    );
  exception when others then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - J1: CONSULTA conseguiu criar documento (deveria ser rejeitado por has_perfil)'; end if;
  raise notice 'OK - J1: CONSULTA lê a view, mas é rejeitado ao tentar escrever';
end $$;
reset role;

-- J2: authenticated SEM perfil ativo não vê nada (RLS) e não escreve.
do $$
declare v_sem uuid; v_falhou boolean := false; v_qtd integer;
begin
  select id into v_sem from public.profiles where email = 'zzhomolog.semperfil@invtec.test';
  if v_sem is null then
    raise notice 'AVISO - J2: usuário zzhomolog.semperfil@invtec.test não encontrado — crie-o no Auth (sem promover) para rodar este teste. Pulado.';
  else
    perform set_config('request.jwt.claim.sub', v_sem::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_sem, 'role', 'authenticated')::text, true);
    set local role authenticated;

    select count(*) into v_qtd from public.documentos_sei_com_situacao;
    if v_qtd <> 0 then
      raise exception 'FALHA - J2: authenticated sem perfil ativo enxergou % linha(s) via RLS (deveria ser 0)', v_qtd;
    end if;

    begin
      perform public.criar_documento_sei_pendente(
        p_tipo_operacao_pretendida := 'TRANSFERENCIA', p_nome_arquivo := 'zz.pdf', p_hash_sha256 := 'zz-j2',
        p_itens := jsonb_build_array(jsonb_build_object('linha', 1))
      );
    exception when others then v_falhou := true;
    end;
    if not v_falhou then raise exception 'FALHA - J2: authenticated sem perfil ativo conseguiu escrever'; end if;
    raise notice 'OK - J2: authenticated sem perfil ativo não vê nada e não escreve';
  end if;
end $$;
reset role;

-- J3: anon não vê nada, sem GRANT nenhum.
do $$
declare v_falhou boolean := false;
begin
  set local role anon;
  begin
    perform count(*) from public.documentos_sei_com_situacao;
  exception when others then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - J3: anon conseguiu consultar a view (deveria não ter GRANT nenhum)'; end if;
  raise notice 'OK - J3: anon sem GRANT algum nas tabelas/view de Documentos SEI';
end $$;
reset role;

-- J4: nenhum INSERT/UPDATE/DELETE direto, mesmo como ADMIN autenticado
-- (toda escrita passa pelas funções — nunca GRANT direto nas tabelas).
do $$
declare v_admin uuid; v_falhou boolean := false;
begin
  select id into v_admin from public.profiles where email = 'zzhomolog.admin@invtec.test';
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  set local role authenticated;

  begin
    insert into public.documentos_sei (numero_documento_sei, tipo_operacao_pretendida, nome_arquivo, hash_sha256, criado_por)
    values ('NUNCA-DEVERIA-EXISTIR', 'TRANSFERENCIA', 'x', 'x', v_admin);
  exception when insufficient_privilege then v_falhou := true;
  end;
  if not v_falhou then raise exception 'FALHA - J4: INSERT direto em documentos_sei foi aceito como authenticated (deveria ser insufficient_privilege)'; end if;
  raise notice 'OK - J4: INSERT direto em documentos_sei rejeitado — só as funções escrevem';
end $$;
reset role;

raise notice 'FIM DO ROTEIRO — reveja acima cada linha OK/FALHA antes de considerar a migration validada.';
