-- 004 · Art. 7.1. Lo destapó la prueba de extremo a extremo del checkout.
--
-- 001 cerró `profiles.dni_hash` sacándolo a `profile_identity`, y `ticket_secrets`
-- con RLS sin políticas. Pero 004 volvió a exponer la misma clase de dato en dos
-- tablas nuevas: `order_items.attendee_dni_hash` y `tickets.holder_dni_hash` eran
-- legibles por el cliente.
--
-- SEVERIDAD, sin dramatizar: baja. La RLS limita a las órdenes y tickets propios,
-- así que un comprador solo veía hashes de DNIs que él mismo tecleó — y conocer
-- HMAC(X) para una X que ya sabes no aporta nada. Tampoco se puede escribir:
-- solo entra por set_item_attendee, que hashea en el servidor.
--
-- Aun así se cierra, por dos razones concretas:
--   1. Dos compradores que nominen a la MISMA persona veían el mismo hash, y con
--      eso pueden deducir que es la misma persona. Es una inferencia entre
--      usuarios que el diseño no pretendía.
--   2. Una regla con excepciones calladas deja de ser regla. El Art. 7.1 dice
--      que el hash no sale de la base; que salga «solo un poco» es cómo empiezan
--      estas cosas.
--
-- Se hace con privilegio de columna, no con tabla aparte: aquí el cliente sí
-- necesita casi todas las columnas, y ya pide listas explícitas. El riesgo de
-- 001 —que alguien lo «arregle» con un `grant select` de tabla y reabra el
-- agujero— se cubre con una comprobación en la suite, que es justo para lo que
-- sirve una prueba.
--
-- ORDEN IMPORTANTE (lección de 0007): primero revocar el privilegio de TABLA,
-- después conceder columna por columna. Un `revoke select (col)` sobre un grant
-- de tabla no hace nada, y no avisa.

revoke select on public.order_items from authenticated, anon;
grant select (
  id, order_id, price_tier_id, seat_id, unit_price_cents,
  attendee_name, attendee_dni_last4, nominated_at, created_at
) on public.order_items to authenticated;

revoke select on public.tickets from authenticated, anon;
grant select (
  id, code, event_id, order_item_id, zone_id, seat_id,
  owner_id, original_owner_id,
  holder_name, holder_dni_last4,
  status, face_value_cents, resale_count,
  qr_available_from, issued_at, used_at
) on public.tickets to authenticated;

comment on column public.order_items.attendee_dni_hash is
  'Art. 7.1: no legible por el cliente. Solo lo escribe set_item_attendee y solo lo lee la validación de puerta (006), que corre con service_role.';
comment on column public.tickets.holder_dni_hash is
  'Art. 7.1: no legible por el cliente. Es el identificador con el que se valida en puerta; el modo DNI de 006 lo compara desde el servidor.';
