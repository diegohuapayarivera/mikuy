# Mudanza a Supabase Pro

Hoy Mikuy corre en el Supabase demo **desing-clothes** (ref `exxcgaikbjfojpfpiocj`, plan gratis),
compartido con otra app. Cuando se firme con el cliente, Mikuy pasa a un proyecto Pro limpio. Si no
se firma, se sigue en desing-clothes y nada de esto hace falta.

Todo lo de Mikuy vive en el esquema `mikuy` y en `supabase/migrations/`, así que la mudanza es
recrear el esquema en el proyecto nuevo y cambiar dos valores públicos.

## Antes de empezar

- Docker corriendo y `npm run db:reset` en verde con las migraciones actuales.
- `npm run db:push:demo` dice "El demo está al día". Así el demo y el repo coinciden.
- Decide qué pasa con los datos del demo (paso 8).

## 1. Crear el proyecto

- Dashboard de Supabase → New project, plan **Pro**, organización de NRL Systems.
- Región: **South America (São Paulo), `sa-east-1`**, la más cercana a Perú. El demo está en
  `us-west-2`.
- Guarda la contraseña de la base en el gestor de contraseñas, nunca en el repo.
- Anota el ref del proyecto nuevo (`<ref-pro>`).

## 2. Enlazar la CLI

Aquí sí se usa el flujo normal de la CLI, porque el proyecto es solo de Mikuy:

```sh
npx supabase login
npx supabase link --project-ref <ref-pro>
```

Nunca hagas `link` contra desing-clothes.

## 3. Aplicar las migraciones

```sh
npx supabase db push
```

Aplica `supabase/migrations/` en orden y guarda el historial en `supabase_migrations` del proyecto
nuevo. `mikuy.migraciones` queda vacía en Pro: solo la usa `db:push:demo`.

Si alguna migración usa `pg_cron` o `pg_net`, activa antes la extensión en Dashboard → Database →
Extensions.

## 4. Exponer `mikuy` en la Data API

Dashboard → Project Settings → Data API → Exposed schemas: agrega `mikuy`. Si Mikuy no usa nada de
`public`, puedes quitar `public`.

Hazlo **después** del `db push`. Si el esquema está expuesto pero no existe, PostgREST no carga el
schema cache y la API responde 503.

No uses `supabase config push`: `supabase/config.toml` tiene valores de local (por ejemplo
`site_url = http://localhost:5173`) y los subiría a producción.

## 5. Auth

Dashboard → Authentication → URL Configuration:

- Site URL: `https://mikuy.nrlsys.com`, o `https://mikuy.dev` si ya se compró.
- Redirect URLs: el mismo dominio con `/**`.
- SMTP propio si Mikuy manda correos (el SMTP de Supabase tiene un límite muy bajo).

En Pro no existe el trigger `on_auth_user_created` de la otra app: los usuarios nuevos ya no crean
filas en `public.profiles`.

## 6. Edge Functions y secretos

Solo las de Mikuy (`mikuy-*`):

```sh
npx supabase functions deploy mikuy-<nombre>
npx supabase secrets set NOMBRE=valor   # Nubefact, Culqi, etc.
```

## 7. Crons y buckets

- Crons `mikuy_*`: si se crean por migración (`cron.schedule`), llegan con el `db push`. Si alguno se
  creó a mano en el demo, recréalo. Para revisarlos:
  `select jobname, schedule from cron.job where jobname like 'mikuy_%';`
- Buckets `mikuy-*`: créalos igual que en el demo (por migración o desde el dashboard), con sus
  políticas sobre `storage.objects` filtradas por `bucket_id`. Si tienen archivos que deban
  mudarse, cópialos con un script.

## 8. Datos de demo

Recomendado: empezar Pro limpio y cargar los datos de demo con un seed propio. Los usuarios de
Mikuy en el demo están en `auth.users`, mezclados con los de la otra app, y `mikuy.perfiles` los
referencia por id.

Si hace falta mudar datos:

```sh
npx supabase db dump --db-url "$DATABASE_URL" --schema mikuy --data-only -f demo-mikuy.sql
```

- Quita las filas de `mikuy.migraciones` del dump.
- Recrea antes los usuarios en Pro (Dashboard o Admin API) y remapea los ids de `mikuy.perfiles`.
- No commitees el dump: tiene datos reales.

## 9. Cambiar `.env.production` y desplegar

En `.env.production` cambian solo dos líneas, con los valores públicos del proyecto Pro (Project
Settings → API):

```sh
VITE_SUPABASE_URL=https://<ref-pro>.supabase.co
VITE_SUPABASE_ANON_KEY=sb_publishable_...
```

Después:

```sh
npm run deploy
```

Commitea el cambio de `.env.production` junto con la actualización de `ESTADO.md` y de este
documento si algo cambió.

## 10. Verificar

Con la publishable key de Pro:

```sh
# Debe responder 406 y listar "mikuy" en el hint de esquemas expuestos.
curl -s -H "apikey: <publishable>" -H "Accept-Profile: no_existe" https://<ref-pro>.supabase.co/rest/v1/
# Debe responder 404 PGRST205 (busca en el schema cache de mikuy).
curl -s -H "apikey: <publishable>" -H "Accept-Profile: mikuy" https://<ref-pro>.supabase.co/rest/v1/no_hay_tabla
```

`GET /rest/v1/` a secas exige la secret key en Supabase cloud, así que con la publishable key
responde 401 aunque todo esté bien.

Luego abre la app en el dominio, entra con un usuario de prueba y revisa que no haya errores en
GlitchTip.

## 11. Limpiar desing-clothes (opcional, con cuidado)

Solo cuando Pro lleve unos días estable. Todo con prefijo `mikuy`; no toques nada de la otra app:

- `drop schema mikuy cascade;`
- Quita `mikuy` de los esquemas expuestos.
- Borra las Edge Functions `mikuy-*`, los jobs `mikuy_*` y los buckets `mikuy-*`.
- Usuarios de Mikuy: bórralos uno por uno, junto con su fila en `public.profiles` creada por el
  trigger de la otra app. Revisa la lista dos veces.
- `DATABASE_URL` en `.env` deja de hacer falta.
