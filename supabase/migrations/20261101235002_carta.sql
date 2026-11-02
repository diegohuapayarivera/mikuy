-- Carta (docs/MODELO-DATOS.md). Las presentaciones no se borran si ya se vendieron: se desactivan.

create table mikuy.categorias (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  nombre text not null check (btrim(nombre) <> ''),
  orden integer not null default 0,
  -- Nula = no se prepara (por ejemplo, derecho de corcho): va directo a caja.
  estacion_id uuid,
  creado_en timestamptz not null default now(),
  unique (restaurante_id, nombre),
  unique (id, restaurante_id),
  foreign key (estacion_id, restaurante_id) references mikuy.estaciones (id, restaurante_id)
);
create index categorias_estacion_idx on mikuy.categorias (estacion_id, restaurante_id);

create table mikuy.platos (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  categoria_id uuid not null,
  nombre text not null check (btrim(nombre) <> ''),
  descripcion text,
  -- Anula la estación de la categoría.
  estacion_id uuid,
  disponible boolean not null default true,
  orden integer not null default 0,
  creado_en timestamptz not null default now(),
  unique (categoria_id, nombre),
  unique (id, restaurante_id),
  foreign key (categoria_id, restaurante_id) references mikuy.categorias (id, restaurante_id),
  foreign key (estacion_id, restaurante_id) references mikuy.estaciones (id, restaurante_id)
);
create index platos_restaurante_idx on mikuy.platos (restaurante_id);
create index platos_categoria_idx on mikuy.platos (categoria_id, restaurante_id);
create index platos_estacion_idx on mikuy.platos (estacion_id, restaurante_id);

create table mikuy.presentaciones (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  plato_id uuid not null,
  nombre text not null default 'Normal' check (btrim(nombre) <> ''),
  precio numeric(10, 2) not null check (precio >= 0),
  activa boolean not null default true,
  -- Cocina la marca agotada "hoy" (fecha de la jornada del restaurante).
  agotada_en date,
  orden integer not null default 0,
  creado_en timestamptz not null default now(),
  unique (plato_id, nombre),
  unique (id, restaurante_id),
  foreign key (plato_id, restaurante_id) references mikuy.platos (id, restaurante_id)
);
create index presentaciones_restaurante_idx on mikuy.presentaciones (restaurante_id);
create index presentaciones_plato_idx on mikuy.presentaciones (plato_id, restaurante_id);

alter table mikuy.categorias enable row level security;
alter table mikuy.platos enable row level security;
alter table mikuy.presentaciones enable row level security;

create policy categorias_miembros_leen on mikuy.categorias for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy platos_miembros_leen on mikuy.platos for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy presentaciones_miembros_leen on mikuy.presentaciones for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));

grant select on mikuy.categorias, mikuy.platos, mikuy.presentaciones to authenticated;
