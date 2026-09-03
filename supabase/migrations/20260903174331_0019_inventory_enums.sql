-- 003 · T-01
-- btree_gist: hace falta para meter un uuid con `=` en el índice GiST de la
-- restricción de exclusión que impide fases solapadas (0021).
create extension if not exists btree_gist with schema extensions;

create type public.zone_kind  as enum ('standing', 'seated');
create type public.phase_kind as enum ('presale', 'regular', 'fanpass_presale');

comment on type public.zone_kind is
  'standing: se compra por cantidad, sin segmentos ni asientos. seated: numerada por fila y asiento, y puede tener segmentos de precio.';
