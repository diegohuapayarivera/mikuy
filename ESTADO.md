# Estado de Mikuy

**Fase actual: Fase 0 · Cimientos.** Repo, infraestructura, esquema multi-tenant y documentación
base. Actualizado el 2026-10-28.

## Qué funciona hoy

- `npm run dev` levanta la PWA. `npm run build` genera el build con el manifest y el service
  worker, y `npm run preview` lo sirve para instalarla.
- Una pantalla de inicio de prueba muestra el logo horizontal, las dos fuentes y los colores de
  estado.
- Los tokens de Mikuy · Identidad están en Tailwind (`src/index.css`): colores, radio 8px y la
  sombra de tarjeta.
- Íconos de la PWA, favicon SVG con respaldo `.ico` y logos SVG del kit oficial.
- El cliente de Supabase y el QueryClient están listos en `src/shared/`, pero nadie los usa todavía.
- `lint`, `typecheck`, `format:check` y `build` pasan.

## Qué falta todavía

- Modelo de datos: no hay tablas, migraciones, RLS ni RPC.
- Proyecto de Supabase: no hay `.env`. Si algo importa `src/shared/supabase.ts` sin él, la app
  lanza un error que dice qué falta.
- Auth, rutas y pantallas. Las carpetas de `src/features/` están vacías.
- Tests, CI y deploy (Cloudflare Workers en mikuy.dev).

## Pendiente en esta fase (TaskView)

- #5 Supabase Pro y Cloudflare Workers en mikuy.dev
- #6 CI con tests, GlitchTip y Umami
- #7 Esquema multi-tenant con RLS
- #8 Tabla de eventos append-only

## Deuda conocida

- #26 Estrategia de actualización del service worker. Hoy es `autoUpdate`, y una tablet abierta
  todo el día sigue con código viejo hasta recargar. Resolverlo antes de Fase 2.
- TypeScript está fijado en 6.0 porque typescript-eslint todavía no soporta TS 7.
