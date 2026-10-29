# Mikuy

Gestión de pedidos para restaurantes: salón, cocina, bebidas y caja en tiempo real.
PWA en Vite + React + TypeScript + Tailwind, con Supabase detrás.

## Cómo correrlo

```sh
npm install
cp .env.example .env   # ya apunta al Supabase local
npm run db:start       # necesita Docker corriendo
npm run dev
```

| Script              | Qué hace                                       |
| ------------------- | ---------------------------------------------- |
| `npm run dev`       | Servidor de desarrollo                         |
| `npm run build`     | Typecheck + build de producción (con el SW)    |
| `npm run preview`   | Sirve el build para probar la PWA instalable   |
| `npm run lint`      | ESLint                                         |
| `npm run typecheck` | `tsc -b`                                       |
| `npm run format`    | Prettier (`format:check` para verificar en CI) |
| `npm run db:start`  | Levanta Supabase local                         |
| `npm run db:stop`   | Lo apaga                                       |
| `npm run db:reset`  | Recrea la base local: migraciones + `seed.sql` |
| `npm run deploy`    | Build + `wrangler deploy` a Cloudflare Workers |

## Deploy

1. `npx wrangler login` (una vez).
2. Crea `.env.production` con la URL y la key de Supabase en la nube, `VITE_GLITCHTIP_DSN` y
   `VITE_UMAMI_WEBSITE_ID` (ver `.env.example`).
3. `npm run deploy`.

Reglas de arquitectura en [CLAUDE.md](CLAUDE.md). Avance real en [ESTADO.md](ESTADO.md).
