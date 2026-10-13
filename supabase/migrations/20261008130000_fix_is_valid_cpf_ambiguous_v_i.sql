-- InvTec — correção pontual: private.is_valid_cpf(text) falhava em produção
-- com SQLSTATE 42702 ("column reference "v_i" is ambiguous") durante o
-- signup.
--
-- Causa raiz: `from generate_series(1, 11) v_i` aliasa o item do FROM como
-- "v_i" e, como generate_series tem uma única coluna de saída, o Postgres
-- nomeia essa coluna também como "v_i" (regra específica para funções de
-- retorno de conjunto com uma coluna só, aliasadas sem lista de colunas).
-- Dentro do bloco PL/pgSQL já existe uma variável declarada `v_i int`, usada
-- nos loops `for v_i in 1..9/1..10 loop`. A referência a `v_i` dentro do
-- `substring(p_cpf from v_i for 1)` (e no `order by v_i`) passa então a
-- colidir com duas coisas de mesmo nome — a variável PL/pgSQL e a coluna do
-- generate_series — e o Postgres recusa a ambiguidade (plpgsql.variable_
-- conflict = error, o padrão) em vez de adivinhar qual delas usar.
--
-- Correção: usar um alias de relação + coluna explícitos (`serie(posicao)`)
-- só na montagem de `v_digitos`, que não colide com nada. A variável
-- PL/pgSQL `v_i` continua existindo e sendo usada, sem alteração, nos dois
-- loops `for v_i in ...` abaixo — eles nunca tiveram ambiguidade (não há
-- nenhuma coluna chamada v_i no escopo deles), então não precisam mudar.
--
-- Nenhuma regra de validação de CPF muda: mesmo algoritmo, mesmos dígitos
-- verificadores, mesma rejeição de sequência repetida/formato inválido.
create or replace function private.is_valid_cpf(p_cpf text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_digitos int[];
  v_soma int;
  v_digito1 int;
  v_digito2 int;
  v_i int;
begin
  if p_cpf is null or p_cpf !~ '^[0-9]{11}$' then
    return false;
  end if;

  -- sequências repetidas (00000000000, 11111111111, ..., 99999999999)
  if p_cpf ~ '^(\d)\1{10}$' then
    return false;
  end if;

  v_digitos := array(
    select substring(p_cpf from serie.posicao for 1)::int
    from pg_catalog.generate_series(1, 11) as serie(posicao)
    order by serie.posicao
  );

  v_soma := 0;
  for v_i in 1..9 loop
    v_soma := v_soma + v_digitos[v_i] * (11 - v_i);
  end loop;
  v_digito1 := 11 - (v_soma % 11);
  if v_digito1 >= 10 then
    v_digito1 := 0;
  end if;
  if v_digito1 <> v_digitos[10] then
    return false;
  end if;

  v_soma := 0;
  for v_i in 1..10 loop
    v_soma := v_soma + v_digitos[v_i] * (12 - v_i);
  end loop;
  v_digito2 := 11 - (v_soma % 11);
  if v_digito2 >= 10 then
    v_digito2 := 0;
  end if;
  if v_digito2 <> v_digitos[11] then
    return false;
  end if;

  return true;
end;
$$;

-- `create or replace function` preserva os privilégios já concedidos/
-- revogados na function (revoke/grant não são resetados por um replace),
-- mas restauramos o revoke explicitamente aqui por segurança/idempotência —
-- mesmo padrão já usado em 20261005120000_add_profile_access_control.sql
-- para esta mesma função: ela nunca pode ser chamável diretamente por
-- `anon`/`authenticated`, só a partir de outra function SECURITY DEFINER.
revoke all on function private.is_valid_cpf(text) from public, anon, authenticated;
