-- InvTec — reforço de schema: UNIQUE(event_id, destinatario_id) em
-- public.notifications (Etapa 5).
--
-- Migration ADITIVA: só acrescenta uma constraint à tabela criada em
-- 20261007100000_add_notifications.sql; nenhuma coluna, função ou policy é
-- alterada.
--
-- POR QUE É SEGURO ADICIONAR: `private.notify_admins_access_request`
-- (migration anterior, seção 2) gera um `event_id` NOVO por chamada e faz um
-- único INSERT...SELECT que varre `profiles` uma vez — cada ADMIN ACTIVE
-- aparece no máximo uma vez nesse SELECT, então no máximo uma linha por
-- (event_id, destinatario_id) já é gerada hoje. A constraint não corrige um
-- bug: só torna essa garantia explícita no schema, para que uma mudança
-- futura na função (ex.: um JOIN introduzido sem cuidado) quebre no INSERT
-- em vez de silenciosamente duplicar o aviso do mesmo evento para o mesmo
-- ADMIN. Projeto em desenvolvimento, sem dados reais em produção — não há
-- violação pré-existente possível para este ALTER TABLE falhar.
alter table public.notifications
  add constraint notifications_event_destinatario_unique unique (event_id, destinatario_id);
