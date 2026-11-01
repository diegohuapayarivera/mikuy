# Estado de Mikuy

**Fase actual: Fase 0 · Cimientos.** Repo, infraestructura, esquema multi-tenant y documentación
base. Actualizado el 2026-11-01.

## Entornos

No hay Supabase local ni Docker en la máquina de Diego.

| Uso                                  | Supabase                                                          | Variables         |
| ------------------------------------ | ----------------------------------------------------------------- | ----------------- |
| Desarrollo (`npm run dev`)           | Demo **desing-clothes** (`exxcgaikbjfojpfpiocj`), esquema `mikuy` | `.env`            |
| Deploy de pruebas (`npm run deploy`) | El mismo demo                                                     | `.env.production` |
| Tests de base (CI)                   | Supabase propio de GitHub Actions, con Docker                     | —                 |
| Producción (v1.0.0, tarea #33)       | Proyecto Pro limpio ([docs/MUDANZA-PRO.md](docs/MUDANZA-PRO.md))  | `.env.production` |

## Qué funciona hoy

- **https://mikuy.nrlsys.com** (Cloudflare Workers, custom domain), con cabeceras de seguridad
  (`public/_headers`): CSP estricta, HSTS, `nosniff`, `X-Frame-Options`, `Referrer-Policy`,
  `Permissions-Policy` y COOP.
  - La pantalla de inicio carga con el logo y las fuentes; el service worker queda activo y
    controla la página.
  - Las rutas desconocidas devuelven `index.html`.
- **Observabilidad activa en producción**, verificada tras el deploy:
  - Umami registra la visita (`/api/send` responde 200 con sesión).
  - GlitchTip recibe un error de prueba (evento `3e0a4f64…`).
  - Ninguno recibe datos personales.
- **CI en cada push y PR**, en verde:
  - `front`: lint, typecheck, formato, build y `npm audit` (bloquea con hallazgos altos o críticos).
  - `secretos`: gitleaks 8.30.1 sobre todo el historial.
  - `db`: levanta su propio Supabase, aplica las migraciones y corre pgTAP (`supabase/tests/`).
- `npm run dev` levanta la PWA contra el Supabase demo.
- Tokens de Mikuy · Identidad en Tailwind, íconos de la PWA, favicon y logos del kit oficial.
- **Esquema `mikuy`** en el demo, con la primera migración aplicada por `npm run db:push:demo`.
  supabase-js apunta a él, aunque la app todavía no lo usa. `public` de la otra app sigue intacto.

## Qué falta todavía

- Modelo de datos: tablas, RLS por membresía y funciones auxiliares (#7, #8, en curso).
- Auth, rutas y pantallas. Las carpetas de `src/features/` están vacías.
- Tests del front (unitarios y Playwright): llegan con las primeras pantallas.

## Pendiente en esta fase (TaskView)

- #7 Esquema multi-tenant con RLS
- #8 Tabla de eventos append-only
- #39 Cloudflare inyecta su beacon de Web Analytics y la CSP lo bloquea: queda un error en consola
  hasta apagar esa inyección en el dashboard de Cloudflare.

## Deuda conocida

- #26 Estrategia de actualización del service worker. Hoy es `autoUpdate`, y una tablet abierta
  todo el día sigue con código viejo hasta recargar. Resolverlo antes de Fase 2.
- TypeScript está fijado en 6.0 porque typescript-eslint todavía no soporta TS 7.

## Notas

- En Supabase cloud, `GET /rest/v1/` a secas exige la secret key: con la publishable key responde
  401 aunque el esquema esté bien expuesto. Para verificar, usa el 406 de un esquema inexistente.
- Umami descarta las visitas de navegadores headless: para probarlo hace falta un user-agent normal.
