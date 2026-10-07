-- InvTec — rejeita CPF com checksum inválido já no signup (achado da revisão final)
--
-- Migration ADITIVA: nenhuma migration anterior é editada. `private.handle_new_user`
-- (redefinida pela última vez em 20261007100000_add_notifications.sql) é
-- redefinida aqui via CREATE OR REPLACE (mesma assinatura — preserva
-- owner/ACL; é função de trigger, então não precisa de novo GRANT/REVOKE)
-- só para mover a validação de ALGORITMO do CPF (dígitos verificadores) do
-- momento da APROVAÇÃO para o momento do CADASTRO. Nenhuma outra regra de
-- negócio da função muda (nome/notificação continuam idênticos).
--
-- POR QUE ISTO É UMA CORREÇÃO (e não só um reforço): a migration
-- 20261005120000 documentou explicitamente, na seção 5/6, a decisão de
-- deixar `handle_new_user` aceitar um CPF com dígito verificador inválido
-- e só bloquear isso na aprovação (`aprovar_usuario`) — o raciocínio
-- original era "um erro de digitação no cadastro não pode travar o
-- usuário fora do sistema antes mesmo de existir". Isso continua válido
-- para CPF AUSENTE (regra A abaixo), mas não para CPF INFORMADO E
-- INVÁLIDO: a validação client-side do Flutter (formulário de cadastro)
-- não é autoridade de segurança — ela pode ser contornada por qualquer
-- chamada direta à API do Supabase com `raw_user_meta_data` forjado. Um
-- profile PENDING com CPF matematicamente inválido é um estado que o
-- sistema não deveria permitir existir nem temporariamente: a única saída
-- dele seria a aprovação rejeitar por CPF ruim (`aprovar_usuario` já exige
-- `is_valid_cpf`), nunca a correção do próprio CPF (não há RPC de
-- autoatualização de CPF para o próprio usuário). Abortar no INSERT é
-- estritamente melhor: o cliente recebe o erro imediatamente, no mesmo
-- fluxo em que pode corrigir o formulário, em vez de só descobrir dias
-- depois que o ADMIN rejeitou a solicitação.
--
-- AS 3 REGRAS:
--   A) CPF ausente/NULL/vazio (depois de normalizado para só dígitos) →
--      cria o profile normalmente com cpf = NULL, access_status =
--      PENDING, ativo = false. Preserva compatibilidade com criação
--      administrativa de contas em auth.users sem metadata de CPF (ex.:
--      convite manual via painel do Supabase) — continua se comportando
--      exatamente como antes desta migration.
--   B) CPF informado → normalizado para só dígitos com a MESMA expressão
--      de `public.normalize_profile_cpf` (20261005120000):
--      `nullif(regexp_replace(coalesce(valor, ''), '[^0-9]', '', 'g'), '')`.
--      Em seguida EXIGE `private.is_valid_cpf(v_cpf) = true` (mesma
--      função da 20261005120000 — 11 dígitos, rejeita sequência repetida,
--      confere os 2 dígitos verificadores). Se inválido, a função ABORTA
--      a transação inteira com `raise exception` ANTES de qualquer INSERT
--      em profiles — nunca cria o profile e só reprova depois.
--   C) CPF válido mas duplicado → nenhuma checagem nova é adicionada
--      aqui. `profiles_cpf_key` (índice único parcial, 20261005120000)
--      continua sendo a única e definitiva autoridade: o INSERT abaixo
--      falha com unique_violation (23505) exatamente como já acontecia.
--      Não existe (e não deve existir) um endpoint `cpf_existe(...)` —
--      mesmo motivo documentado em 20261005120000 para `is_valid_cpf`
--      nunca ter GRANT para `authenticated`: evitar que alguém de fora
--      use respostas de erro para enumerar/testar CPFs.
--
-- O que PERMANECE idêntico (fora de escopo desta correção): aprovação,
-- rejeição, bloqueio, permissões, notifications, Realtime, validação
-- client-side do Flutter, CPF legado NULL de contas já existentes,
-- estrutura de `profiles` (cpf continua NULLABLE — nenhuma migration
-- jamais adiciona NOT NULL a essa coluna, nem esta).
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text := coalesce(
    public.normalize_text(new.raw_user_meta_data ->> 'nome'),
    new.email,
    new.id::text
  );
  -- mesma normalização de public.normalize_profile_cpf (20261005120000):
  -- só dígitos, string vazia vira NULL.
  v_cpf text := nullif(regexp_replace(coalesce(new.raw_user_meta_data ->> 'cpf', ''), '[^0-9]', '', 'g'), '');
begin
  -- regra B: só valida quando um CPF foi de fato informado — regra A
  -- (ausente) pula esta checagem inteira e segue para o INSERT com
  -- cpf = NULL.
  if v_cpf is not null and private.is_valid_cpf(v_cpf) is not true then
    raise exception 'CPF inválido.' using errcode = 'P0001';
  end if;

  insert into public.profiles (id, nome, email, cpf, perfil, ativo, access_status, rejection_count)
  values (
    new.id,
    v_nome,
    new.email,
    v_cpf,
    'CONSULTA',
    false,
    'PENDING',
    0
  );

  perform private.notify_admins_access_request(
    new.id,
    'ACCESS_REQUEST_CREATED',
    'Nova solicitação de acesso',
    v_nome || ' solicitou acesso ao InvTec.'
  );

  return new;
end;
$$;
