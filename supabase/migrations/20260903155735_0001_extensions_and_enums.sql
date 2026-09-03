-- 001 Fundaciones · T-02
-- Extensiones y enums base. Ver specs/001-fundaciones/plan.md

create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault;

-- Art. 9.2: el rol vive aquí, nunca en un campo que el cliente pueda editar.
create type public.app_role as enum ('fan', 'organizer', 'staff', 'admin');

create type public.organizer_status as enum ('draft', 'pending', 'approved', 'rejected', 'suspended');

create type public.organizer_role as enum ('owner', 'admin', 'viewer');

comment on type public.app_role is
  'Rol global. fan se asigna al registrarse; admin solo por service_role; organizer y staff se derivan de organizer_members / event_staff y aquí son atajo de navegación.';
