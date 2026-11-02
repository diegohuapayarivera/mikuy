-- Aislamiento entre restaurantes, sin escritura directa y reglas que impone la base.
-- Arma dos restaurantes completos (A y B) y cuatro usuarios:
--   A: administrador de A · B: administrador de B · C: sin perfil (como los de la otra app)
--   D: perfil inactivo en A · E: mozo de A
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

-- Ayudantes de prueba (se borran con el rollback).
create schema pruebas;
grant usage on schema pruebas to anon, authenticated;

create table pruebas.ids (clave text primary key, valor uuid not null);
grant select on pruebas.ids to anon, authenticated;

create function pruebas.id(p_clave text) returns uuid language sql stable as $$
  select valor from pruebas.ids where clave = p_clave
$$;

-- Tablas que se leen desde la API (todas menos pines y migraciones).
create function pruebas.tablas() returns text[] language sql immutable as $$
  select array[
    'restaurantes', 'config_salud', 'estaciones', 'perfiles', 'categorias', 'platos',
    'presentaciones', 'mesas', 'atenciones', 'atencion_mesas', 'envios', 'tandas', 'items',
    'cajas', 'cobros', 'cobro_items', 'pagos', 'eventos'
  ]
$$;

-- Cuenta las filas de un restaurante que ve el rol actual (con RLS).
create function pruebas.contar(p_tabla text, p_restaurante uuid) returns bigint
language plpgsql as $$
declare
  n bigint;
begin
  execute format(
    'select count(*) from mikuy.%I where %I = $1',
    p_tabla, case when p_tabla = 'restaurantes' then 'id' else 'restaurante_id' end
  ) into n using p_restaurante;
  return n;
end;
$$;

create function pruebas.contar_todo(p_tabla text) returns bigint language plpgsql as $$
declare
  n bigint;
begin
  execute format('select count(*) from mikuy.%I', p_tabla) into n;
  return n;
end;
$$;

-- Cambia el usuario de la sesión (lo que lee auth.uid()).
create function pruebas.como(p_usuario uuid) returns void language sql as $$
  select set_config(
    'request.jwt.claims',
    json_build_object('sub', p_usuario, 'role', 'authenticated')::text,
    true
  )
$$;

-- Restaurante completo: al menos una fila en cada tabla.
create function pruebas.armar(p_clave text, p_usuario uuid) returns void language plpgsql as $$
declare
  r uuid; e uuid; pf uuid; c uuid; pl uuid; pr uuid; m uuid; at uuid; en uuid; t uuid;
  it uuid; cj uuid; co uuid;
begin
  insert into mikuy.restaurantes (nombre, slug)
    values ('Restaurante ' || p_clave, 'resto-' || lower(p_clave)) returning id into r;
  insert into mikuy.config_salud (
    restaurante_id, ventas_bien_pct, ventas_atento_pct, cocina_bien_min, cocina_atento_min,
    salon_bien_min, salon_atento_min, caja_bien_min, caja_atento_min, carta_bien_agotados,
    carta_atento_agotados, equipo_bien_mesas, equipo_atento_mesas, aviso_plato_min,
    aviso_bebida_min, aviso_mesa_sin_pedir_min, aviso_cuenta_min
  ) values (r, 90, 75, 60, 90, 10, 20, 10, 20, 0, 2, 4, 6, 40, 10, 15, 10);
  insert into mikuy.estaciones (restaurante_id, nombre) values (r, 'Cocina') returning id into e;
  insert into mikuy.perfiles (restaurante_id, user_id, nombre, rol)
    values (r, p_usuario, 'Admin ' || p_clave, 'administrador') returning id into pf;
  insert into mikuy.pines (restaurante_id, perfil_id, hash, expira_en)
    values (r, pf, repeat('h', 60), now() + interval '30 minutes');
  insert into mikuy.categorias (restaurante_id, nombre, estacion_id)
    values (r, 'Entradas', e) returning id into c;
  insert into mikuy.platos (restaurante_id, categoria_id, nombre)
    values (r, c, 'Ocopa') returning id into pl;
  insert into mikuy.presentaciones (restaurante_id, plato_id, precio)
    values (r, pl, 18) returning id into pr;
  insert into mikuy.mesas (restaurante_id, nombre) values (r, 'Mesa 1') returning id into m;
  insert into mikuy.atenciones (restaurante_id, tipo, mozo_id)
    values (r, 'mesa', pf) returning id into at;
  insert into mikuy.atencion_mesas (restaurante_id, atencion_id, mesa_id) values (r, at, m);
  insert into mikuy.envios (restaurante_id, atencion_id, mozo_id, llave_idempotencia)
    values (r, at, pf, gen_random_uuid()) returning id into en;
  insert into mikuy.tandas (restaurante_id, estacion_id, iniciada_por)
    values (r, e, pf) returning id into t;
  insert into mikuy.items (
    restaurante_id, atencion_id, envio_id, presentacion_id, plato_nombre, presentacion_nombre,
    precio, estacion_id
  ) values (r, at, en, pr, 'Ocopa', 'Normal', 18, e) returning id into it;
  insert into mikuy.cajas (restaurante_id, abierta_por) values (r, pf) returning id into cj;
  insert into mikuy.cobros (
    restaurante_id, atencion_id, caja_id, cobrado_por, llave_idempotencia, subtotal, total
  ) values (r, at, cj, pf, gen_random_uuid(), 18, 18) returning id into co;
  insert into mikuy.cobro_items (item_id, restaurante_id, cobro_id, atencion_id)
    values (it, r, co, at);
  insert into mikuy.pagos (restaurante_id, cobro_id, medio, monto, recibido, vuelto)
    values (r, co, 'efectivo', 18, 20, 2);
  insert into mikuy.eventos (restaurante_id, tipo, entidad, entidad_id, perfil_id)
    values (r, 'prueba', 'restaurante', r, pf);

  insert into pruebas.ids values
    (p_clave, r), (p_clave || '.estacion', e), (p_clave || '.perfil', pf),
    (p_clave || '.plato', pl), (p_clave || '.presentacion', pr), (p_clave || '.mesa', m),
    (p_clave || '.atencion', at), (p_clave || '.envio', en), (p_clave || '.item', it),
    (p_clave || '.caja', cj), (p_clave || '.cobro', co);
