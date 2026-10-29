# Estado de Mikuy

**Fase actual: Fase 0 · Cimientos.** Repo, infraestructura, esquema multi-tenant y documentación
base. Actualizado el 2026-10-29.

## Entornos

| Entorno                       | Supabase                                                          | Variables         |
| ----------------------------- | ----------------------------------------------------------------- | ----------------- |
| Local (`npm run dev`)         | Supabase local (CLI + Docker)                                     | `.env`            |
| Producción (`npm run deploy`) | Demo **desing-clothes** (`exxcgaikbjfojpfpiocj`), esquema `mikuy` | `.env.production` |
| Futuro, si se firma           | Proyecto Pro limpio ([docs/MUDANZA-PRO.md](docs/MUDANZA-PRO.md))  | `.env.production` |

## Qué funciona hoy

- **Producción en https://mikuy.nrlsys.com** (Cloudflare Workers, custom domain). Verificado en un
  navegador headless: la pantalla de inicio carga con el logo y las fuentes, sin mensajes en
  consola. El manifest es correcto y el service worker queda activo, controla la página y
  precachea el cascarón. Las rutas desconocidas devuelven `index.html`.
- `npm run dev` levanta la PWA contra Supabase local. `npm run build` genera el build con manifest y
  service worker.
- Una pantalla de inicio de prueba muestra el logo horizontal, las dos fuentes y los colores de
  estado.
- Los tokens de Mikuy · Identidad están en Tailwind (`src/index.css`). Íconos de la PWA, favicon
  SVG con respaldo `.ico` y logos SVG del kit oficial.
- **Esquema `mikuy`**: supabase-js apunta a él (`db: { schema: 'mikuy' }`), aunque la app todavía
  no lo usa. Primera migración (`20261029172411_crear_esquema_mikuy`): crea el esquema, el
  `usage` para los roles de la API y la tabla interna `mikuy.migraciones` (con RLS y sin acceso
  desde la API).
- **Local**: `db:start` y `db:reset` aplican la migración. La API responde 200 en `/rest/v1/` con
  `Accept-Profile: mikuy`.
- **Demo**: la migración se aplicó con `npm run db:push:demo` y quedó registrada en
  `mikuy.migraciones`.
  - La API expone `mikuy`: con la publishable key, un esquema inexistente responde 406 y lista
    `public, graphql_public, mikuy`.
  - `public` de la otra app sigue igual: 6 tablas, 2 funciones, sus 13 migraciones y el trigger
    `on_auth_user_created`.
- CI en GitHub Actions en cada push y PR: `npm ci`, lint, typecheck, format:check y build, en
  verde en `main`. El job de tests de base (pgTAP) está comentado hasta #7.
- GlitchTip y Umami están listos, pero solo se activan con sus IDs en el build de producción.
- `lint`, `typecheck`, `format:check` y `build` pasan.

## Qué falta todavía

- Modelo de datos: tablas, RLS por membresía (`mikuy.perfiles`) y RPC (#7, #8).
- DSN de GlitchTip y website ID de Umami (#6).
- Auth, rutas y pantallas. Las carpetas de `src/features/` están vacías.
- Tests (front y pgTAP).
- Proyecto Pro: solo si se firma con el cliente (ver [docs/MUDANZA-PRO.md](docs/MUDANZA-PRO.md)).

## Pendiente en esta fase (TaskView)

- #6 CI con tests, GlitchTip y Umami: en curso, faltan los IDs de GlitchTip y Umami. El job de
  pgTAP se activa con #7.
- #7 Esquema multi-tenant con RLS
- #8 Tabla de eventos append-only

## Deuda conocida

- #26 Estrategia de actualización del service worker. Hoy es `autoUpdate`, y una tablet abierta
  todo el día sigue con código viejo hasta recargar. Resolverlo antes de Fase 2.
- TypeScript está fijado en 6.0 porque typescript-eslint todavía no soporta TS 7.

## Notas

- En Supabase cloud, `GET /rest/v1/` a secas exige la secret key: con la publishable key responde
  401 aunque el esquema esté bien expuesto. Para verificar, usa el 406 de un esquema inexistente.
