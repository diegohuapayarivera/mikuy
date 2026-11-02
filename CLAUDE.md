# Mikuy

SaaS multi-tenant de gestión de pedidos para restaurantes: salón, cocina, bebidas y caja en
tiempo real. Producto de NRL Systems, en https://mikuy.nrlsys.com. Un dev, meta de 4–5
restaurantes.

Stack: PWA en Vite + React + TypeScript + Tailwind 4, TanStack Query y supabase-js. Supabase
(Postgres, RLS, Auth, Realtime, Edge Functions, pg_cron). Avance real en [ESTADO.md](ESTADO.md).

## Reglas de arquitectura

Son decisiones cerradas. Respétalas siempre; si una tarea parece pedir romper alguna, para y
pregunta.

1. **Monolito con la lógica en Postgres (Supabase). No hay backend propio ni microservicios.**
   Reglas de negocio, validaciones y transiciones viven en SQL (funciones, triggers, RLS). El
   front muestra datos y llama comandos. Lo que no puede vivir en SQL (hablar con un proveedor
   externo) va en una Edge Function de Supabase, no en un servidor aparte.
2. **Multi-tenant: `restaurante_id` en cada tabla, RLS en todas, y el tenant siempre sale de la
   sesión, nunca del cliente.** Las políticas y las RPC obtienen el restaurante del usuario
   autenticado; ninguna RPC recibe `restaurante_id` como parámetro. Toda tabla nueva trae
   `restaurante_id`, RLS activado y sus políticas en la misma migración.
3. **CQRS-lite: lecturas por la API REST; escrituras solo por funciones RPC. El cliente nunca
   hace INSERT/UPDATE directo.** Lecturas con `supabase.from(...).select(...)` (tablas o vistas);
   escrituras con `supabase.rpc(...)`. ESLint bloquea `.from().insert/update/upsert/delete`, pero
   la base también debe impedirlo: el rol del cliente no escribe directo en las tablas.
4. **Las máquinas de estado de platos y mesas se validan en la base.** Plato: pendiente →
   preparando → listo → entregado, o no disponible. Una transición inválida la rechaza la base
   aunque el front la permita.
5. **Llave de idempotencia generada en el cliente para pedidos y cobros.** Se genera una vez por
   intento (`crypto.randomUUID()`), se reusa en los reintentos, y la RPC devuelve el resultado
   original si la llave ya existe.
6. **El cobro va en una transacción con bloqueo de fila. En el cobro nunca hay UI optimista.** La
   RPC de cobro bloquea la fila (`FOR UPDATE`), valida y registra todo o nada. El front espera la
   respuesta con el botón deshabilitado. En general, UI optimista solo donde se puede deshacer.
7. **Realtime solo avisa (notify-then-refetch): invalida la query y la pantalla recarga.** El
   payload de Realtime no se usa como dato ni se escribe en la caché: solo
   `queryClient.invalidateQueries(...)`. Al reconectar el canal, invalida lo visible.
8. **Tabla de eventos append-only para trazabilidad y tiempos (no es event sourcing).** Cada RPC
   escribe su evento en la misma transacción. Nadie hace UPDATE ni DELETE sobre eventos. El estado
   actual vive en sus tablas; los eventos no se reproducen para reconstruirlo.
9. **Los proveedores externos (facturación, pagos) van detrás de una interfaz.**
   `ProveedorFacturacion` (Nubefact) y `ProveedorPagos` (Culqi). Es el único lugar con puertos y
   adaptadores.
10. **Descartado: event sourcing, Clean Architecture por capas, offline-first, Redux** (y
    microservicios). No los propongas. Estado del servidor en TanStack Query; estado local con
    `useState`/`useReducer`. El service worker solo precachea el cascarón de la app: nunca cachea
    respuestas de Supabase. Sin capa de caché aparte (Redis u otra): TanStack Query + Realtime y el
    cálculo nocturno de Salud bastan. Se reevalúa solo si se mide lentitud con más clientes.
11. **Textos de la app en español, tuteando. "Mikuy" siempre con M mayúscula.**

Otras decisiones del documento de arquitectura: RBAC con el rol en `perfiles`, aplicado en RLS y
en rutas. El plan del restaurante (`restaurante.plan`) decide qué se ve. Umbrales, minutos de aviso
y color son configuración guardada como datos. Salud lee vistas SQL y un cálculo nocturno de "tu
normal" con pg_cron.

## Modelo de datos

