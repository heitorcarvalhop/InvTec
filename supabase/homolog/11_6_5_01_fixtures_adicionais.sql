-- =============================================================================
-- PROMPT 11.6.5 — Fixtures ADICIONAIS (além de `01_fixtures_homologacao
-- .sql`, que já roda antes deste): um patrimônio BAIXADO, um segundo
-- setor/localização (para testar troca de setor), e um documento SEI
-- pendente vinculado a um patrimônio (para o cenário P0042).
--
-- Mesma disciplina de `01_fixtures_homologacao.sql`: prefixo ZZHOMOLOG-
-- (patrimônios) / ZZ_HOMOLOG_ (setores/localizações), idempotente (só
-- insere se ainda não existir), nunca toca os 1.414 bens reais nem o
-- Despacho 577. Rode DEPOIS de `01_fixtures_homologacao.sql` (reusa
-- `zzhomolog.admin@invtec.test` como `criado_por`).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PASSO 1 — um segundo par setor/localização (destino de uma troca de
-- setor legítima nos testes de atomicidade da seção 3).
-- -----------------------------------------------------------------------------
insert into public.setores (nome, sigla, descricao)
select 'ZZ_HOMOLOG_11_6_5_DESTINO', 'ZZH1165D', 'Setor fictício — PROMPT 11.6.5, destino de troca de setor'
where not exists (select 1 from public.setores where sigla = 'ZZH1165D');

insert into public.localizacoes (setor_id, nome, sigla)
select s.id, 'Sala fictícia destino 11.6.5', 'ZZH1165-D1'
from public.setores s
where s.sigla = 'ZZH1165D'
  and not exists (select 1 from public.localizacoes where sigla = 'ZZH1165-D1');

-- -----------------------------------------------------------------------------
-- PASSO 2 — patrimônios fictícios específicos de 11.6.5.
--   ZZHOMOLOG-11.6.5-01 — em ZZHGETEC, COM localização (para testar troca de
--     setor isolada e a limpeza automática da localização).
--   ZZHOMOLOG-11.6.5-02 — BAIXADO (para o cenário "patrimônio com
--     bloqueio").
-- -----------------------------------------------------------------------------
insert into public.patrimonios (numero_patrimonio, tipo_id, setor_atual_id, localizacao_atual_id, status, criado_por, descricao)
select 'ZZHOMOLOG-11.6.5-01', t.id, s.id, l.id, 'DISPONIVEL', p.id, 'Patrimônio fictício — PROMPT 11.6.5 (troca de setor)'
from public.tipos_patrimonio t, public.setores s, public.localizacoes l,
     (select id from public.profiles where email = 'zzhomolog.admin@invtec.test' limit 1) p
where t.nome = 'Notebook' and s.sigla = 'ZZHGETEC' and l.sigla = 'ZZHG-01'
  and not exists (select 1 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-01');

-- BAIXADO exige uma movimentação BAIXA de verdade (o status não é editável
-- por UPDATE direto — `protect_patrimonio_columns`) — cadastra DISPONÍVEL
-- primeiro e então registra a baixa via RPC já homologada.
insert into public.patrimonios (numero_patrimonio, tipo_id, setor_atual_id, status, criado_por, descricao)
select 'ZZHOMOLOG-11.6.5-02', t.id, s.id, 'DISPONIVEL', p.id, 'Patrimônio fictício — PROMPT 11.6.5 (baixado)'
from public.tipos_patrimonio t, public.setores s,
     (select id from public.profiles where email = 'zzhomolog.admin@invtec.test' limit 1) p
where t.nome = 'Monitor' and s.sigla = 'ZZHGETEC'
  and not exists (select 1 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02');

select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;

do $$
begin
  if not exists (
    select 1 from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02' and status = 'BAIXADO'
  ) then
    perform public.registrar_movimentacao(
      p_patrimonio_id := (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-11.6.5-02'),
      p_tipo := 'BAIXA',
      p_motivo := 'ZZ_HOMOLOG baixa fictícia — PROMPT 11.6.5'
    );
  end if;
end;
$$;

reset role;

-- -----------------------------------------------------------------------------
-- PASSO 3 — um documento SEI PENDENTE vinculado a ZZHOMOLOG-000001 (da
-- fixture geral), para o cenário P0042 (pendência SEI incompatível).
-- `criar_documento_sei_pendente` nunca altera o patrimônio (só cria a
-- solicitação) — ver `20260921170000_add_documentos_sei.sql`.
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', (select id::text from public.profiles where email = 'zzhomolog.admin@invtec.test'), false);
select set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where email = 'zzhomolog.admin@invtec.test'), 'role', 'authenticated')::text, false);
set role authenticated;

do $$
begin
  if not exists (select 1 from public.documentos_sei where numero_documento_sei = 'ZZHOMOLOG-SEI-11.6.5-01') then
    perform public.criar_documento_sei_pendente(
      p_tipo_operacao_pretendida := 'TRANSFERENCIA',
      p_nome_arquivo := 'zz_homolog_11_6_5_pendencia.pdf',
      p_hash_sha256 := 'zz-homolog-11-6-5-pendencia',
      p_itens := jsonb_build_array(jsonb_build_object(
        'linha', 1,
        'patrimonio_id', (select id from public.patrimonios where numero_patrimonio = 'ZZHOMOLOG-000001')
      )),
      p_numero_documento_sei := 'ZZHOMOLOG-SEI-11.6.5-01'
    );
  end if;
end;
$$;

reset role;

-- Conferência:
select numero_patrimonio, status, setor_atual_id, localizacao_atual_id
from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-11.6.5%'
order by numero_patrimonio;

select d.numero_documento_sei, i.status, i.patrimonio_id
from public.documentos_sei d
join public.documentos_sei_itens i on i.documento_id = d.id
where d.numero_documento_sei = 'ZZHOMOLOG-SEI-11.6.5-01';
