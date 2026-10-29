import logo from '@/assets/logo/mikuy-horizontal.svg'

// Pantalla de prueba de la Fase 0: confirma que cargan el logo, las fuentes y los tokens.
const estados = [
  { etiqueta: 'Pendiente', barra: 'border-estado-pendiente', texto: 'text-estado-pendiente-texto' },
  {
    etiqueta: 'Preparando',
    barra: 'border-estado-preparando',
    texto: 'text-estado-preparando-texto',
  },
  { etiqueta: 'Listo', barra: 'border-estado-listo', texto: 'text-estado-listo-texto' },
  {
    etiqueta: 'Por cobrar',
    barra: 'border-estado-por-cobrar',
    texto: 'text-estado-por-cobrar-texto',
  },
  {
    etiqueta: 'No hay',
    barra: 'border-estado-no-disponible',
    texto: 'text-estado-no-disponible-texto',
  },
  { etiqueta: 'Entregado', barra: 'border-estado-entregado', texto: 'text-estado-entregado-texto' },
]

export default function App() {
  return (
    <main className="mx-auto flex min-h-dvh max-w-xl flex-col justify-center gap-8 px-4 py-12">
      <img src={logo} alt="Mikuy" className="h-12 w-auto self-start" />

      <div>
        <h1 className="text-[32px] leading-[1.15]">Todo listo para empezar</h1>
        <p className="mt-2 text-tinta-suave">
          El logo, las letras y los colores ya cargan. Pronto verás aquí el salón, la cocina, las
          bebidas y la caja.
        </p>
      </div>

      <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {estados.map((estado) => (
          <li
            key={estado.etiqueta}
            className={`rounded border-l-[5px] bg-tarjeta px-3 py-3 shadow-tarjeta ${estado.barra}`}
          >
            <span className={`text-[13px] font-bold tracking-[0.04em] uppercase ${estado.texto}`}>
              {estado.etiqueta}
            </span>
          </li>
        ))}
      </ul>
    </main>
  )
}