end;
$$;

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000a', 'a@prueba.mikuy'),
  ('00000000-0000-4000-8000-00000000000b', 'b@prueba.mikuy'),
  ('00000000-0000-4000-8000-00000000000c', 'c@prueba.mikuy'),
  ('00000000-0000-4000-8000-00000000000d', 'd@prueba.mikuy'),
  ('00000000-0000-4000-8000-00000000000e', 'e@prueba.mikuy');
insert into pruebas.ids values
  ('usuario.A', '00000000-0000-4000-8000-00000000000a'),
  ('usuario.B', '00000000-0000-4000-8000-00000000000b'),
  ('usuario.C', '00000000-0000-4000-8000-00000000000c'),
  ('usuario.D', '00000000-0000-4000-8000-00000000000d'),
  ('usuario.E', '00000000-0000-4000-8000-00000000000e');

select pruebas.armar('A', pruebas.id('usuario.A'));
select pruebas.armar('B', pruebas.id('usuario.B'));
insert into mikuy.perfiles (restaurante_id, user_id, nombre, rol, activo)
  values (pruebas.id('A'), pruebas.id('usuario.D'), 'Mozo dado de baja', 'mozo', false);
insert into mikuy.perfiles (restaurante_id, user_id, nombre, rol)
  values (pruebas.id('A'), pruebas.id('usuario.E'), 'Mozo', 'mozo');

-- ---------------------------------------------------------------------------------------------
-- Aislamiento entre restaurantes
-- ---------------------------------------------------------------------------------------------
set local role authenticated;

select pruebas.como(pruebas.id('usuario.A'));
select is(mikuy_privado.restaurante_actual(), pruebas.id('A'), 'restaurante_actual() de A es A');
select is(mikuy_privado.perfil_actual(), pruebas.id('A.perfil'), 'perfil_actual() de A es su perfil');
select ok(pruebas.contar(t, pruebas.id('A')) > 0, format('A ve sus filas de %s', t))
  from unnest(pruebas.tablas()) t;
select is(pruebas.contar(t, pruebas.id('B')), 0::bigint, format('A no ve nada de B en %s', t))
  from unnest(pruebas.tablas()) t;

-- Eventos: solo el administrador lee el historial.
select pruebas.como(pruebas.id('usuario.E'));
select is(mikuy_privado.rol_actual(), 'mozo'::mikuy.rol_perfil, 'rol_actual() del mozo es mozo');
select is(pruebas.contar('eventos', pruebas.id('A')), 0::bigint, 'un mozo no lee eventos');
select ok(pruebas.contar('items', pruebas.id('A')) > 0, 'un mozo sí lee los items de su restaurante');

