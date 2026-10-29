# Mikuy

Gestión de pedidos para restaurantes: salón, cocina, bebidas y caja en tiempo real.
PWA en Vite + React + TypeScript + Tailwind, con Supabase detrás.

## Cómo correrlo

```sh
npm install
cp .env.example .env   # completa la URL y la anon key de Supabase
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

Reglas de arquitectura en [CLAUDE.md](CLAUDE.md). Avance real en [ESTADO.md](ESTADO.md).
