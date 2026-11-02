-- Estructura y permisos de todo el esquema: RLS en todas las tablas, sin escrituras para los roles de
-- la API y sin funciones SECURITY DEFINER expuestas.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

select tables_are(
  'mikuy',
  array[
    'atencion_mesas', 'atenciones', 'cajas', 'categorias', 'cobro_items', 'cobros',
    'config_salud', 'envios', 'estaciones', 'eventos', 'items', 'mesas', 'migraciones', 'pagos',
    'perfiles', 'pines', 'platos', 'presentaciones', 'restaurantes', 'tandas'
  ],
  'mikuy tiene exactamente las tablas del modelo'
);

select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   where c.relnamespace = 'mikuy'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
  null,
  'todas las tablas de mikuy tienen RLS'
);

select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   where c.relnamespace = 'mikuy'::regnamespace and c.relkind = 'r'
     and not exists (select 1 from pg_policy p where p.polrelid = c.oid)),
  null,
  'todas las tablas de mikuy tienen al menos una política'
);

select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   where c.relnamespace = 'mikuy'::regnamespace and c.relkind = 'r'
     and (has_table_privilege('anon', c.oid, 'select')
       or has_table_privilege('anon', c.oid, 'insert')
       or has_table_privilege('anon', c.oid, 'update')
       or has_table_privilege('anon', c.oid, 'delete'))),
  null,
  'anon no tiene privilegios sobre ninguna tabla'
);

select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   where c.relnamespace = 'mikuy'::regnamespace and c.relkind = 'r'
     and (has_table_privilege('authenticated', c.oid, 'insert')
       or has_table_privilege('authenticated', c.oid, 'update')
       or has_table_privilege('authenticated', c.oid, 'delete')
       or has_table_privilege('authenticated', c.oid, 'truncate'))),
  null,
  'authenticated no escribe directo en ninguna tabla'
);

select is(
  (select array_agg(c.relname::text order by c.relname)
   from pg_class c
   where c.relnamespace = 'mikuy'::regnamespace and c.relkind = 'r'
     and has_table_privilege('authenticated', c.oid, 'select')),
  array[
    'atencion_mesas', 'atenciones', 'cajas', 'categorias', 'cobro_items', 'cobros',
    'config_salud', 'envios', 'estaciones', 'eventos', 'items', 'mesas', 'pagos', 'perfiles',
    'platos', 'presentaciones', 'restaurantes', 'tandas'
  ],
  'authenticated lee todo menos pines y migraciones'
);

select is(
  (select count(*)::int
   from pg_proc p
   where p.pronamespace = 'mikuy'::regnamespace and p.prosecdef),
  0,
  'no hay funciones SECURITY DEFINER en el esquema expuesto'
);

select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p
   where p.pronamespace in ('mikuy'::regnamespace, 'mikuy_privado'::regnamespace)
     and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')),
  null,
  'todas las funciones fijan su search_path'
);

select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p
   where p.pronamespace in ('mikuy'::regnamespace, 'mikuy_privado'::regnamespace)
     and has_function_privilege('anon', p.oid, 'execute')),
  null,
  'anon no ejecuta ninguna función de Mikuy'
);

select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p
   where p.pronamespace in ('mikuy'::regnamespace, 'mikuy_privado'::regnamespace)
     and has_function_privilege('authenticated', p.oid, 'execute')),
  array['perfil_actual', 'restaurante_actual', 'rol_actual'],
  'authenticated solo ejecuta perfil_actual, restaurante_actual y rol_actual'
);

select ok(
  not has_schema_privilege('anon', 'mikuy_privado', 'usage'),
  'anon no usa el esquema mikuy_privado'
);

select * from finish();
rollback;