select pruebas.como(pruebas.id('usuario.B'));
select is(pruebas.contar(t, pruebas.id('A')), 0::bigint, format('B no ve nada de A en %s', t))
  from unnest(pruebas.tablas()) t;

select pruebas.como(pruebas.id('usuario.C'));
select is(mikuy_privado.restaurante_actual(), null, 'sin perfil no hay restaurante_actual()');
select is(pruebas.contar_todo(t), 0::bigint, format('un usuario sin perfil no ve nada en %s', t))
  from unnest(pruebas.tablas()) t;

select pruebas.como(pruebas.id('usuario.D'));
select is(mikuy_privado.perfil_actual(), null, 'un perfil inactivo no cuenta');
select is(pruebas.contar_todo(t), 0::bigint, format('un perfil inactivo no ve nada en %s', t))
  from unnest(pruebas.tablas()) t;

-- ---------------------------------------------------------------------------------------------
-- Sin escritura directa: ni authenticated ni anon escriben; nadie lee pines ni migraciones.
-- ---------------------------------------------------------------------------------------------
select pruebas.como(pruebas.id('usuario.A'));
select throws_ok(
  format('insert into mikuy.%I default values', t), '42501', null,
  format('authenticated no inserta en %s', t)
) from unnest(pruebas.tablas() || array['pines', 'migraciones']) t;
select throws_ok(
  format('update mikuy.%I set %I = %I', t, col.c, col.c), '42501', null,
  format('authenticated no actualiza %s', t)
) from unnest(pruebas.tablas() || array['pines', 'migraciones']) t,
  lateral (select case t when 'restaurantes' then 'id' when 'migraciones' then 'version'
                         else 'restaurante_id' end) as col(c);
select throws_ok(
  format('delete from mikuy.%I', t), '42501', null,
  format('authenticated no borra en %s', t)
) from unnest(pruebas.tablas() || array['pines', 'migraciones']) t;
select throws_ok('select * from mikuy.pines', '42501', null, 'authenticated no lee pines');
select throws_ok(
  $$select mikuy_privado.registrar_evento('x', 'y', null)$$, '42501', null,
  'authenticated no llama registrar_evento directo'
);

reset role;
set local role anon;
select throws_ok(
  format('select * from mikuy.%I', t), '42501', null, format('anon no lee %s', t)
) from unnest(pruebas.tablas()) t;
reset role;

-- ---------------------------------------------------------------------------------------------
-- Una unidad no se cobra dos veces
-- ---------------------------------------------------------------------------------------------
insert into mikuy.cobros (
  restaurante_id, atencion_id, caja_id, cobrado_por, llave_idempotencia, subtotal, total
) values (
  pruebas.id('A'), pruebas.id('A.atencion'), pruebas.id('A.caja'), pruebas.id('A.perfil'),
  gen_random_uuid(), 18, 18
);
select throws_ok(
  format(
    $$insert into mikuy.cobro_items (item_id, restaurante_id, cobro_id, atencion_id)
      select %L, %L, c.id, %L from mikuy.cobros c
      where c.atencion_id = %L and c.id <> %L$$,
    pruebas.id('A.item'), pruebas.id('A'), pruebas.id('A.atencion'),
    pruebas.id('A.atencion'), pruebas.id('A.cobro')
  ),
  '23505', null, 'la misma unidad no entra en un segundo cobro'
);
with nueva as (
  insert into mikuy.items (
    restaurante_id, atencion_id, envio_id, presentacion_id, plato_nombre, presentacion_nombre,
    precio
  ) values (
    pruebas.id('B'), pruebas.id('B.atencion'), pruebas.id('B.envio'), pruebas.id('B.presentacion'),
    'Ocopa', 'Normal', 18
  ) returning id
)
insert into pruebas.ids select 'B.item_sin_cobrar', id from nueva;
select throws_ok(
  format(
    $$insert into mikuy.cobro_items (item_id, restaurante_id, cobro_id, atencion_id)
      values (%L, %L, %L, %L)$$,
    pruebas.id('B.item_sin_cobrar'), pruebas.id('A'), pruebas.id('A.cobro'),
    pruebas.id('A.atencion')
  ),
  '23503', null, 'no se cobra una unidad de otra atención'
);

