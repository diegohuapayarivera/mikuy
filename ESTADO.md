# Estado de Mikuy

**Fase 0 · Cimientos: terminada.** Repo, infraestructura, esquema multi-tenant y documentación
base. Siguiente: Fase 1 · Ingreso y carta. Actualizado el 2026-11-01.

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
  - El HTML sale con `Cache-Control: ... no-transform`, así Cloudflare no inyecta su beacon de Web
    Analytics y la consola queda sin errores de CSP. Los estáticos conservan la política por
    defecto y se siguen comprimiendo.
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
- **Modelo de datos completo** (docs/MODELO-DATOS.md) en el demo, por `npm run db:push:demo`:
  20 tablas en `mikuy`, con RLS por membresía, solo lectura para `authenticated` y escrituras solo
  por RPC (todavía no hay RPC de negocio). `eventos` es append-only y solo lo lee el administrador.
  Las funciones `security definer` viven en `mikuy_privado`, que no está expuesto.
- **Sabor de Morenas cargado en el demo** con `npm run db:seed:demo`: 2 estaciones, 17
  categorías, 93 platos, 119 presentaciones y 12 mesas. Repetible sin duplicar.
- **pgTAP en el CI**: estructura y permisos, aislamiento entre restaurantes, sin escritura directa,
  una unidad no se cobra dos veces, una mesa no está en dos atenciones abiertas, eventos rechaza
  UPDATE y DELETE, máquina de estados de las unidades y `jornada`. Avisos de seguridad de Supabase
  en cero para `mikuy`. `public` de la otra app sigue intacto.

## Qué falta todavía

- RPC de negocio, Auth (PIN y login), rutas y pantallas: Fase 1 en adelante.
- Lecturas por rol más finas (hoy cualquier miembro lee todo salvo `pines` y `eventos`): llegan con
  las pantallas.
- Tests del front (unitarios y Playwright): Fase 4.

## Deuda conocida

- #26 Estrategia de actualización del service worker. Hoy es `autoUpdate`, y una tablet abierta
  todo el día sigue con código viejo hasta recargar. Resolverlo antes de Fase 2.
- TypeScript está fijado en 6.0 porque typescript-eslint todavía no soporta TS 7.

## Notas

- En Supabase cloud, `GET /rest/v1/` a secas exige la secret key: con la publishable key responde
  401 aunque el esquema esté bien expuesto. Para verificar, usa el 406 de un esquema inexistente.
- Umami descarta las visitas de navegadores headless: para probarlo hace falta un user-agent normal.