La fuente de verdad es [docs/MODELO-DATOS.md](docs/MODELO-DATOS.md). La carta real de Sabor de
Morenas está en [docs/carta-sabor-de-morenas.json](docs/carta-sabor-de-morenas.json). Principios que
no se negocian:

- **Una fila por unidad** en `items`: "Sopa seca ×13" son 13 filas; la UI agrupa. Así funcionan las
  tandas, el cobro por partes y separar mesas.
- **El precio se congela al pedir**: `items` guarda nombre, presentación, precio y estación del
  momento.
- **"Hoy" es la fecha del calendario** en la zona horaria del restaurante (`jornada`), aunque haya
  turnos o varios cierres de caja.
- **Todo es configurable por restaurante** (estaciones, tiempo de preparación, umbrales, portero).
  El tiempo de preparación es **un promedio general por restaurante**, no por plato. Lo edita el
  administrador cuando quiera (por defecto 25 min) y alimenta las sugerencias de cocina y Salud.
  Nada propio de Sabor de Morenas queda fijo en el código.
- **Roles**: `administrador`, `mozo`, `estacion` (cocina, bebidas, barra…) y `portero`. Por encima
  del personal solo existe `administrador` (lo usa la dueña o la administradora). No hay rol `dueno`
  ni `admin` aparte.
- **Solo el administrador, y con motivo**: anular, cortesías y descuentos.
- Si una tarea pide algo que el modelo no cubre, para y pregunta antes de inventar tablas.

## Estructura del front

```
src/
  features/<feature>/   pedidos, cocina, caja, salud, admin, auth
    ui/                 pantallas y componentes de la feature
    hooks/              useQuery / useMutation de la feature
    servicio.ts         llamadas a Supabase (select y rpc), sin React
  shared/               supabase.ts, queryClient.ts y lo que usen dos o más features
  assets/logo/          SVG oficiales del logo
```

- Una feature no importa de otra; lo común sube a `shared/`.
- Importa con el alias `@/` (apunta a `src/`).
- Prettier sin punto y coma, comillas simples, 100 columnas. Ordena las clases de Tailwind.

## Diseño

