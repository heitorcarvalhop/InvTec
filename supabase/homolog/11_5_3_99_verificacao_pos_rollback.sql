-- =============================================================================
-- PROMPT 11.5.3 — PASSO 99: ROLLBACK de segurança + verificação PÓS-ROLLBACK
-- =============================================================================
-- Rode DEPOIS de 11_5_3_concluir_lote_rollback.sql — tenha ele terminado bem
-- ou falhado no meio. Cada bloco numa execução SEPARADA do SQL Editor.
-- Só o BLOCO A escreve algo (nada: é só um ROLLBACK); os demais são SELECT.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- BLOCO A — ROLLBACK isolado e seguro.
-- Execute SOZINHO, imediatamente, NA MESMA aba/conexão do SQL Editor onde
-- rodou 11_5_3_concluir_lote_rollback.sql, se o script principal parou por
-- causa de uma exceção FORA de um bloco de cenário (assertiva de guarda/
-- fixture, por exemplo — os blocos dos cenários B/C/D/E/F já capturam o erro
-- esperado deles e não deveriam derrubar a transação inteira): o Postgres
-- pula o resto do script, inclusive o ROLLBACK final, e a transação fica
-- aberta/abortada NAQUELA conexão específica.
--
-- PROMPT 11.5.3.1 — IMPORTANTE: `ROLLBACK;` só afeta a transação da conexão
-- que o executa. Rodar este BLOCO A numa aba/conexão DIFERENTE da que ficou
-- com a transação aberta NÃO a desfaz — ele só confirma (ou avisa "there is
-- no transaction in progress", o que é seguro e não faz nada) que a conexão
-- ATUAL, a que você está usando agora, não tem nada pendente. Se você não
-- tem mais acesso à aba original (foi fechada, travou etc.), NÃO tente
-- encerrá-la lançando mão de `pg_terminate_backend` por conta própria —
-- volte ao BLOCO D, PARE, e leve o `pid`/estado dela para análise.
-- -----------------------------------------------------------------------------
ROLLBACK;


-- -----------------------------------------------------------------------------
-- BLOCO B — "FOTO DEPOIS": contagem + md5 das linhas inteiras. Precisa ser
-- IDÊNTICO ao BLOCO 3 de 11_5_3_00_prerequisitos_somente_leitura.sql (mesma
-- contagem E mesmo md5 em CADA tabela, incluindo `documentos_sei_lotes_
-- conclusao`, que deve voltar a exatamente 0 linhas — "lotes registrados: 0"
-- era o estado confirmado antes deste prompt). Se algum md5 divergir, ALGO
-- foi persistido ou alterado — pare e investigue (compare também o BLOCO C).
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
select 'documentos_sei_lotes_conclusao', count(*), md5(coalesce(string_agg(t::text, '|' order by t.lote_id), ''))
from public.documentos_sei_lotes_conclusao t
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
-- BLOCO C — nenhum dado ZZHOMOLOG-11.5.3 permaneceu. Esperado: TODAS as
-- linhas com 0. (Padrões: números/nomes/siglas começando por ZZHOMOLOG-11.5.3,
-- os 4 documentos ZZHOMOLOG-SEI-11.5.3-A/E/F/G e os chamados
-- ZZHOMOLOG-4556-11.5.3-*.)
-- -----------------------------------------------------------------------------
select 'patrimonios' as tabela, count(*) as sobras
from public.patrimonios
where numero_patrimonio like 'ZZHOMOLOG-11.5.3%' or descricao like 'Patrimônio fictício PROMPT 11.5.3%'
union all
select 'documentos_sei', count(*)
from public.documentos_sei
where numero_documento_sei like 'ZZHOMOLOG-SEI-11.5.3%' or nome_arquivo like 'ZZHOMOLOG-11.5.3%'
union all
select 'documentos_sei_itens', count(*)
from public.documentos_sei_itens
where numero_patrimonio_original like 'ZZHOMOLOG-11.5.3%' or numero_chamado_original like 'ZZHOMOLOG-4556-11.5.3%'
union all
select 'documentos_sei_eventos', count(*)
from public.documentos_sei_eventos
where descricao like '%ZZHOMOLOG-11.5.3%'
union all
select 'documentos_sei_lotes_conclusao', count(*)
from public.documentos_sei_lotes_conclusao
where documento_id in (select id from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-SEI-11.5.3%')
union all
select 'movimentacoes', count(*)
from public.movimentacoes
where numero_documento like 'ZZHOMOLOG-SEI-11.5.3%'
   or numero_chamado like 'ZZHOMOLOG-4556-11.5.3%'
   or motivo like '%ZZHOMOLOG-SEI-11.5.3%'
   or observacao like 'ZZHOMOLOG-11.5.3%'
union all
select 'setores', count(*)
from public.setores
where nome like 'ZZHOMOLOG-11.5.3%' or sigla like 'ZZHOMOLOG-11.5.3%'
union all
select 'localizacoes', count(*)
from public.localizacoes
where nome like 'ZZHOMOLOG-11.5.3%' or sigla like 'ZZHOMOLOG-11.5.3%'
union all
select 'tipos_patrimonio', count(*)
from public.tipos_patrimonio
where nome like 'ZZHOMOLOG-11.5.3%'
order by tabela;


-- -----------------------------------------------------------------------------
-- BLOCO D — sobrou alguma transação aberta/abortada (a única forma de o teste
-- "vazar" seria uma sessão presa; dados não confirmados são INVISÍVEIS aos
-- outros SELECTs, então só isto os revelaria)? Esperado: 0 linhas.
--
-- PROMPT 11.5.3.1 — se aparecer uma sessão "idle in transaction (aborted)":
--   * IMPORTANTE: um ROLLBACK executado NESTA conexão (a do BLOCO A) NÃO
--     desfaz uma transação que ficou aberta em OUTRA conexão/aba — cada
--     conexão do Postgres tem sua própria transação; `ROLLBACK;` só afeta a
--     transação da conexão que o executa. Se a sessão presa listada abaixo
--     tem um `pid` DIFERENTE do desta sua sessão atual, o BLOCO A desta aba
--     não a alcança.
--   * NÃO encerre a sessão automaticamente (`pg_terminate_backend` não é um
--     procedimento padrão deste runbook). Em vez disso: PARE — interrompa
--     qualquer execução em andamento naquela aba/conexão do SQL Editor — e
--     leve o `pid`, o `usename`, o `state` e a `ultima_query` abaixo para
--     análise antes de decidir o que fazer (pode ser a mesma aba que rodou o
--     script principal, ainda com a transação aberta porque o ROLLBACK final
--     dela nunca rodou — nesse caso, volte a essa aba e rode `ROLLBACK;`
--     diretamente nela, é o caminho seguro; só considere encerrar a conexão à
--     força depois de confirmar que não há outra forma de fechá-la e que os
--     dados dela realmente precisam ser descartados).
-- (pg_stat_activity pode ocultar sessões de outros papéis conforme o projeto;
-- se a lista vier vazia, o BLOCO B/C continuam sendo a prova definitiva.)
-- -----------------------------------------------------------------------------
select pid, usename, state, xact_start, now() - xact_start as aberta_ha, left(query, 120) as ultima_query
from pg_stat_activity
where datname = current_database()
  and pid <> pg_backend_pid()
  and state like 'idle in transaction%'
order by xact_start;
