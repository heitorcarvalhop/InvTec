-- Atualização somente de dados do catálogo de tipos_patrimonio. Não altera
-- schema, tabelas, funções ou RLS.
--
-- Tipos legados nunca são apagados (só desativados): tipo_id tem
-- ON DELETE RESTRICT e precisa continuar válido para histórico/testes.
-- Idempotente.

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

-- 3. Desativa (nunca apaga) os tipos legados fora do catálogo oficial.
update public.tipos_patrimonio
set ativo = false
where ativo = true
  and lower(nome) in (lower('Teclado'), lower('Mouse'), lower('Switch'), lower('Dock Station'));
