// Carga Sabor de Morenas en el demo: restaurante, umbrales de Salud, estaciones, la carta de
// docs/carta-sabor-de-morenas.json y las mesas 1 a 12 de ejemplo.
// Repetible sin duplicar: cada fila se identifica por su nombre dentro de su padre y, si ya existe,
// se actualiza. No toca lo que el administrador cambia en la app (disponible, activa).
import { readFile } from 'node:fs/promises'
import { conectar, confirmar, fallar } from './demo-db.ts'

interface Opcion {
  nombre: string
  precio: number
}
interface Plato {
  nombre: string
  descripcion?: string
  estacion?: string
  opciones: Opcion[]
}
interface Categoria {
  nombre: string
  estacion: string
  platos: Plato[]
}
interface Carta {
  restaurante: string
  estaciones: string[]
  tiempo_prep_min: number
  categorias: Categoria[]
}

const CARTA = 'docs/carta-sabor-de-morenas.json'
const RESTAURANTE = {
  nombre: 'Sabor de Morenas',
  slug: 'sabor-de-morenas',
  plan: 'basico',
  color: 'aji',
  zona_horaria: 'America/Lima',
}
// Valores iniciales de Salud de Sabor de Morenas (Vault: proyectos/mikuy/salud.md).
const CONFIG_SALUD = {
  ventas_bien_pct: 90,
  ventas_atento_pct: 75,
  cocina_bien_min: 60,
  cocina_atento_min: 90,
  salon_bien_min: 10,
  salon_atento_min: 20,
  caja_bien_min: 10,
  caja_atento_min: 20,
  carta_bien_agotados: 0,
  carta_atento_agotados: 2,
  equipo_bien_mesas: 4,
  equipo_atento_mesas: 6,
  aviso_plato_min: 40,
  aviso_bebida_min: 10,
  aviso_mesa_sin_pedir_min: 15,
  aviso_cuenta_min: 10,
}
const MESAS = 12
// Los platos que la carta marca sin estación (derecho de corcho) van a una categoría sin estación:
// así lo prevé el modelo ("categoría sin estación = solo caja").
const SIN_ESTACION = 'ninguna'
const CATEGORIA_SIN_ESTACION = 'Otros cargos'

function validar(carta: Carta) {
  const estaciones = new Set(carta.estaciones)
  for (const c of carta.categorias) {
    if (!estaciones.has(c.estacion))
      fallar(`Categoría ${c.nombre}: estación desconocida ${c.estacion}`)
    for (const p of c.platos) {
      if (p.estacion && p.estacion !== SIN_ESTACION && !estaciones.has(p.estacion)) {
        fallar(`Plato ${p.nombre}: estación desconocida ${p.estacion}`)
      }
      if (p.opciones.length === 0) fallar(`Plato ${p.nombre}: sin presentaciones`)
    }
  }
}