-- ---------------------------------------------------------------------------------------------
-- Una mesa no está en dos atenciones abiertas
-- ---------------------------------------------------------------------------------------------
with nueva as (
  insert into mikuy.atenciones (restaurante_id, tipo) values (pruebas.id('A'), 'mesa') returning id
)
insert into pruebas.ids select 'A.atencion2', id from nueva;
select throws_ok(
  format(
    $$insert into mikuy.atencion_mesas (restaurante_id, atencion_id, mesa_id) values (%L, %L, %L)$$,
    pruebas.id('A'), pruebas.id('A.atencion2'), pruebas.id('A.mesa')
  ),
  '23505', null, 'una mesa no entra en una segunda atención abierta'
);
update mikuy.atencion_mesas set hasta = now() where mesa_id = pruebas.id('A.mesa');
select lives_ok(
  format(
    $$insert into mikuy.atencion_mesas (restaurante_id, atencion_id, mesa_id) values (%L, %L, %L)$$,
    pruebas.id('A'), pruebas.id('A.atencion2'), pruebas.id('A.mesa')
  ),
  'liberada la mesa, otra atención puede tomarla'
);

-- ---------------------------------------------------------------------------------------------
-- Eventos: solo INSERT
-- ---------------------------------------------------------------------------------------------
select throws_ok(
  'update mikuy.eventos set tipo = tipo', '23001', null,
  'eventos rechaza UPDATE, incluso del dueño de la tabla'
);
select throws_ok(
  'delete from mikuy.eventos', '23001', null,
  'eventos rechaza DELETE, incluso del dueño de la tabla'
);
select throws_ok('truncate mikuy.eventos', '23001', null, 'eventos rechaza TRUNCATE');
set local role service_role;
select throws_ok(
  'update mikuy.eventos set tipo = tipo', '42501', null, 'service_role no actualiza eventos'
);
select throws_ok('delete from mikuy.eventos', '42501', null, 'service_role no borra eventos');
reset role;

select pruebas.como(pruebas.id('usuario.A'));
select lives_ok(
  $$select mikuy_privado.registrar_evento('plato_listo', 'item', null, 'preparando', 'listo')$$,
  'registrar_evento inserta con la sesión'
);
select is(
  (select row(restaurante_id, perfil_id)::text from mikuy.eventos where tipo = 'plato_listo'),
  row(pruebas.id('A'), pruebas.id('A.perfil'))::text,
  'el evento toma restaurante y perfil de la sesión'
);
select pruebas.como(pruebas.id('usuario.C'));
select throws_ok(
  $$select mikuy_privado.registrar_evento('x', 'y', null)$$, '42501', null,
  'sin perfil activo no se registra un evento'
);

-- ---------------------------------------------------------------------------------------------
-- Máquina de estados de la unidad
-- ---------------------------------------------------------------------------------------------
create function pruebas.nueva_unidad(p_estacion uuid) returns uuid language sql as $$
  insert into mikuy.items (
    restaurante_id, atencion_id, envio_id, presentacion_id, plato_nombre, presentacion_nombre,
    precio, estacion_id
  ) values (
    pruebas.id('A'), pruebas.id('A.atencion'), pruebas.id('A.envio'),
    pruebas.id('A.presentacion'), 'Ocopa', 'Normal', 18, p_estacion
  ) returning id
$$;

insert into pruebas.ids values
  ('u1', pruebas.nueva_unidad(pruebas.id('A.estacion'))),
  ('u2', pruebas.nueva_unidad(pruebas.id('A.estacion'))),
  ('u3', pruebas.nueva_unidad(null)),
  ('u4', pruebas.nueva_unidad(pruebas.id('A.estacion')));

select lives_ok(
  format($$update mikuy.items set estado = 'preparando' where id = %L$$, pruebas.id('u1')),
  'pendiente → preparando'
);
select lives_ok(
  format($$update mikuy.items set estado = 'listo' where id = %L$$, pruebas.id('u1')),
  'preparando → listo'
);
select lives_ok(
  format($$update mikuy.items set estado = 'entregado' where id = %L$$, pruebas.id('u1')),
  'listo → entregado'
);
select throws_ok(
  format($$update mikuy.items set estado = 'anulado', anulado_motivo = 'error' where id = %L$$,
    pruebas.id('u1')),
  '23514', null, 'lo entregado ya no se anula'
);
select throws_ok(
  format($$update mikuy.items set estado = 'listo' where id = %L$$, pruebas.id('u2')),
  '23514', null, 'pendiente no salta a listo'
);
select throws_ok(
  format($$update mikuy.items set estado = 'entregado' where id = %L$$, pruebas.id('u2')),
  '23514', null, 'lo que se prepara no pasa de pendiente a entregado'
);
select lives_ok(
  format($$update mikuy.items set estado = 'entregado' where id = %L$$, pruebas.id('u3')),
  'lo que no se prepara pasa de pendiente a entregado'
);
select throws_ok(
  format($$update mikuy.items set estado = 'anulado' where id = %L$$, pruebas.id('u2')),
  '23514', null, 'anular exige motivo'
);
select lives_ok(
  format($$update mikuy.items set estado = 'anulado', anulado_motivo = 'Pidió otro plato'
           where id = %L$$, pruebas.id('u2')),
  'pendiente → anulado con motivo'
);
select lives_ok(
  format($$update mikuy.items set estado = 'no_disponible' where id = %L$$, pruebas.id('u4')),
  'pendiente → no_disponible'
);
select throws_ok(
  format(
    $$insert into mikuy.items (
        restaurante_id, atencion_id, envio_id, presentacion_id, plato_nombre,
        presentacion_nombre, precio, estado
      ) values (%L, %L, %L, %L, 'Ocopa', 'Normal', 18, 'listo')$$,
    pruebas.id('A'), pruebas.id('A.atencion'), pruebas.id('A.envio'), pruebas.id('A.presentacion')
  ),
  '23514', null, 'una unidad nace pendiente'
);

