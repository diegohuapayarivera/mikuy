-- El esquema mikuy existe y su tabla interna no se ve desde la API.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select has_schema('mikuy');
select has_table('mikuy', 'migraciones', 'existe mikuy.migraciones');
select ok(
  (select relrowsecurity from pg_class where oid = 'mikuy.migraciones'::regclass),
  'mikuy.migraciones tiene RLS'
);
select ok(
  not has_table_privilege('authenticated', 'mikuy.migraciones', 'select')
    and not has_table_privilege('anon', 'mikuy.migraciones', 'select'),
  'ni anon ni authenticated leen mikuy.migraciones'
);

select * from finish();
rollback;
