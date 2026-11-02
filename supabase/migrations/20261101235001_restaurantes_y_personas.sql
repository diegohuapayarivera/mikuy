-- Restaurante y personas (docs/MODELO-DATOS.md).
--
-- Las funciones que usan las políticas RLS son SECURITY DEFINER y viven en mikuy_privado, un esquema
-- que la Data API no expone: así no se pueden llamar por /rest/v1/rpc (lint 0029 de Supabase).

create schema if not exists mikuy_privado;
revoke all on schema mikuy_privado from public;
grant usage on schema mikuy_privado to authenticated, service_role;

-- Ninguna función nueva queda ejecutable por public sin un grant explícito.
alter default privileges in schema mikuy revoke execute on functions from public;
alter default privileges in schema mikuy_privado revoke execute on functions from public;

-- La tabla interna de migraciones no se lee desde la API; la política lo deja explícito.
create policy migraciones_sin_acceso on mikuy.migraciones for select to authenticated using (false);

create type mikuy.plan_restaurante as enum ('basico', 'completo');
create type mikuy.color_restaurante as enum ('aji', 'anil', 'algarrobo');
-- Por encima del personal solo existe administrador (lo usa la dueña o la administradora).
create type mikuy.rol_perfil as enum ('administrador', 'mozo', 'estacion', 'portero');

create function mikuy_privado.zona_horaria_valida(p_zona text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
  perform pg_catalog.timezone(p_zona, '2000-01-01 00:00:00+00'::timestamptz);
  return true;
exception
  when invalid_parameter_value then
    return false;
end;
$$;
revoke execute on function mikuy_privado.zona_horaria_valida(text) from public;

create table mikuy.restaurantes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null check (btrim(nombre) <> ''),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  plan mikuy.plan_restaurante not null default 'basico',
  color mikuy.color_restaurante not null default 'aji',
  zona_horaria text not null default 'America/Lima'
    check (mikuy_privado.zona_horaria_valida(zona_horaria)),
  usa_portero boolean not null default false,
  -- Promedio general de preparación de la cocina; lo edita el administrador.
  tiempo_prep_min integer not null default 25 check (tiempo_prep_min > 0),
  pin_minutos integer not null default 30 check (pin_minutos between 5 and 1440),
  creado_en timestamptz not null default now()
);

-- Umbrales de Salud por área (bien / atento; más allá es "revisar") y minutos de aviso.
create table mikuy.config_salud (
  restaurante_id uuid primary key references mikuy.restaurantes (id),
  ventas_bien_pct integer not null check (ventas_bien_pct between 0 and 1000),
  ventas_atento_pct integer not null check (ventas_atento_pct between 0 and 1000),
  cocina_bien_min integer not null check (cocina_bien_min > 0),
  cocina_atento_min integer not null,
  salon_bien_min integer not null check (salon_bien_min > 0),
  salon_atento_min integer not null,
  caja_bien_min integer not null check (caja_bien_min > 0),
  caja_atento_min integer not null,
  carta_bien_agotados integer not null check (carta_bien_agotados >= 0),
  carta_atento_agotados integer not null,
  equipo_bien_mesas integer not null check (equipo_bien_mesas > 0),
  equipo_atento_mesas integer not null,
  aviso_plato_min integer not null check (aviso_plato_min > 0),
  aviso_bebida_min integer not null check (aviso_bebida_min > 0),
  aviso_mesa_sin_pedir_min integer not null check (aviso_mesa_sin_pedir_min > 0),
  aviso_cuenta_min integer not null check (aviso_cuenta_min > 0),
  actualizado_en timestamptz not null default now(),
  -- En ventas, más es mejor; en el resto, menos es mejor.
  check (ventas_atento_pct <= ventas_bien_pct),
  check (cocina_bien_min <= cocina_atento_min),
  check (salon_bien_min <= salon_atento_min),
  check (caja_bien_min <= caja_atento_min),
  check (carta_bien_agotados <= carta_atento_agotados),
  check (equipo_bien_mesas <= equipo_atento_mesas)
);

