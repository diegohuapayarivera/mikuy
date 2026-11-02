// Conexión al Supabase demo (desing-clothes) para los scripts db:*.
// DATABASE_URL es secreta: se lee de .env y nunca se imprime. Con MIKUY_DB_CI=1, y solo dentro de
// GitHub Actions, apunta al Supabase efímero del CI para probar los scripts sin tocar el demo.
import { readFile } from 'node:fs/promises'
import { stdin, stdout } from 'node:process'
import { createInterface } from 'node:readline/promises'
import pg from 'pg'

export const PROYECTO_DEMO = 'exxcgaikbjfojpfpiocj'
// Raíces "Supabase Root 2021 CA" (vencen en 2031 y 2035), sacadas de la CLI de Supabase.
const CA_SUPABASE = 'supabase/certs/supabase-root-2021-ca.pem'
const DB_CI = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'

export function fallar(mensaje: string): never {
  console.error(`✗ ${mensaje}`)
  process.exit(1)
}

function urlDelDemo(): string {
  try {
    process.loadEnvFile('.env')
  } catch {
    fallar('No encontré .env en la raíz del repo.')
  }
  const valor = process.env.DATABASE_URL
  if (!valor) fallar('Falta DATABASE_URL en .env (session pooler del Supabase demo).')

  let url: URL
  try {
    url = new URL(valor)
  } catch {
    fallar('DATABASE_URL no es una URL válida.')
  }
  // Candado: estos scripts solo escriben en el demo. Pro usa la CLI.
  if (!url.username.endsWith(`.${PROYECTO_DEMO}`) && !url.hostname.includes(PROYECTO_DEMO)) {
    fallar(`DATABASE_URL no apunta al proyecto demo (${PROYECTO_DEMO}).`)
  }
  // El TLS se configura en el cliente; un sslmode en la URL lo pisaría.
  url.searchParams.delete('sslmode')
  return url.toString()
}

export async function conectar(): Promise<{ cliente: pg.Client; destino: string }> {
  let cliente: pg.Client
  let destino: string
  if (process.env.MIKUY_DB_CI === '1') {
    if (process.env.CI !== 'true') fallar('MIKUY_DB_CI=1 solo se usa dentro de GitHub Actions.')
    cliente = new pg.Client({ connectionString: DB_CI })
    destino = 'el Supabase del CI'
  } else {
    // TLS verificado contra la CA de Supabase (el pooler no usa una CA pública).
    const ca = await readFile(CA_SUPABASE, 'utf8')
    cliente = new pg.Client({ connectionString: urlDelDemo(), ssl: { ca } })
    destino = `el demo (${PROYECTO_DEMO})`
  }
  try {
    await cliente.connect()
  } catch (error) {
    fallar(
      `No pude conectar a ${destino}: ${error instanceof Error ? error.message : String(error)}`,
    )
  }
  return { cliente, destino }
}

export async function confirmar(pregunta: string) {
  const rl = createInterface({ input: stdin, output: stdout })
  const respuesta = (await rl.question(pregunta)).trim().toLowerCase()
  rl.close()
  return respuesta === 'si' || respuesta === 'sí'
}
