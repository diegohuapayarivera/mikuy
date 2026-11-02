-- Trazabilidad (docs/MODELO-DATOS.md). Append-only: no es event sourcing, el estado vive en sus
-- tablas. Fuente de los tiempos de Salud y del historial de anulaciones y cortesías.

create table mikuy.eventos (
  id bigint generated always as identity primary key,
  restaurante_id uuid not null references mikuy.restaurantes (id),
  tipo text not null check (btrim(tipo) <> ''),
  entidad text not null check (btrim(entidad) <> ''),
  entidad_id uuid,
  de text,
  a text,
  perfil_id uuid,
  datos jsonb not null default '{}',
  creado_en timestamptz not null default now(),
  foreign key (perfil_id, restaurante_id) references mikuy.perfiles (id, restaurante_id)
);
create index eventos_restaurante_creado_idx on mikuy.eventos (restaurante_id, creado_en);
create index eventos_entidad_idx on mikuy.eventos (restaurante_id, entidad, entidad_id);
create index eventos_perfil_idx on mikuy.eventos (perfil_id, restaurante_id);

-- Nadie modifica ni borra eventos, ni siquiera el dueño de la tabla o service_role.
create function mikuy_privado.eventos_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'mikuy.eventos es append-only: % no está permitido', tg_op
    using errcode = 'restrict_violation';
end;
$$;
revoke execute on function mikuy_privado.eventos_append_only() from public;

create trigger eventos_sin_update_ni_delete
  before update or delete on mikuy.eventos
  for each row execute function mikuy_privado.eventos_append_only();
create trigger eventos_sin_truncate
  before truncate on mikuy.eventos
  for each statement execute function mikuy_privado.eventos_append_only();

revoke update, delete, truncate on mikuy.eventos from anon, authenticated, service_role;

-- Lo llaman las RPC en la misma transacción que el cambio. Restaurante y perfil salen de la
-- sesión, nunca de un parámetro. No se expone: no tiene grant para ningún rol de la API.
create function mikuy_privado.registrar_evento(
  p_tipo text,
  p_entidad text,
  p_entidad_id uuid,
  p_de text default null,
  p_a text default null,
  p_datos jsonb default '{}'
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_restaurante uuid := mikuy_privado.restaurante_actual();
  v_id bigint;
begin
  if v_restaurante is null then
    raise exception 'Sin perfil activo: no se puede registrar el evento'
      using errcode = 'insufficient_privilege';
  end if;

  insert into mikuy.eventos (restaurante_id, tipo, entidad, entidad_id, de, a, perfil_id, datos)
  values (
    v_restaurante, p_tipo, p_entidad, p_entidad_id, p_de, p_a,
    mikuy_privado.perfil_actual(), coalesce(p_datos, '{}')
  )
  returning id into v_id;

  return v_id;
end;
$$;
revoke execute on function mikuy_privado.registrar_evento(text, text, uuid, text, text, jsonb)
  from public;

alter table mikuy.eventos enable row level security;
-- Solo el administrador lee el historial.
create policy eventos_administrador_lee on mikuy.eventos for select to authenticated
  using (
    restaurante_id = (select mikuy_privado.restaurante_actual())
    and (select mikuy_privado.rol_actual()) = 'administrador'
  );
grant select on mikuy.eventos to authenticated;
