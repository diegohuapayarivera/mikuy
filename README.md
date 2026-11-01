# Mikuy

Gestión de pedidos para restaurantes: salón, cocina, bebidas y caja en tiempo real.
PWA en Vite + React + TypeScript + Tailwind, con Supabase detrás.

## Cómo correrlo

```sh
npm install
cp .env.example .env   # apunta al Supabase demo; DATABASE_URL solo si vas a migrar
npm run dev
```

No hay Supabase local ni Docker: `npm run dev` usa el Supabase demo (desing-clothes, esquema
`mikuy`). Los tests de base (pgTAP) corren solo en GitHub Actions.

| Script                 | Qué hace                                                               |
| ---------------------- | ---------------------------------------------------------------------- |
| `npm run dev`          | Servidor de desarrollo                                                 |
| `npm run build`        | Typecheck + build de producción (con el SW)                            |
| `npm run preview`      | Sirve el build para probar la PWA instalable                           |
| `npm run lint`         | ESLint                                                                 |
| `npm run typecheck`    | `tsc -b`                                                               |
| `npm run format`       | Prettier (`format:check` para verificar en CI)                         |
| `npm run db:push:demo` | Aplica las migraciones pendientes al Supabase demo (pide confirmación) |
| `npm run deploy`       | Build + `wrangler deploy` a Cloudflare Workers                         |

## CI

En cada push y PR, GitHub Actions corre tres jobs. Si alguno falla, no hay merge ni deploy.

- **front**: lint, typecheck, formato, build y `npm audit` (bloquea con hallazgos altos o críticos).
- **secretos**: gitleaks sobre todo el historial.
- **db**: levanta su propio Supabase con Docker, aplica las migraciones y corre los tests pgTAP de
  `supabase/tests/`.

## Deploy

1. `npx wrangler login` (una vez).
2. `npm run deploy`. El build toma los valores públicos de `.env.production`, que está en el repo,
   y se publica en https://mikuy.nrlsys.com con las cabeceras de seguridad de `public/_headers`.

Reglas de arquitectura en [CLAUDE.md](CLAUDE.md). Avance real en [ESTADO.md](ESTADO.md).
