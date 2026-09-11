-- =============================================================================
-- Atualização SOMENTE DE DADOS do catálogo de tipos_patrimonio, para a
-- importação da planilha real da GETEC.
--
-- NÃO altera schema, NÃO cria/altera tabelas, colunas, funções ou RLS.
-- NÃO é aplicada automaticamente — este arquivo fica para revisão e
-- aplicação manual (`supabase db push` ou equivalente) quando autorizado.
--
-- Contexto: a migration inicial (20260910120000_initial_schema.sql) seedou
-- tipos_patrimonio com Teclado/Mouse/Switch/Dock Station como tipos
-- próprios. O catálogo desejado para esta fase os substitui por categorias
-- mais amplas (ex.: "Equipamento de Rede") e adiciona tipos que ainda não
-- existiam (TV, Projetor, Servidor, Estabilizador, Mobiliário,
-- Software / Licença, Certificado Digital).
--
-- Nunca DELETE: tipos legados ficam com ativo = false, nunca são apagados.
-- Motivo: patrimonios.tipo_id referencia tipos_patrimonio com
-- ON DELETE RESTRICT — apagar quebraria qualquer referência existente ou
-- futura (histórico, testes). "Desativado" já impede o uso em novos
-- cadastros (ver private.validate_tipo_patrimonio_ativo na migration
-- inicial), sem destruir nada.
--
-- Idempotente: pode ser executada mais de uma vez sem duplicar tipos nem
-- falhar em cima do que já foi aplicado.
-- =============================================================================

-- 1. Cria os tipos do catálogo oficial que ainda não existem (comparação
--    por lower(nome), igual ao índice único já existente na tabela).
insert into public.tipos_patrimonio (nome)
select catalogo.nome
from (
  values
    ('Notebook'),
    ('Desktop'),
    ('Monitor'),
    ('Impressora'),
    ('Nobreak'),
    ('Servidor'),
    ('TV'),
    ('Projetor'),
    ('Equipamento de Rede'),
    ('Estabilizador'),
    ('Mobiliário'),
    ('Software / Licença'),
    ('Certificado Digital'),
    ('Outros')
) as catalogo(nome)
where not exists (
  select 1
  from public.tipos_patrimonio t
  where lower(t.nome) = lower(catalogo.nome)
);

-- 2. Reativa tipos do catálogo oficial que por acaso já existam desativados.
update public.tipos_patrimonio
set ativo = true
where ativo = false
  and lower(nome) in (
    lower('Notebook'), lower('Desktop'), lower('Monitor'), lower('Impressora'),
    lower('Nobreak'), lower('Servidor'), lower('TV'), lower('Projetor'),
    lower('Equipamento de Rede'), lower('Estabilizador'), lower('Mobiliário'),
    lower('Software / Licença'), lower('Certificado Digital'), lower('Outros')
  );

-- 3. Desativa (nunca apaga) os tipos legados que não fazem mais parte do
--    catálogo oficial desta fase — seção 7/31 da especificação de
--    importação: Teclado/Mouse/Switch/Dock Station passam a ser cobertos
--    por categorias mais amplas ("Equipamento de Rede", "Outros").
update public.tipos_patrimonio
set ativo = false
where ativo = true
  and lower(nome) in (lower('Teclado'), lower('Mouse'), lower('Switch'), lower('Dock Station'));
