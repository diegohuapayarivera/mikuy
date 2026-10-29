// Aplica supabase/migrations al Supabase demo (desing-clothes) sin la CLI ni psql.
// Ese proyecto es de otra app: su historial (supabase_migrations) no es nuestro y no se toca.
// Mikuy lleva el suyo en mikuy.migraciones. En local y en Pro se usa la CLI con los mismos archivos.
import { createHash } from 'node:crypto'
import { readdir, readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { stdin, stdout } from 'node:process'
import { createInterface } from 'node:readline/promises'
import pg from 'pg'

const PROYECTO_DEMO = 'exxcgaikbjfojpfpiocj'
const CARPETA = 'supabase/migrations'
// Raíces "Supabase Root 2021 CA" (vencen en 2031 y 2035), sacadas de la CLI de Supabase.
const CA_SUPABASE = 'supabase/certs/supabase-root-2021-ca.pem'

interface Migracion {
  version: string
  nombre: string
  archivo: string
  sql: string
  checksum: string
}

function fallar(mensaje: string): never {
  console.error(`✗ ${mensaje}`)
  process.exit(1)
}

// DATABASE_URL es secreta: se lee de .env y nunca se imprime.
function leerConexion(): string {
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
  // Candado: este script solo escribe en el demo. Local y Pro usan la CLI.
  if (!url.username.endsWith(`.${PROYECTO_DEMO}`) && !url.hostname.includes(PROYECTO_DEMO)) {
    fallar(`DATABASE_URL no apunta al proyecto demo (${PROYECTO_DEMO}).`)
  }
  // El TLS se configura en el cliente; un sslmode en la URL lo pisaría.
  url.searchParams.delete('sslmode')
  return url.toString()
}

async function leerMigraciones(): Promise<Migracion[]> {
  const archivos = (await readdir(CARPETA)).filter((a) => a.endsWith('.sql')).sort()
  return Promise.all(
    archivos.map(async (archivo) => {
      const partes = /^(\d+)_(.+)\.sql$/.exec(archivo)
      if (!partes) fallar(`Nombre inválido: ${archivo}. Se espera <timestamp>_<nombre>.sql.`)
      const sql = await readFile(join(CARPETA, archivo), 'utf8')
      // Cada migración corre dentro de la transacción del script.
      if (/^\s*(begin|commit|rollback)\s*;/im.test(sql)) {
        fallar(`${archivo} trae BEGIN/COMMIT propio. Quítalo: el script ya la envuelve.`)
      }
      const checksum = createHash('sha256').update(sql).digest('hex')
      return { version: partes[1], nombre: partes[2], archivo, sql, checksum }
    }),
  )
}

async function confirmar(pregunta: string) {
  const rl = createInterface({ input: stdin, output: stdout })
  const respuesta = (await rl.question(pregunta)).trim().toLowerCase()
  rl.close()
  return respuesta === 'si' || respuesta === 'sí'
}

async function main() {
  const conexion = leerConexion()
  const migraciones = await leerMigraciones()

  // TLS verificado contra la CA de Supabase (el pooler no usa una CA pública).
  const ca = await readFile(CA_SUPABASE, 'utf8')
  const cliente = new pg.Client({ connectionString: conexion, ssl: { ca } })
  try {
    await cliente.connect()
  } catch (error) {
    fallar(`No pude conectar al demo: ${error instanceof Error ? error.message : String(error)}`)
  }

  try {
    const { rows } = await cliente.query<{ existe: boolean }>(
      "select to_regclass('mikuy.migraciones') is not null as existe",
    )
    const aplicadas = new Map<string, string>()
    if (rows[0]?.existe) {
      const registro = await cliente.query<{ version: string; checksum: string }>(
        'select version, checksum from mikuy.migraciones',
      )
      for (const fila of registro.rows) aplicadas.set(fila.version, fila.checksum)
    }

    for (const m of migraciones) {
      const checksum = aplicadas.get(m.version)
      if (checksum && checksum !== m.checksum) {
        fallar(`${m.archivo} cambió después de aplicarse. No se edita: crea una migración nueva.`)
      }
    }
    const enRepo = new Set(migraciones.map((m) => m.version))
    const ajenas = [...aplicadas.keys()].filter((v) => !enRepo.has(v))
    if (ajenas.length > 0) {
      console.warn(`! En el demo hay versiones que no están en el repo: ${ajenas.join(', ')}`)
    }

    const pendientes = migraciones.filter((m) => !aplicadas.has(m.version))
    if (pendientes.length === 0) {
      console.log('✓ El demo está al día: no hay migraciones pendientes.')
      return
    }

    console.log(`Migraciones pendientes en el demo (${PROYECTO_DEMO}):`)
    for (const m of pendientes) console.log(`  · ${m.archivo}`)
    if (!(await confirmar(`¿Aplicar ${pendientes.length}? Escribe "si" para continuar: `))) {
      console.log('Cancelado. No se aplicó nada.')
      return
    }

    for (const m of pendientes) {
      try {
        await cliente.query('begin')
        await cliente.query("set local lock_timeout = '5s'")
        await cliente.query("set local statement_timeout = '60s'")
        await cliente.query(m.sql)
        await cliente.query(
          'insert into mikuy.migraciones (version, nombre, checksum) values ($1, $2, $3)',
          [m.version, m.nombre, m.checksum],
        )
        await cliente.query('commit')
        console.log(`✓ ${m.archivo}`)
      } catch (error) {
        await cliente.query('rollback')
        fallar(
          `${m.archivo} falló y se deshizo: ${error instanceof Error ? error.message : String(error)}`,
        )
      }
    }
  } finally {
    await cliente.end()
  }
}

await main()
