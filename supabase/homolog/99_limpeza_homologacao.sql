-- =============================================================================
-- PROMPT 11.3.4 — limpeza dos dados fictícios de HOMOLOGAÇÃO (ZZ_HOMOLOG_*
-- / ZZHOMOLOG-*), para poder rodar o roteiro de testes de novo do zero.
--
-- SÓ RODAR no projeto de HOMOLOGAÇÃO — rode primeiro
-- `00_check_target_not_producao.sh env/homologacao.env` (ou o `.ps1`) até
-- "LIBERADO" e cole isto na MESMA aba do Dashboard confirmada ali (PROMPT
-- 11.3.4.1) — nunca confie só na lembrança de qual aba é qual. Ordem
-- respeita as FKs (filhos antes dos pais). Idempotente: rodar de novo sem
-- nada para apagar não dá erro.
-- =============================================================================

-- PROMPT 11.6.5 — `patrimonio_comparacao_execucoes` é FILHA de `patrimonios`
-- (`on delete restrict`): precisa ser limpa ANTES da linha de `patrimonios`
-- mais abaixo, senão o DELETE de patrimonios falha. Tabela nova nesta etapa
-- (migration `20260930120000_add_aplicar_decisao_comparacao_patrimonio.sql`,
-- ainda não aplicada em nenhum ambiente — esta linha só tem efeito quando/se
-- ela existir).
delete from public.patrimonio_comparacao_execucoes
where patrimonio_id in (select id from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-%');

delete from public.documentos_sei_eventos
where documento_id in (select id from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-%');

delete from public.documentos_sei_itens
where documento_id in (select id from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-%');

delete from public.documentos_sei
where numero_documento_sei like 'ZZHOMOLOG-%';

delete from public.movimentacoes
where numero_documento like 'ZZHOMOLOG-%'
   or patrimonio_id in (select id from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-%');

delete from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-%';

delete from public.localizacoes where sigla like 'ZZH%';

delete from public.setores where sigla like 'ZZH%';

-- Conferência (todas devem retornar 0):
select
  (select count(*) from public.documentos_sei where numero_documento_sei like 'ZZHOMOLOG-%') as documentos_restantes,
  (select count(*) from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-%') as patrimonios_restantes,
  (select count(*) from public.setores where sigla like 'ZZH%') as setores_restantes,
  (select count(*) from public.patrimonio_comparacao_execucoes) as execucoes_comparacao_restantes;

-- OPCIONAL — usuários de teste (zzhomolog.*@invtec.test): deixar como
-- estão é seguro (é um projeto de homologação isolado, não produção); só
-- remova se quiser um projeto totalmente limpo. Para remover de fato,
-- primeiro:
--   delete from public.profiles where email like 'zzhomolog.%@invtec.test';
-- e SÓ DEPOIS exclua os usuários correspondentes no painel Authentication
-- do projeto de homologação (a FK profiles.id -> auth.users é ON DELETE
-- RESTRICT: a ordem inversa falha).
