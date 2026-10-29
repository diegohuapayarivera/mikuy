# Estado de Mikuy

**Fase actual: Fase 0 · Cimientos.** Repo, infraestructura, esquema multi-tenant y documentación
base. Actualizado el 2026-10-29.

## Qué funciona hoy

- `npm run dev` levanta la PWA. `npm run build` genera el build con el manifest y el service
  worker, y `npm run preview` lo sirve para instalarla.
- Una pantalla de inicio de prueba muestra el logo horizontal, las dos fuentes y los colores de
  estado.
- Los tokens de Mikuy · Identidad están en Tailwind (`src/index.css`): colores, radio 8px y la
  sombra de tarjeta.
- Íconos de la PWA, favicon SVG con respaldo `.ico` y logos SVG del kit oficial.
- El cliente de Supabase y el QueryClient están listos en `src/shared/`, pero nadie los usa todavía.
- Supabase local configurado con la CLI (`supabase/`, migraciones y `seed.sql` vacíos) y los
  scripts `db:start`, `db:stop` y `db:reset`. `.env.example` ya apunta a él. Todavía no se levantó:
  hace falta Docker corriendo.
- Cloudflare Workers: `wrangler.jsonc` sirve `dist/` como SPA (las rutas desconocidas devuelven
  `index.html`). Probado con `wrangler dev` y `wrangler deploy --dry-run`; sin deploy real.
- `lint`, `typecheck`, `format:check` y `build` pasan.

## Qué falta todavía

- Modelo de datos: no hay tablas, migraciones con esquema, RLS ni RPC.
- Proyecto de Supabase en la nube y primer deploy a Cloudflare (los hace Diego).
- Auth, rutas y pantallas. Las carpetas de `src/features/` están vacías.
- Tests y CI.

## Pendiente en esta fase (TaskView)

- #5 Supabase Pro y Cloudflare Workers en mikuy.dev: en curso. Falta el proyecto en la nube y el
  primer deploy.
- #6 CI con tests, GlitchTip y Umami
- #7 Esquema multi-tenant con RLS
- #8 Tabla de eventos append-only

## Deuda conocida

- #26 Estrategia de actualización del service worker. Hoy es `autoUpdate`, y una tablet abierta
  todo el día sigue con código viejo hasta recargar. Resolverlo antes de Fase 2.
- TypeScript está fijado en 6.0 porque typescript-eslint todavía no soporta TS 7.