La fuente de verdad es [Mikuy · Identidad](https://claude.ai/artifact/Fv12oTY8n22WjhnXKnRGS1).
Los tokens viven en `src/index.css` (`@theme`). La paleta de Tailwind está vaciada: solo existen
los colores de Mikuy.

- `estado-*` son reservados para el estado de un plato o una mesa, nunca decoran. Barra con
  `border-estado-<x>` y etiqueta con `text-estado-<x>-texto`. El estado se dice siempre con
  palabra o ícono, nunca solo con color.
- El color del restaurante (`resto-aji`, `resto-anil`, `resto-algarrobo`) solo pinta la franja
  superior y sus botones, con texto `blanco-cal`. `aji-panca` se usa poco.
- Una sola sombra (`shadow-tarjeta`) y radio por defecto de 8px (`rounded`).
- Títulos y cifras en `font-titulos` (Schibsted Grotesk 800). El resto en Atkinson Hyperlegible,
  que ya es la fuente por defecto.
- Logo: usa los archivos de `src/assets/logo/` según el fondo (`-invertido` sobre `carbon`).
  Nunca lo recolorees ni lo reemplaces por texto.
- Montos en soles con dos decimales (`S/ 56.00`), tiempos en minutos, frases cortas, sin emojis.

## Base de datos

Hay dos entornos (detalle en [ESTADO.md](ESTADO.md)). **No hay Supabase local ni Docker.**

- **Demo (desarrollo y pruebas)**: el proyecto **desing-clothes** (`exxcgaikbjfojpfpiocj`, plan
  gratis), compartido con otra app. Lo usan `npm run dev` (`.env`) y el deploy de pruebas
  (`.env.production`).
- **Pro (producción)**: la v1.0.0 sale en Supabase Pro, haya o no cliente fundador. Todo debe seguir
  listo para esa mudanza ([docs/MUDANZA-PRO.md](docs/MUDANZA-PRO.md); tarea #33 de TaskView).
- Los tests de base (pgTAP) corren en GitHub Actions, que levanta su propio Supabase con Docker en
  el CI. Nunca en la máquina de Diego.

### Esquema `mikuy`

- Todo lo de Mikuy vive en los esquemas `mikuy` y `mikuy_privado`, nunca en `public`, en todos los
  entornos. supabase-js apunta a `mikuy` (`db: { schema: 'mikuy' }`).
- `mikuy` está expuesto en la API: tablas, vistas y las RPC que llama el front. `mikuy_privado` no
  está expuesto: ahí van las funciones `security definer` (las que usan las políticas RLS y las que
  hacen el trabajo de cada RPC). Patrón: la RPC en `mikuy` valida y llama a su función en
  `mikuy_privado`.
- Las migraciones crean todo con grants explícitos, porque en `mikuy` no hay grants por defecto:
  - Esquema: `usage` para `anon`, `authenticated` y `service_role` (ya está en la primera
    migración).
  - Tablas: RLS activado y `grant select` solo donde una política lo permite. Nunca `insert`,
    `update` ni `delete` para `anon` o `authenticated`: las escrituras van por RPC.
  - Funciones: `revoke execute ... from public` y `grant execute` solo al rol que la usa. Postgres
    da `execute` a `public` por defecto.
- RLS por membresía: estar autenticado no basta. Cada política exige que el usuario tenga perfil en
  `mikuy.perfiles`, y el restaurante sale de ahí. En el demo hay usuarios de la otra app.
- Lo compartido lleva prefijo: Edge Functions `mikuy-*`, jobs de pg_cron `mikuy_*` y buckets
  `mikuy-*`.

### Migraciones

- Todo cambio de esquema es una migración en `supabase/migrations/`
  (`npx supabase migration new <nombre>`), nunca un cambio a mano. Sin `BEGIN`/`COMMIT` propios.
- Una migración aplicada no se edita: se crea otra. `db:push:demo` compara checksums y se detiene
  si una cambió.
- En Pro se usa el flujo normal de la CLI (`supabase db push`). En el CI, `supabase start` y
  `db reset` solo para correr pgTAP.
- **Toda migración es compatible hacia atrás**: primero se agrega lo nuevo y lo viejo se borra en
  una versión posterior, cuando ya nada lo usa. Así un rollback de la app nunca choca con la base.
- **Antes de aplicar migraciones al demo o a Pro hay un respaldo** del esquema `mikuy` (tarea #35).
  Hasta que exista el script, avisa a Diego antes de cada `db:push:demo`.
- En el demo, **solo** `npm run db:push:demo`. Nunca `supabase link`, `db push`, `config push` ni
  `migration repair` contra desing-clothes: su historial tiene 13 migraciones de otra app.
- En el demo no toques `public`, `storage`, `auth` ni `supabase_migrations`, ni el trigger
  `on_auth_user_created`. Ese trigger crea una fila en `public.profiles` por cada usuario nuevo de
  auth, incluidos los que cree Mikuy.
- `DATABASE_URL` vive solo en `.env`: nunca la imprimas, la loguees ni la copies a otro archivo.
  `.env.production` se commitea y solo lleva valores públicos.
- En la nube, `GET /rest/v1/` a secas exige la secret key. Para verificar que `mikuy` está expuesto,
  usa `Accept-Profile: mikuy` contra una tabla, o el 406 de un esquema inexistente.

## Dominio

- Producción: https://mikuy.nrlsys.com, custom domain del Worker `mikuy` en la zona nrlsys.com.
- En el Auth del demo, el Site URL es de la otra app: Mikuy solo agrega sus URLs a Redirect URLs.
- Cuando se compre mikuy.dev, cambia: `routes` en `wrangler.jsonc`, `data-domains` de Umami en
  `src/shared/observabilidad.ts`, las URLs de Auth del proyecto en uso, este archivo, README y
  ESTADO.md.

## Comandos

```sh
npm run dev         # desarrollo
npm run build       # tsc -b + build con el service worker
npm run lint        # ESLint
npm run typecheck   # tsc -b
npm run format      # Prettier
npm run db:push:demo  # migraciones pendientes al demo (desing-clothes); pide confirmación
npm run deploy      # build + wrangler deploy a https://mikuy.nrlsys.com
```

Antes de cada commit deben pasar `lint`, `typecheck` y `build`. Actualiza `ESTADO.md` en el mismo
commit que cambia lo que funciona.

- Nunca corras `npm run deploy` ni `npm run db:push:demo` sin que te lo pidan.
- GlitchTip y Umami se inician en `src/shared/observabilidad.ts`, solo en producción. No mandes
  datos personales: nada de `Sentry.setUser`, ni nombres, teléfonos o montos de clientes en tags,
  contextos o mensajes de error.

## Calidad

Hay dos niveles. Durante el desarrollo se avanza rápido; lo pesado se hace al final, en la Fase 4,
antes de publicar una versión.

**Durante el desarrollo (cada tarea)**

- El CI en verde es la verificación: lint, typecheck, build, pgTAP, gitleaks y npm audit. Si pasa,
  la tarea está lista. No agregues verificaciones manuales extra (navegador, producción, capturas)
  salvo que Diego las pida.
- Toda tabla nueva trae RLS y un test pgTAP de aislamiento entre restaurantes.
- Las reglas que tocan dinero o permisos (cobro, anulaciones, estados) llevan su test pgTAP. El
  resto de tests puede esperar a la Fase 4.
- Ningún dato personal en GlitchTip, Umami ni en logs.
- No despliegues ni apliques migraciones sin que te lo pidan.

**Antes de la v1.0.0 y de cada versión (Fase 4)**

- Avisos de seguridad de Supabase en cero y revisión OWASP ASVS nivel 1 (tarea #36).
- Límite de intentos en PIN y login.
- Tests de punta a punta (Playwright) de los flujos principales, incluido el cobro por partes.
- Simulación de servicio con 4 usuarios (tarea #37) y prueba con agentes de IA (tarea #38).
- Si el CI no está en verde, no se publica.

## Versiones y despliegues

- **Versionado semántico**: `vMAYOR.MENOR.PARCHE`. MAYOR rompe compatibilidad, MENOR agrega
  funcionalidad, PARCHE corrige. Cada versión publicada lleva su etiqueta git y su entrada en
  `CHANGELOG.md`.
- **Rollback de la app**: `wrangler rollback` vuelve a la versión anterior del Worker. Por eso las
  migraciones son compatibles hacia atrás.
- Ninguna versión sale a clientes sin pasar el nivel "Antes de cada versión" de Calidad.

## TaskView

Proyecto Mikuy (goalId 4).

- Columnas: 11 To Do, 12 Doing, 13 Done, 14 Bloqueado.
- Etiquetas: 6 Feature, 7 Bug, 8 Refactor, 9 Infra, 10 Docs.
- Al empezar una tarea, muévela a Doing. Al terminar, a Done y `complete=true`.
- Bugs, deuda y bloqueos se anotan como tarea apenas aparecen, con su etiqueta. Si algo bloquea
  una tarea, muévela a Bloqueado.
- No borres tareas ni crees varias de golpe sin preguntar.
- Listas: 1 Fase 0 · Cimientos, 2 Fase 1 · Ingreso y carta, 3 Fase 2 · Pedidos en tiempo real,
  4 Fase 3 · Caja y Salud, 5 Ideas a futuro, 6 Fase 4 · Calidad y lanzamiento.
- No agregues ideas a "Ideas a futuro" por tu cuenta: las ideas se aterrizan primero con Diego.

## Cómo trabajar

Diego trabaja solo con Claude Code. Cuando diga "inicia la Fase N" (o "sigue con la Fase N"):

1. Lee la lista de esa fase en TaskView y las notas de cada tarea (Qué es, Pasos, Notas).
2. Haz las tareas en orden. Cada una: a Doing, implementación, CI en verde, un commit, a Done con
   `complete=true`, y `ESTADO.md` al día en el mismo commit.
3. Pregunta solo lo que bloquea una decisión de negocio que no esté en este archivo ni en `docs/`.
   Si una tarea espera una respuesta, muévela a Bloqueado y sigue con la siguiente.
4. Antes de aplicar migraciones al demo, muestra el plan y espera el OK de Diego.
5. Al terminar la fase: resumen corto de qué quedó, qué decidiste por tu cuenta y qué falta.

Las pantallas siguen el lienzo de diseño y el sistema de identidad (Referencias). Salud sigue
[docs/SALUD.md](docs/SALUD.md). Si Diego trae una idea nueva, primero aterrízala con él (qué problema
resuelve, para quién, en qué plan, cuánto cuesta hacerla) y solo con su OK créala en "Ideas a futuro".

## Referencias

- [Mikuy · Pantallas del MVP](https://claude.ai/artifact/WJBQUpbPNd3YiVwHhCA8PE): las pantallas
  diseñadas (estilo A · Carbón), una por rol.

- [Mikuy · Identidad](https://claude.ai/artifact/Fv12oTY8n22WjhnXKnRGS1): logo, color,
  tipografía, voz.
- [Mikuy · Arquitectura](https://claude.ai/artifact/57n7DZ14tRHLPU2yfHZdSE): diagrama y "cómo
  viaja un pedido".
- Vault: `proyectos/mikuy/arquitectura.md` (decisiones y por qué), `proyectos/mikuy/modelo-datos.md`
  y `proyectos/mikuy/salud.md`.
