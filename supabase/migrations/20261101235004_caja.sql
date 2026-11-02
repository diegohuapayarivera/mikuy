-- Caja (docs/MODELO-DATOS.md). Cada unidad se cobra una sola vez: lo impide la base.

create type mikuy.medio_pago as enum ('efectivo', 'tarjeta', 'yape', 'plin', 'otro');

-- Puede haber varias por día; Salud suma todo bajo "Hoy".
create table mikuy.cajas (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  abierta_por uuid not null,
  abierta_en timestamptz not null default now(),
  monto_inicial numeric(10, 2) not null default 0 check (monto_inicial >= 0),
  cerrada_en timestamptz,
  monto_contado numeric(10, 2) check (monto_contado >= 0),
  unique (id, restaurante_id),
  foreign key (abierta_por, restaurante_id) references mikuy.perfiles (id, restaurante_id),
  check ((cerrada_en is null) = (monto_contado is null)),
  check (cerrada_en is null or cerrada_en >= abierta_en)
);
create index cajas_restaurante_idx on mikuy.cajas (restaurante_id, abierta_en);
create index cajas_abierta_por_idx on mikuy.cajas (abierta_por, restaurante_id);

-- Un pago parcial o total. El descuento lo da el administrador, con motivo (lo valida la RPC).
create table mikuy.cobros (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  atencion_id uuid not null,
  caja_id uuid not null,
  cobrado_por uuid not null,
  llave_idempotencia uuid not null,
  subtotal numeric(10, 2) not null check (subtotal >= 0),
  descuento numeric(10, 2) not null default 0,
  descuento_motivo text,
  total numeric(10, 2) not null,
  creado_en timestamptz not null default now(),
  unique (restaurante_id, llave_idempotencia),
  unique (id, restaurante_id),
  unique (id, atencion_id, restaurante_id),
  foreign key (atencion_id, restaurante_id) references mikuy.atenciones (id, restaurante_id),
  foreign key (caja_id, restaurante_id) references mikuy.cajas (id, restaurante_id),
  foreign key (cobrado_por, restaurante_id) references mikuy.perfiles (id, restaurante_id),
  check (descuento >= 0 and descuento <= subtotal),
  check (total = subtotal - descuento),
  check ((descuento > 0) = (descuento_motivo is not null)),
  check (descuento_motivo is null or btrim(descuento_motivo) <> '')
);
create index cobros_atencion_idx on mikuy.cobros (atencion_id, restaurante_id);
create index cobros_caja_idx on mikuy.cobros (caja_id, restaurante_id);
create index cobros_cobrado_por_idx on mikuy.cobros (cobrado_por, restaurante_id);

-- item_id es la llave: una unidad no se cobra dos veces. La unidad y el cobro son de la misma
-- atención.
create table mikuy.cobro_items (
  item_id uuid primary key,
  restaurante_id uuid not null references mikuy.restaurantes (id),
  cobro_id uuid not null,
  atencion_id uuid not null,
  foreign key (cobro_id, atencion_id, restaurante_id)
    references mikuy.cobros (id, atencion_id, restaurante_id),
  foreign key (item_id, atencion_id, restaurante_id)
    references mikuy.items (id, atencion_id, restaurante_id)
);
create index cobro_items_restaurante_idx on mikuy.cobro_items (restaurante_id);
create index cobro_items_cobro_idx on mikuy.cobro_items (cobro_id, atencion_id, restaurante_id);
create index cobro_items_item_idx on mikuy.cobro_items (item_id, atencion_id, restaurante_id);

-- Pagos mixtos = varias filas.
create table mikuy.pagos (
  id uuid primary key default gen_random_uuid(),
  restaurante_id uuid not null references mikuy.restaurantes (id),
  cobro_id uuid not null,
  medio mikuy.medio_pago not null,
  monto numeric(10, 2) not null check (monto > 0),
  recibido numeric(10, 2),
  vuelto numeric(10, 2),
  creado_en timestamptz not null default now(),
  foreign key (cobro_id, restaurante_id) references mikuy.cobros (id, restaurante_id),
  check (medio = 'efectivo' or (recibido is null and vuelto is null)),
  check (recibido is null or recibido >= monto),
  check (vuelto is null or (recibido is not null and vuelto = recibido - monto))
);
create index pagos_restaurante_idx on mikuy.pagos (restaurante_id);
create index pagos_cobro_idx on mikuy.pagos (cobro_id, restaurante_id);

alter table mikuy.cajas enable row level security;
alter table mikuy.cobros enable row level security;
alter table mikuy.cobro_items enable row level security;
alter table mikuy.pagos enable row level security;

create policy cajas_miembros_leen on mikuy.cajas for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy cobros_miembros_leen on mikuy.cobros for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy cobro_items_miembros_leen on mikuy.cobro_items for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));
create policy pagos_miembros_leen on mikuy.pagos for select to authenticated
  using (restaurante_id = (select mikuy_privado.restaurante_actual()));

grant select on mikuy.cajas, mikuy.cobros, mikuy.cobro_items, mikuy.pagos to authenticated;
