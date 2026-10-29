import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error(
    'Faltan VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY. Copia .env.example a .env y complétalo.',
  )
}

// Todo lo de Mikuy vive en el esquema `mikuy`, nunca en `public`.
// Lecturas con supabase.from(...).select(); escrituras solo con supabase.rpc(...).
export const supabase = createClient(url, anonKey, { db: { schema: 'mikuy' } })