async function main() {
  const carta = JSON.parse(await readFile(CARTA, 'utf8')) as Carta
  if (carta.restaurante !== RESTAURANTE.nombre)
    fallar(`${CARTA} no es la carta de ${RESTAURANTE.nombre}`)
  validar(carta)

  const platos = carta.categorias.flatMap((c) => c.platos)
  const presentaciones = platos.reduce((n, p) => n + p.opciones.length, 0)
  const conSinEstacion = platos.some((p) => p.estacion === SIN_ESTACION)
  const categorias = carta.categorias.length + (conSinEstacion ? 1 : 0)

  const { cliente, destino } = await conectar()
  try {
    console.log(`Se cargará ${RESTAURANTE.nombre} en ${destino}:`)
    console.log(
      `  ${carta.estaciones.length} estaciones, ${categorias} categorías, ${platos.length} platos, ` +
        `${presentaciones} presentaciones y ${MESAS} mesas.`,
    )
    if (!(await confirmar('¿Continuar? Escribe "si" para continuar: '))) {
      console.log('Cancelado. No se cargó nada.')
      return
    }

    await cliente.query('begin')
    const uno = async (sql: string, valores: unknown[]) => {
      const { rows } = await cliente.query<{ id: string }>(sql, valores)
      return rows[0].id
    }

    const restaurante = await uno(
      `insert into mikuy.restaurantes (nombre, slug, plan, color, zona_horaria, tiempo_prep_min)
       values ($1, $2, $3, $4, $5, $6)
       on conflict (slug) do update set nombre = excluded.nombre, plan = excluded.plan,
         color = excluded.color, zona_horaria = excluded.zona_horaria,
         tiempo_prep_min = excluded.tiempo_prep_min
       returning id`,
      [
        RESTAURANTE.nombre,
        RESTAURANTE.slug,
        RESTAURANTE.plan,
        RESTAURANTE.color,
        RESTAURANTE.zona_horaria,
        carta.tiempo_prep_min,
      ],
    )

    const columnas = Object.keys(CONFIG_SALUD)
    await cliente.query(
      `insert into mikuy.config_salud (restaurante_id, ${columnas.join(', ')})
       values ($1, ${columnas.map((_, i) => `$${i + 2}`).join(', ')})
       on conflict (restaurante_id) do update set
         ${columnas.map((c) => `${c} = excluded.${c}`).join(', ')}, actualizado_en = now()`,
      [restaurante, ...Object.values(CONFIG_SALUD)],
    )

    const estaciones = new Map<string, string>()
    for (const [i, nombre] of carta.estaciones.entries()) {
      estaciones.set(
        nombre,
        await uno(
          `insert into mikuy.estaciones (restaurante_id, nombre, orden) values ($1, $2, $3)
           on conflict (restaurante_id, nombre) do update set orden = excluded.orden
           returning id`,
          [restaurante, nombre, i + 1],
        ),
      )
    }

    const categoria = (nombre: string, orden: number, estacion: string | null) =>
      uno(
        `insert into mikuy.categorias (restaurante_id, nombre, orden, estacion_id)
         values ($1, $2, $3, $4)
         on conflict (restaurante_id, nombre) do update set orden = excluded.orden,
           estacion_id = excluded.estacion_id
         returning id`,
        [restaurante, nombre, orden, estacion],
      )
    const sinEstacion = conSinEstacion
      ? await categoria(CATEGORIA_SIN_ESTACION, carta.categorias.length + 1, null)
      : null

    for (const [i, c] of carta.categorias.entries()) {
      const idCategoria = await categoria(c.nombre, i + 1, estaciones.get(c.estacion) ?? null)
      for (const [j, p] of c.platos.entries()) {
        const vaSinEstacion = p.estacion === SIN_ESTACION
        // La estación del plato solo se guarda si anula la de su categoría.
        const estacionPropia =
          p.estacion && !vaSinEstacion && p.estacion !== c.estacion
            ? (estaciones.get(p.estacion) ?? null)
            : null
        const plato = await uno(
          `insert into mikuy.platos (
             restaurante_id, categoria_id, nombre, descripcion, estacion_id, orden
           ) values ($1, $2, $3, $4, $5, $6)
           on conflict (categoria_id, nombre) do update set descripcion = excluded.descripcion,
             estacion_id = excluded.estacion_id, orden = excluded.orden
           returning id`,
          [
            restaurante,
            vaSinEstacion ? sinEstacion : idCategoria,
            p.nombre,
            p.descripcion ?? null,
            estacionPropia,
            j + 1,
          ],
        )
        for (const [k, o] of p.opciones.entries()) {
          await cliente.query(
            `insert into mikuy.presentaciones (restaurante_id, plato_id, nombre, precio, orden)
             values ($1, $2, $3, $4, $5)
             on conflict (plato_id, nombre) do update set precio = excluded.precio,
               orden = excluded.orden`,
            [restaurante, plato, o.nombre, String(o.precio), k + 1],
          )
        }
      }
    }

    for (let n = 1; n <= MESAS; n++) {
      await cliente.query(
        `insert into mikuy.mesas (restaurante_id, nombre, orden) values ($1, $2, $3)
         on conflict (restaurante_id, nombre) do update set orden = excluded.orden`,
        [restaurante, `Mesa ${n}`, n],
      )
    }

    await cliente.query('commit')

    const { rows } = await cliente.query<Record<string, string>>(
      `select
         (select count(*) from mikuy.estaciones where restaurante_id = $1) as estaciones,
         (select count(*) from mikuy.categorias where restaurante_id = $1) as categorias,
         (select count(*) from mikuy.platos where restaurante_id = $1) as platos,
         (select count(*) from mikuy.presentaciones where restaurante_id = $1) as presentaciones,
         (select count(*) from mikuy.mesas where restaurante_id = $1) as mesas`,
      [restaurante],
    )
    const t = rows[0]
    console.log(
      `✓ ${RESTAURANTE.nombre} en ${destino}: ${t.estaciones} estaciones, ${t.categorias} categorías, ` +
        `${t.platos} platos, ${t.presentaciones} presentaciones, ${t.mesas} mesas.`,
    )
  } catch (error) {
    await cliente.query('rollback').catch(() => {})
    fallar(`El seed falló y se deshizo: ${error instanceof Error ? error.message : String(error)}`)
  } finally {
    await cliente.end()
  }
}

await main()
