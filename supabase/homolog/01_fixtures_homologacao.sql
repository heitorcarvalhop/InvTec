-- =============================================================================
-- PROMPT 11.3.4 — Fixtures de HOMOLOGAÇÃO (setores, localizações, usuários
-- de teste, patrimônios fictícios).
--
-- SÓ RODAR DEPOIS de, nesta ordem (PROMPT 11.3.4.1):
--   1. `00_check_target_not_producao.sh env/homologacao.env` (Git Bash) OU
--      `00_check_target_not_producao.ps1 -HomologEnvFile env\homologacao.env`
--      (PowerShell) ter impresso "LIBERADO" — inclui a confirmação visual
--      do ref do Dashboard, não só a comparação de arquivos;
--   2. Colar este SQL na MESMA aba do Dashboard cujo ref você acabou de
--      confirmar no passo 1 — rodar o script de guarda no terminal NÃO
--      protege sozinho um SQL colado numa aba diferente/antiga do
--      navegador (ver cabeçalho do script de guarda).
--
-- TUDO aqui usa o prefixo ZZ_HOMOLOG_ (setores/localizações) ou
-- ZZHOMOLOG- (número de patrimônio) — nunca os 33 bens reais do Despacho
-- 577, nunca dados de produção. Idempotente: cada INSERT só roda se a
-- linha ainda não existir (comparação pelo nome/sigla fictícios).
-- =============================================================================

-- =============================================================================
-- PASSO 1 — SETORES E LOCALIZAÇÕES FICTÍCIOS
-- =============================================================================

insert into public.setores (nome, sigla, descricao)
select v.nome, v.sigla, 'Setor fictício de homologação — PROMPT 11.3.4, nunca usar como setor real'
from (values
  ('ZZ_HOMOLOG_GETEC', 'ZZHGETEC'),
  ('ZZ_HOMOLOG_GEASI', 'ZZHGEASI'),
  ('ZZ_HOMOLOG_GESOL', 'ZZHGESOL'),
  ('ZZ_HOMOLOG_CIMEHGO', 'ZZHCIMEH')
) as v(nome, sigla)
where not exists (select 1 from public.setores s where s.sigla = v.sigla);

insert into public.localizacoes (setor_id, nome, sigla)
select s.id, v.nome, v.sigla
from public.setores s
join (values
  ('ZZHGETEC', 'Sala fictícia GETEC 1', 'ZZHG-01'),
  ('ZZHGEASI', 'Sala fictícia GEASI 1', 'ZZHA-01'),
  ('ZZHGESOL', 'Sala fictícia GESOL 1', 'ZZHS-01'),
  ('ZZHCIMEH', 'Sala fictícia CIMEHGO 1', 'ZZHC-01')
) as v(setor_sigla, nome, sigla) on v.setor_sigla = s.sigla
where not exists (
  select 1 from public.localizacoes l where l.sigla = v.sigla
);

-- =============================================================================
-- PASSO 2 — USUÁRIOS DE TESTE (ADMIN / GESTOR / OPERADOR / CONSULTA)
-- =============================================================================
-- `profiles` NÃO aceita INSERT direto (só a trigger `handle_new_user`, que
-- dispara quando um usuário é criado no Supabase Auth — ver migration
-- inicial). Passo MANUAL, fora deste SQL, ANTES de continuar:
--
--   1. No projeto de HOMOLOGAÇÃO (nunca produção): Authentication > Add
--      user (ou a Admin API) — crie 4 usuários com e-mails claramente
--      fictícios, ex.:
--        zzhomolog.admin@invtec.test
--        zzhomolog.gestor@invtec.test
--        zzhomolog.operador@invtec.test
--        zzhomolog.consulta@invtec.test
--      Senha: qualquer uma gerada só para teste — NUNCA reaproveitar senha
--      real de ninguém (seção 1 do prompt).
--   2. A trigger cria a linha em `profiles` automaticamente, com
--      perfil='CONSULTA' e ativo=false (padrão de segurança). Rode o bloco
--      abaixo (como o role `postgres`/dono do SQL Editor, que não está
--      sujeito a RLS) para promover cada um ao perfil correto:

update public.profiles set perfil = 'ADMIN', ativo = true
where email = 'zzhomolog.admin@invtec.test';

update public.profiles set perfil = 'GESTOR', ativo = true
where email = 'zzhomolog.gestor@invtec.test';

update public.profiles set perfil = 'OPERADOR', ativo = true
where email = 'zzhomolog.operador@invtec.test';

update public.profiles set perfil = 'CONSULTA', ativo = true
where email = 'zzhomolog.consulta@invtec.test';

-- Um quinto usuário, deixado SEM promover (perfil=CONSULTA, ativo=false,
-- o padrão da trigger) serve como caso "authenticated sem perfil ativo"
-- da seção 7 do prompt — não precisa de UPDATE nenhum, só criar o usuário
-- (ex.: zzhomolog.semperfil@invtec.test) e deixá-lo como está.

-- Conferência (nunca deveria retornar 0 linhas antes de seguir para o
-- roteiro de testes):
select email, perfil, ativo from public.profiles where email like 'zzhomolog.%@invtec.test' order by email;

-- =============================================================================
-- PASSO 3 — PATRIMÔNIOS FICTÍCIOS
-- =============================================================================
-- `criado_por` exige um profile já existente — rode isto DEPOIS do passo 2.
-- Números de patrimônio com o prefixo ZZHOMOLOG- (nunca confundíveis com
-- os 8 dígitos reais da GETEC).

insert into public.patrimonios (numero_patrimonio, tipo_id, setor_atual_id, status, criado_por, descricao)
select v.numero, t.id, s.id, 'DISPONIVEL', p.id, 'Patrimônio fictício de homologação — PROMPT 11.3.4'
from (values
  ('ZZHOMOLOG-000001', 'Notebook', 'ZZHGETEC'),
  ('ZZHOMOLOG-000002', 'Monitor', 'ZZHGETEC'),
  ('ZZHOMOLOG-000003', 'Notebook', 'ZZHGEASI'),
  ('ZZHOMOLOG-000004', 'Monitor', 'ZZHGESOL'),
  ('ZZHOMOLOG-000005', 'Estabilizador', 'ZZHCIMEH')
) as v(numero, tipo_nome, setor_sigla)
join public.tipos_patrimonio t on t.nome = v.tipo_nome
join public.setores s on s.sigla = v.setor_sigla
cross join lateral (
  select id from public.profiles where email = 'zzhomolog.admin@invtec.test' limit 1
) as p
where not exists (select 1 from public.patrimonios px where px.numero_patrimonio = v.numero);

-- Conferência:
select numero_patrimonio, status, setor_atual_id from public.patrimonios where numero_patrimonio like 'ZZHOMOLOG-%' order by numero_patrimonio;
