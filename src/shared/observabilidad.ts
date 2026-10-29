import * as Sentry from '@sentry/react'

// GlitchTip (errores) y Umami (visitas). Solo en producción y solo si están sus variables;
// sin ellas la app funciona igual y no hace nada.
export function iniciarObservabilidad() {
  if (!import.meta.env.PROD) return
  iniciarGlitchTip()
  iniciarUmami()
}

function iniciarGlitchTip() {
  const dsn = import.meta.env.VITE_GLITCHTIP_DSN
  if (!dsn) return

  Sentry.init({
    dsn,
    environment: 'production',
    // Sin datos personales. Sentry 11 recolecta todo por defecto (IP incluida): se apaga explícito.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
    },
    // GlitchTip no usa sesiones de Sentry.
    integrations: (integraciones) => integraciones.filter((i) => i.name !== 'BrowserSession'),
    beforeBreadcrumb(miga) {
      // Lo que se loguea en consola puede llevar datos de clientes o del personal.
      if (miga.category === 'console') return null
      const url: unknown = miga.data?.url
      if (miga.data && typeof url === 'string') miga.data.url = sinQuery(url)
      return miga
    },
    beforeSend(evento) {
      delete evento.user
      if (evento.request?.url) evento.request.url = sinQuery(evento.request.url)
      return evento
    },
  })
}

function iniciarUmami() {
  const websiteId = import.meta.env.VITE_UMAMI_WEBSITE_ID
  if (!websiteId) return

  const script = document.createElement('script')
  script.defer = true
  script.src = 'https://stats.nrlsys.com/script.js'
  script.dataset.websiteId = websiteId
  // Solo cuenta visitas en el dominio real, no en previews ni en localhost.
  script.dataset.domains = 'mikuy.dev'
  document.head.appendChild(script)
}

// Los filtros de la API REST van en la query (?nombre=eq.…) y pueden traer datos personales.
function sinQuery(url: string) {
  return url.split('?')[0]
}
