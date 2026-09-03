-- 001 Fundaciones · T-11, T-12, T-13
-- Art. 7.1-7.2.
--
-- Por qué HMAC con pepper y no bcrypt: el DNI se necesita DETERMINISTA — la
-- nominación compara asistente contra titular y el modo DNI del validador (D-03)
-- busca por documento. Eso descarta un hash con salt por fila.
-- Y por qué con pepper y no SHA-256 desnudo: 8 dígitos son 10^8 candidatos, el
-- diccionario completo se genera en segundos. Sin el pepper no hay fuerza bruta.

-- T-11: el pepper se crea una vez. No rota sin un plan de re-hasheo, porque no se
-- puede re-derivar sin el DNI original. Respaldo custodiado antes de producción (D-10).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'dni_pepper') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'dni_pepper',
      'Pepper HMAC para profiles.dni_hash. Art. 7.1. Perderlo invalida todos los hashes.'
    );
  end if;
end $$;

-- AC-08, AC-09
create or replace function public.hash_dni(p_dni text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_pepper text;
begin
  if p_dni is null or p_dni !~ '^[0-9]{8}$' then
    raise exception 'DNI inválido: se esperan 8 dígitos' using errcode = '22023';
  end if;

  select decrypted_secret into strict v_pepper
    from vault.decrypted_secrets where name = 'dni_pepper';

  return encode(extensions.hmac(p_dni, v_pepper, 'sha256'), 'hex');
end $$;

-- Revocada al cliente: si pudiera llamarla tendría un oráculo para confirmar el
-- DNI de cualquier persona. Solo la usan las funciones security definer de
-- nominación (004) y de puerta (006).
revoke all on function public.hash_dni(text) from public, anon, authenticated;

-- AC-06, AC-08: el fan declara su DNI; el servidor hashea. El cliente nunca
-- escribe dni_hash — si pudiera, copiaría el hash de otra persona y se haría
-- pasar por ella en puerta.
create or replace function public.set_own_dni(p_dni text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'no autenticado' using errcode = '28000';
  end if;

  update public.profiles
     set dni_hash  = public.hash_dni(p_dni),
         dni_last4 = right(p_dni, 4)
   where id = v_uid;
end $$;

-- AC-07: D-10 — sin proveedor de KYC, el sello es manual y es de Admin.
create or replace function public.verify_dni(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.auth_is_admin() then
    raise exception 'solo Admin' using errcode = '42501';
  end if;

  update public.profiles
     set dni_verified_at = now()
   where id = p_user_id and dni_hash is not null;

  if not found then
    raise exception 'perfil inexistente o sin DNI declarado' using errcode = '22023';
  end if;
end $$;

revoke all on function public.set_own_dni(text)  from public, anon;
revoke all on function public.verify_dni(uuid)   from public, anon;
grant execute on function public.set_own_dni(text) to authenticated;
grant execute on function public.verify_dni(uuid)  to authenticated;