-- ---------------------------------------------------------------------------------------------
-- Integridad entre restaurantes y otras reglas
-- ---------------------------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into mikuy.items (
        restaurante_id, atencion_id, envio_id, presentacion_id, plato_nombre,
        presentacion_nombre, precio
      ) values (%L, %L, %L, %L, 'Ocopa', 'Normal', 18)$$,
    pruebas.id('A'), pruebas.id('A.atencion'), pruebas.id('A.envio'), pruebas.id('B.presentacion')
  ),
  '23503', null, 'una unidad de A no usa la carta de B'
);
select throws_ok(
  format(
    $$insert into mikuy.envios (restaurante_id, atencion_id, mozo_id, llave_idempotencia)
      select restaurante_id, atencion_id, mozo_id, llave_idempotencia
      from mikuy.envios where id = %L$$,
    pruebas.id('A.envio')
  ),
  '23505', null, 'la llave de idempotencia de un envío no se repite'
);
select throws_ok(
  format(
    $$insert into mikuy.cobros (
        restaurante_id, atencion_id, caja_id, cobrado_por, llave_idempotencia, subtotal,
        descuento, total
      ) values (%L, %L, %L, %L, gen_random_uuid(), 18, 3, 15)$$,
    pruebas.id('A'), pruebas.id('A.atencion'), pruebas.id('A.caja'), pruebas.id('A.perfil')
  ),
  '23514', null, 'un descuento exige motivo'
);
select throws_ok(
  format(
    $$insert into mikuy.cobros (
        restaurante_id, atencion_id, caja_id, cobrado_por, llave_idempotencia, subtotal, total
      ) values (%L, %L, %L, %L, gen_random_uuid(), 18, 20)$$,
    pruebas.id('A'), pruebas.id('A.atencion'), pruebas.id('A.caja'), pruebas.id('A.perfil')
  ),
  '23514', null, 'el total es el subtotal menos el descuento'
);
select throws_ok(
  format($$insert into mikuy.atenciones (restaurante_id, tipo) values (%L, 'llevar')$$,
    pruebas.id('A')),
  '23514', null, 'para llevar exige nombre'
);
with nueva as (
  insert into mikuy.atenciones (restaurante_id, tipo, nombre_llevar, abierta_en)
  values (pruebas.id('A'), 'llevar', 'Rosa', '2026-11-02 03:30:00+00')
  returning id
)
insert into pruebas.ids select 'A.llevar', id from nueva;
select is(
  (select jornada from mikuy.atenciones where id = pruebas.id('A.llevar')),
  '2026-11-01'::date,
  'la jornada es la fecha en la zona horaria del restaurante (22:30 en Lima)'
);
select throws_ok(
  $$insert into mikuy.restaurantes (nombre, slug, zona_horaria) values ('X', 'x', 'Marte/Olympus')$$,
  '23514', null, 'la zona horaria tiene que existir'
);
select throws_ok(
  format($$insert into mikuy.perfiles (restaurante_id, nombre, rol) values (%L, 'Cocina', 'estacion')$$,
    pruebas.id('A')),
  '23514', null, 'el rol estación exige su estación'
);
select throws_ok(
  format($$insert into mikuy.perfiles (restaurante_id, user_id, nombre, rol) values (%L, %L, 'Otro', 'mozo')$$,
    pruebas.id('B'), pruebas.id('usuario.A')),
  '23505', null, 'un usuario no tiene dos perfiles activos'
);

select * from finish();
rollback;