create table mikuy.estaciones (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  nombre text not null check (btrim(nombre) <> ''),
  orden integer not null default 0,
  creado_en timestamptz not null default now(),
  unique (restaurante_id, nombre),
  unique (id, restaurante_id)
);

create table mikuy.perfiles (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  user_id uuid references auth.users (id) on delete set null,
  nombre text not null check (btrim(nombre) <> ''),
  rol mikuy.rol_perfil not null,
  estacion_id uuid,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  unique (id, restaurante_id),
  foreign key (estacion_id, restaurante_id) references mikuy.estaciones (id, restaurante_id),
  check ((rol = 'estacion') = (estacion_id is not null))
);
create index perfiles_restaurante_idx on mikuy.perfiles (restaurante_id);
create index perfiles_estacion_idx on mikuy.perfiles (estacion_id, restaurante_id);
create index perfiles_user_idx on mikuy.perfiles (user_id);
-- Un usuario tiene a lo sumo un perfil activo: perfil_actual() y restaurante_actual() son únicos.
create unique index perfiles_un_activo_por_usuario on mikuy.perfiles (user_id)
  where activo and user_id is not null;

-- PIN de un solo uso. Solo se guarda el hash; nunca se lee desde la API.
create table mikuy.pines (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  perfil_id uuid not null,
  hash text not null check (length(hash) >= 20),
  expira_en timestamptz not null,
  usado_en timestamptz,
  creado_en timestamptz not null default now(),
  foreign key (perfil_id, restaurante_id) references mikuy.perfiles (id, restaurante_id)
);
create index pines_restaurante_idx on mikuy.pines (restaurante_id);
create index pines_perfil_idx on mikuy.pines (perfil_id, restaurante_id);
-- Un solo PIN sin usar por perfil: generar uno nuevo reemplaza al anterior.
create unique index pines_uno_vigente_por_perfil on mikuy.pines (perfil_id) where usado_en is null;

-- Perfil y restaurante de la sesión. El tenant siempre sale de aquí, nunca del cliente.
create function mikuy_privado.perfil_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id
  from mikuy.perfiles p
  where p.user_id = (select auth.uid()) and p.activo
$$;

create function mikuy_privado.restaurante_actual()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.restaurante_id
  from mikuy.perfiles p
  where p.user_id = (select auth.uid()) and p.activo
$$;

create function mikuy_privado.rol_actual()
returns mikuy.rol_perfil
language sql
stable
security definer
set search_path = ''
as $$
  select p.rol
  from mikuy.perfiles p
  where p.user_id = (select auth.uid()) and p.activo
$$;

revoke execute on function mikuy_privado.perfil_actual() from public;
revoke execute on function mikuy_privado.restaurante_actual() from public;
grant execute on function mikuy_privado.perfil_actual() to authenticated, service_role;
grant execute on function mikuy_privado.restaurante_actual() to authenticated, service_role;
revoke execute on function mikuy_privado.rol_actual() from public;
grant execute on function mikuy_privado.rol_actual() to authenticated, service_role;

-- RLS por membresía: solo quien tiene perfil activo en el restaurante lee sus filas.
alter table mikuy.restaurantes enable row level security;
alter table mikuy.config_salud enable row level security;
alter table mikuy.estaciones enable row level security;
alter table mikuy.perfiles enable row level security;
alter table mikuy.pines enable row level security;

create policy restaurantes_miembros_leen on mikuy.restaurantes for select to authenticated
  using (id = (select mikuy_privado.restaurante_actual()));
create policy config_salud_miembros_leen on mikuy.config_salud for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy estaciones_miembros_leen on mikuy.estaciones for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy perfiles_miembros_leen on mikuy.perfiles for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy pines_sin_acceso on mikuy.pines for select to authenticated using (false);

-- Solo lectura; las escrituras van por RPC. pines no se lee.
grant select on mikuy.restaurantes, mikuy.config_salud, mikuy.estaciones, mikuy.perfiles
  to authenticated;
