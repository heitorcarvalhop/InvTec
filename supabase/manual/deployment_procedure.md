# InvTec — Procedimento manual de aplicação do módulo de usuários

Guia de referência para aplicação MANUAL (SQL Editor do Supabase) das migrations
do módulo de usuários. Nada aqui é executado automaticamente — é um roteiro
para o administrador copiar/colar passo a passo. Revisado nas etapas de
auditoria final (migrations/RLS/grants/SECURITY DEFINER/backfill/rollback) e
atualizado com a correção de validação de CPF no cadastro.

## PASSO 0 — Backup / recuperação

Antes de aplicar qualquer migration:

- Confirme no painel Supabase (Database > Backups) que o backup diário
  automático do plano atual está ativo e rodou recentemente.
- Se o plano incluir PITR (Point-in-Time Recovery), anote o horário exato de
  início do PASSO 2 para poder restaurar para "1 minuto antes" se algo der
  errado.
- Alternativa/complemento: rode um `pg_dump` manual (painel ou
  `supabase db dump`) e guarde o arquivo localmente antes de prosseguir.

Não criar segundo ambiente, staging ou Docker — use só os recursos padrão do
plano Supabase contratado.

## PASSO 0.1 — Política de senha no Supabase Auth (checklist, não migration)

Antes de liberar o cadastro público, confira manualmente no painel Supabase
(Authentication > Policies, ou Authentication > Settings, dependendo da
versão do painel) a configuração de requisitos de senha disponível:

- Se houver campo de **comprimento mínimo**: defina como **12**.
- Se houver um seletor de **requisitos de caracteres** (ex. "Letters and
  digits" / "Lowercase, uppercase letters, digits" / "Lowercase, uppercase
  letters, digits and symbols" — a redação exata varia por versão do
  painel): selecione a opção **mais forte disponível** (idealmente
  maiúscula+minúscula+dígito+símbolo).
- **Se o painel não permitir configurar exatamente a regra do InvTec**
  (mínimo 12 + maiúscula + minúscula + número + especial, todos
  simultaneamente) — isso é uma limitação conhecida da plataforma, não um
  bug do projeto. Não inventar um sistema de senha paralelo, não criar
  tabela/trigger própria de senha, não armazenar senha fora do Supabase
  Auth. O Flutter já aplica a regra completa client-side antes de qualquer
  cadastro (`lib/features/auth/domain/signup_validators.dart`:
  `validarSenha`/`avaliarRequisitosSenha`) — isso é uma camada de
  produto/UX, não um substituto da autoridade do Supabase Auth sobre o
  armazenamento de senhas (o Auth sempre as armazena com hash seguro,
  independente da política de complexidade configurada).

## PASSO 1 — Pré-checagem (somente leitura)

Abrir `supabase/manual/pre_user_module_checks.sql`, colar INTEIRO no SQL
Editor, executar, e **guardar a saída de cada bloco** (especialmente a
contagem total de profiles e a lista de ADMINs) — o pós-check depende de
comparar contra estes números.

## PASSOS 2-10 — Migrations, na ordem exata

Um passo por arquivo. Para cada um: abrir o arquivo, colar o conteúdo
INTEIRO no SQL Editor, executar, confirmar sucesso antes de ir para o
próximo.

| Passo | Arquivo |
|---|---|
| 2 | `supabase/migrations/20261005120000_add_profile_access_control.sql` |
| 3 | `supabase/migrations/20261005130000_add_admin_user_rpcs.sql` |
| 4 | `supabase/migrations/20261006100000_add_permission_catalog.sql` |
| 5 | `supabase/migrations/20261006110000_add_has_permission_and_override_rpcs.sql` |
| 6 | `supabase/migrations/20261006120000_migrate_business_authorization_to_permissions.sql` (arquivo grande, ~2000 linhas — confirme que o SQL Editor não truncou nada antes de executar) |
| 7 | `supabase/migrations/20261007100000_add_notifications.sql` |
| 8 | `supabase/migrations/20261008100000_add_notifications_unique_constraint.sql` |
| 9 | `supabase/migrations/20261008110000_add_profiles_realtime.sql` |
| 10 | `supabase/migrations/20261008120000_reject_invalid_cpf_on_signup.sql` |

## PASSO 11 — Pós-checagem (somente leitura)

Abrir `supabase/manual/post_user_module_checks.sql`, colar INTEIRO,
executar, comparar cada bloco contra a saída do PASSO 1 e contra os valores
esperados documentados nos comentários do próprio arquivo (14 permissions,
43 role_permissions no total, zero violações de invariante, etc.).

## Pontos críticos de reversão (documentação, não script)

Nenhum script de rollback destrutivo é fornecido de propósito — estas
migrations alteram autenticação/autorização; a preferência em caso de falha
real é restaurar o backup/PITR ou corrigir a migration conscientemente,
nunca um `DROP CASCADE` genérico.

- Se um PASSO de migration falhar no meio (ex. a constraint
  `profiles_ativo_access_status_coerente` rejeitar alguma linha inesperada):
  restaure pelo PITR/backup para antes daquele passo — nunca tente
  "completar na mão" uma migration que falhou pela metade.
- Se depois do PASSO 6 algum ADMIN relatar perda de acesso a uma tela de
  negócio: verifique primeiro `role_permissions`/`user_permissions` antes de
  qualquer rollback — é muito mais provável ser um override do que uma
  falha estrutural.
- Se o PASSO 11 mostrar qualquer linha nos SELECTs de "zero violações
  esperadas" (invariante `ativo`↔`access_status`) ou um ADMIN faltando na
  listagem de administradores: pare imediatamente e restaure pelo
  backup/PITR antes de deixar qualquer usuário final operar o sistema.

## Smoke test pós-deploy (ver relatório da revisão final para o roteiro completo)

ADMIN existente (login, Dashboard, Patrimônios, Movimentações,
Administração, sino) → novo usuário (cadastro, PENDING, notificação chega
ao ADMIN, aprovação como CONSULTA, usuário recebe a mudança e entra) →
permissões (negar uma ação, UI some, servidor também nega) → rejeição
(cadastrar usuário de teste, rejeitar, reenviar, confirmar nova
notificação). Não usar dados patrimoniais reais para testes destrutivos.
