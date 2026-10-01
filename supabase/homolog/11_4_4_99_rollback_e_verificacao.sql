-- =============================================================================
-- PROMPT 11.4.4 — PASSO 99: ROLLBACK de segurança + verificação PÓS-ROLLBACK
-- =============================================================================
-- Rode DEPOIS de 11_4_4_concluir_item_rollback.sql — tenha ele terminado bem
-- ou falhado no meio. Cada bloco numa execução SEPARADA do SQL Editor.
-- Só o BLOCO A escreve algo (nada: é só um ROLLBACK); os demais são SELECT.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BLOCO A — ROLLBACK isolado e seguro.
-- Execute SOZINHO, imediatamente, se o script principal parou por causa de uma
-- exceção (assertiva, erro da RPC etc.): o Postgres pula o resto do script,
-- inclusive o ROLLBACK final, e a transação fica aberta/abortada.
--
-- É SEGURO rodar sem transação aberta: o Postgres só avisa "there is no
-- transaction in progress" e não faz nada. Se o editor usar outra conexão para
-- esta execução, o aviso é o esperado — a transação antiga morre quando o
-- editor fecha a conexão dela; confirme no BLOCO C.
-- -----------------------------------------------------------------------------
ROLLBACK;


-- -----------------------------------------------------------------------------
-- BLOCO B — "FOTO DEPOIS": contagem + md5 das linhas inteiras. Precisa ser
-- IDÊNTICO ao BLOCO 3 de 11_4_4_00_prerequisitos_somente_leitura.sql (mesma
-- contagem E mesmo md5 em CADA tabela). Se algum md5 divergir, ALGO foi
-- persistido ou alterado — pare e investigue (compare também o BLOCO D).
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as total,
       md5(coalesce(string_agg(t::text, '|' order by t.id), '')) as impressao
from public.patrimonios t
union all
select 'movimentacoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.movimentacoes t
union all
select 'documentos_sei', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei t
union all
select 'documentos_sei_itens', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei_itens t
union all
select 'documentos_sei_eventos', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.documentos_sei_eventos t
union all
select 'setores', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.setores t
union all
select 'localizacoes', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.localizacoes t
union all
select 'tipos_patrimonio', count(*), md5(coalesce(string_agg(t::text, '|' order by t.id), ''))
from public.tipos_patrimonio t
order by tabela;


-- -----------------------------------------------------------------------------
-- BLOCO C — nenhum dado ZZHOMOLOG-11.4.4 permaneceu. Esperado: TODAS as
-- linhas com 0. (Padrões: números/nomes/siglas começando por ZZHOMOLOG-11.4.4,
-- o documento ZZHOMOLOG-SEI-11.4.4 e o chamado ZZHOMOLOG-4556.)
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as sobras
from public.patrimonios
where numero_patrimonio like 'ZZHOMOLOG-11.4.4%' or descricao like 'Patrimonio ficticio PROMPT 11.4.4%'
union all
select 'documentos_sei', count(*)
from public.documentos_sei
where numero_documento_sei like 'ZZHOMOLOG-SEI-11.4.4%' or nome_arquivo like 'ZZHOMOLOG-11.4.4%'
union all
select 'documentos_sei_itens', count(*)
from public.documentos_sei_itens
where numero_patrimonio_original like 'ZZHOMOLOG-11.4.4%' or numero_chamado_original like 'ZZHOMOLOG-4556%'
union all
select 'documentos_sei_eventos', count(*)
from public.documentos_sei_eventos
where descricao like '%ZZHOMOLOG-11.4.4%'
union all
select 'movimentacoes', count(*)
from public.movimentacoes
where numero_documento like 'ZZHOMOLOG-SEI-11.4.4%'
   or numero_chamado like 'ZZHOMOLOG-4556%'
   or motivo like '%ZZHOMOLOG-SEI-11.4.4%'
   or observacao like 'ZZHOMOLOG-11.4.4%'
union all
select 'setores', count(*)
from public.setores
where nome like 'ZZHOMOLOG-11.4.4%' or sigla like 'ZZHOMOLOG-11.4.4%'
union all
select 'localizacoes', count(*)
from public.localizacoes
where nome like 'ZZHOMOLOG-11.4.4%' or sigla like 'ZZHOMOLOG-11.4.4%'
union all
select 'tipos_patrimonio', count(*)
from public.tipos_patrimonio
where nome like 'ZZHOMOLOG-11.4.4%'
order by tabela;


-- -----------------------------------------------------------------------------
-- BLOCO D — sobrou alguma transação aberta/abortada (a única forma de o teste
-- "vazar" seria uma sessão presa; dados não confirmados são INVISÍVEIS aos
-- outros SELECTs, então só isto os revelaria)? Esperado: 0 linhas. Se aparecer
-- uma sessão "idle in transaction (aborted)" do editor, o ROLLBACK do BLOCO A
-- não chegou nela: rode-o de novo na mesma aba ou encerre-a com
--   select pg_terminate_backend(<pid>);   (só nessa sessão do editor)
-- (pg_stat_activity pode ocultar sessões de outros papéis conforme o projeto;
-- se a lista vier vazia, o BLOCO B/C continuam sendo a prova definitiva.)
-- -----------------------------------------------------------------------------
select pid, usename, state, xact_start, now() - xact_start as aberta_ha, left(query, 120) as ultima_query
from pg_stat_activity
where datname = current_database()
  and pid <> pg_backend_pid()
  and state like 'idle in transaction%'
order by xact_start;
