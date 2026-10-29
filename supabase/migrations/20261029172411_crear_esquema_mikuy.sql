-- Esquema propio de Mikuy. Nada de Mikuy vive en public: en el demo comparte proyecto con otra app.
create schema if not exists mikuy;

-- Los roles de la Data API pueden ver el esquema. Qué tablas leen lo deciden los grants y RLS de
-- cada tabla; las escrituras van solo por RPC.
grant usage on schema mikuy to anon, authenticated, service_role;

-- Registro de migraciones que `npm run db:push:demo` aplicó en el demo (desing-clothes).
-- En local y en Pro el historial lo lleva la CLI de Supabase y esta tabla queda vacía.
create table if not exists mikuy.migraciones (
  version text primary key,
  nombre text not null,
  checksum text not null,
  aplicada_en timestamptz not null default now()
);

-- Tabla interna: sin acceso desde la Data API.
alter table mikuy.migraciones enable row level security;
revoke all on mikuy.migraciones from anon, authenticated;
