-- Salón y pedidos (docs/MODELO-DATOS.md). Una fila por unidad en items; la UI agrupa.

create type mikuy.tipo_atencion as enum ('mesa', 'llevar');
create type mikuy.estado_atencion as enum ('abierta', 'cerrada');
create type mikuy.estado_item as enum (
  'pendiente', 'preparando', 'listo', 'entregado', 'no_disponible', 'anulado'
);

create table mikuy.mesas (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  nombre text not null check (btrim(nombre) <> ''),
  orden integer not null default 0,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  unique (restaurante_id, nombre),
  unique (id, restaurante_id)
);

-- "Hoy" es la fecha del calendario en la zona horaria del restaurante.
create function mikuy_privado.jornada_de(p_restaurante uuid, p_momento timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (p_momento at time zone r.zona_horaria)::date
  from mikuy.restaurantes r
  where r.id = p_restaurante
$$;
revoke execute on function mikuy_privado.jornada_de(uuid, timestamptz) from public;

create table mikuy.atenciones (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  tipo mikuy.tipo_atencion not null,
  nombre_llevar text,
  -- Del mozo que toma el primer pedido; nulo mientras nadie pide (portero).
  mozo_id uuid,
  personas integer check (personas > 0),
  estado mikuy.estado_atencion not null default 'abierta',
  -- La fija el trigger desde abierta_en y la zona horaria del restaurante.
  jornada date not null,
  abierta_en timestamptz not null default now(),
  cerrada_en timestamptz,
  unique (id, restaurante_id),
  foreign key (mozo_id, restaurante_id) references mikuy.perfiles (id, restaurante_id),
  check ((tipo = 'llevar') = (nombre_llevar is not null)),
  check (nombre_llevar is null or btrim(nombre_llevar) <> ''),
  check ((estado = 'cerrada') = (cerrada_en is not null)),
  check (cerrada_en is null or cerrada_en >= abierta_en)
);
create index atenciones_restaurante_jornada_idx on mikuy.atenciones (restaurante_id, jornada);
create index atenciones_mozo_idx on mikuy.atenciones (mozo_id, restaurante_id);

create function mikuy_privado.atenciones_fijar_jornada()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.jornada := mikuy_privado.jornada_de(new.restaurante_id, new.abierta_en);
  return new;
end;
$$;
revoke execute on function mikuy_privado.atenciones_fijar_jornada() from public;

create trigger atenciones_fijar_jornada
  before insert or update of abierta_en, restaurante_id on mikuy.atenciones
  for each row execute function mikuy_privado.atenciones_fijar_jornada();

-- Juntar = varias filas abiertas; separar = cerrar una fila (hasta).
create table mikuy.atencion_mesas (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  atencion_id uuid not null,
  mesa_id uuid not null,
  desde timestamptz not null default now(),
  hasta timestamptz,
  foreign key (atencion_id, restaurante_id) references mikuy.atenciones (id, restaurante_id),
  foreign key (mesa_id, restaurante_id) references mikuy.mesas (id, restaurante_id),
  check (hasta is null or hasta >= desde)
);
create index atencion_mesas_restaurante_idx on mikuy.atencion_mesas (restaurante_id);
create index atencion_mesas_atencion_idx on mikuy.atencion_mesas (atencion_id, restaurante_id);
create index atencion_mesas_mesa_idx on mikuy.atencion_mesas (mesa_id, restaurante_id);
-- Una mesa está a lo sumo en una atención abierta.
create unique index atencion_mesas_una_abierta_por_mesa on mikuy.atencion_mesas (mesa_id)
  where hasta is null;

-- Lo que el mozo manda de una vez. Reintentar con la misma llave no duplica.
create table mikuy.envios (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  atencion_id uuid not null,
  mozo_id uuid not null,
  llave_idempotencia uuid not null,
  enviado_en timestamptz not null default now(),
  unique (restaurante_id, llave_idempotencia),
  unique (id, restaurante_id),
  unique (id, atencion_id, restaurante_id),
  foreign key (atencion_id, restaurante_id) references mikuy.atenciones (id, restaurante_id),
  foreign key (mozo_id, restaurante_id) references mikuy.perfiles (id, restaurante_id)
);
create index envios_atencion_idx on mikuy.envios (atencion_id, restaurante_id);
create index envios_mozo_idx on mikuy.envios (mozo_id, restaurante_id);

-- Unidades que una estación empieza juntas.
create table mikuy.tandas (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  estacion_id uuid not null,
  iniciada_por uuid not null,
  iniciada_en timestamptz not null default now(),
  unique (id, restaurante_id),
  foreign key (estacion_id, restaurante_id) references mikuy.estaciones (id, restaurante_id),
  foreign key (iniciada_por, restaurante_id) references mikuy.perfiles (id, restaurante_id)
);
create index tandas_restaurante_idx on mikuy.tandas (restaurante_id);
create index tandas_estacion_idx on mikuy.tandas (estacion_id, restaurante_id);
create index tandas_iniciada_por_idx on mikuy.tandas (iniciada_por, restaurante_id);

-- Una fila por unidad. Nombre, presentación, precio y estación se congelan al pedir.
create table mikuy.items (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  atencion_id uuid not null,
  envio_id uuid not null,
  presentacion_id uuid not null,
  plato_nombre text not null,
  presentacion_nombre text not null,
  precio numeric(10, 2) not null check (precio >= 0),
  -- Nula = no se prepara.
  estacion_id uuid,
  nota text,
  estado mikuy.estado_item not null default 'pendiente',
  tanda_id uuid,
  cortesia_motivo text,
  anulado_motivo text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (id, restaurante_id),
  unique (id, atencion_id, restaurante_id),
  foreign key (atencion_id, restaurante_id) references mikuy.atenciones (id, restaurante_id),
  -- El envío es de la misma atención que la unidad.
  foreign key (envio_id, atencion_id, restaurante_id)
    references mikuy.envios (id, atencion_id, restaurante_id),
  foreign key (presentacion_id, restaurante_id)
    references mikuy.presentaciones (id, restaurante_id),
  foreign key (estacion_id, restaurante_id) references mikuy.estaciones (id, restaurante_id),
  foreign key (tanda_id, restaurante_id) references mikuy.tandas (id, restaurante_id),
  check ((estado = 'anulado') = (anulado_motivo is not null)),
  check (anulado_motivo is null or btrim(anulado_motivo) <> ''),
  check (cortesia_motivo is null or btrim(cortesia_motivo) <> '')
);
create index items_atencion_idx on mikuy.items (atencion_id, restaurante_id);
create index items_envio_idx on mikuy.items (envio_id, atencion_id, restaurante_id);
create index items_presentacion_idx on mikuy.items (presentacion_id, restaurante_id);
create index items_estacion_estado_idx on mikuy.items (estacion_id, restaurante_id, estado);
create index items_tanda_idx on mikuy.items (tanda_id, restaurante_id);
create index items_restaurante_estado_idx on mikuy.items (restaurante_id, estado);

-- Máquina de estados de la unidad. Toda unidad nace pendiente.
--   pendiente → preparando → listo → entregado
--   pendiente → no_disponible
--   pendiente → entregado, solo si no se prepara (sin estación)
--   cualquiera antes de entregado → anulado (con motivo; que sea el administrador lo valida la RPC)
create function mikuy_privado.items_validar_estado()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.estado <> 'pendiente' then
      raise exception 'Una unidad nace pendiente, no %', new.estado
        using errcode = 'check_violation';
    end if;
  elsif new.estado is distinct from old.estado then
    if not (
      (old.estado = 'pendiente' and new.estado in ('preparando', 'no_disponible'))
      or (old.estado = 'preparando' and new.estado = 'listo')
      or (old.estado = 'listo' and new.estado = 'entregado')
      or (old.estado = 'pendiente' and new.estado = 'entregado' and new.estacion_id is null)
      or (old.estado in ('pendiente', 'preparando', 'listo', 'no_disponible')
          and new.estado = 'anulado')
    ) then
      raise exception 'Transición no permitida: % → %', old.estado, new.estado
        using errcode = 'check_violation';
    end if;
  end if;
  new.actualizado_en := now();
  return new;
end;
$$;
revoke execute on function mikuy_privado.items_validar_estado() from public;

create trigger items_validar_estado
  before insert or update on mikuy.items
  for each row execute function mikuy_privado.items_validar_estado();

alter table mikuy.mesas enable row level security;
alter table mikuy.atenciones enable row level security;
alter table mikuy.atencion_mesas enable row level security;
alter table mikuy.envios enable row level security;
alter table mikuy.tandas enable row level security;
alter table mikuy.items enable row level security;

create policy mesas_miembros_leen on mikuy.mesas for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy atenciones_miembros_leen on mikuy.atenciones for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy atencion_mesas_miembros_leen on mikuy.atencion_mesas for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy envios_miembros_leen on mikuy.envios for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy tandas_miembros_leen on mikuy.tandas for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy items_miembros_leen on mikuy.items for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));

grant select on mikuy.mesas, mikuy.atenciones, mikuy.atencion_mesas, mikuy.envios, mikuy.tandas,
  mikuy.items to authenticated;
