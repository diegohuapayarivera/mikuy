# Mikuy

SaaS multi-tenant de gestión de pedidos para restaurantes: salón, cocina, bebidas y caja en
tiempo real. Producto de NRL Systems (mikuy.dev). Un dev, meta de 4–5 restaurantes.

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
    respuestas de Supabase.
11. **Textos de la app en español, tuteando. "Mikuy" siempre con M mayúscula.**

Otras decisiones del documento de arquitectura: RBAC con el rol en `perfiles`, aplicado en RLS y
en rutas. El plan del restaurante (`restaurante.plan`) decide qué se ve. Umbrales, minutos de aviso
y color son configuración guardada como datos. Salud lee vistas SQL y un cálculo nocturno de "tu
normal" con pg_cron.

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

## Comandos

```sh
npm run dev         # desarrollo
npm run build       # tsc -b + build con el service worker
npm run lint        # ESLint
npm run typecheck   # tsc -b
npm run format      # Prettier
npm run db:start    # Supabase local (necesita Docker)
npm run db:stop
npm run db:reset    # recrea la base local con supabase/migrations y supabase/seed.sql
npm run deploy      # build + wrangler deploy a Cloudflare Workers
```

Antes de cada commit deben pasar `lint`, `typecheck` y `build`. Actualiza `ESTADO.md` en el mismo
commit que cambia lo que funciona.

- Los cambios de esquema van como migración en `supabase/migrations/`, nunca a mano en la base.
- Nunca corras `npm run deploy` sin que te lo pidan.

## TaskView

Proyecto Mikuy (goalId 4).

- Columnas: 11 To Do, 12 Doing, 13 Done, 14 Bloqueado.
- Etiquetas: 6 Feature, 7 Bug, 8 Refactor, 9 Infra, 10 Docs.
- Al empezar una tarea, muévela a Doing. Al terminar, a Done y `complete=true`.
- Bugs, deuda y bloqueos se anotan como tarea apenas aparecen, con su etiqueta. Si algo bloquea
  una tarea, muévela a Bloqueado.
- No borres tareas ni crees varias de golpe sin preguntar.

## Referencias

- [Mikuy · Identidad](https://claude.ai/artifact/Fv12oTY8n22WjhnXKnRGS1): logo, color,
  tipografía, voz.
- [Mikuy · Arquitectura](https://claude.ai/artifact/57n7DZ14tRHLPU2yfHZdSE): diagrama y "cómo
  viaja un pedido".
- Vault: `proyectos/mikuy/arquitectura.md` (decisiones y por qué) y `proyectos/mikuy/salud.md`.
