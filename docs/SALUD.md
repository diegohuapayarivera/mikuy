# Salud del restaurante

Pantalla del administrador que reemplaza "ventas del día". Todo sale de los pedidos, cambios de estado y cobros que Mikuy ya registra. Las pantallas están en el lienzo de diseño (Admin-salud, Admin-salud-basico, Admin-salud-inicio, Admin-salud-reglas).

## Principios
- **Sin IA:** cada frase es una plantilla con datos ("El que más tarda hoy es {plato}: {min} min"). Si una frase no se puede calcular, no va.
- **Se entiende sin explicación:** nada de códigos de color que memorizar; cada número dice qué es y, si importa, cuál es el normal.
- **Lo normal es de cada restaurante:** los límites se piden al dar de alta y se editan en "Cómo lo calculamos". Mikuy sugiere "tu promedio real" (últimas 4 semanas) con un botón Usar; nunca cambia valores solo.
- **No desanimar al cliente nuevo:** los primeros 14 días no hay comparaciones; se muestra "Lo que ya lograste con Mikuy". El plan Completo compara contra el promedio del mismo día de la semana ("tu normal"), nunca contra un solo día anterior.
- **Problemas visibles, redactados para actuar.**
- **"Hoy"** es la fecha del calendario del restaurante. El tiempo de preparación general del restaurante (`restaurantes.tiempo_prep_min`) define cuándo un plato va atrasado.

## Bloques
- **Ahora mismo** (en vivo): mesas con clientes, por cobrar, platos atrasados, mesas esperando. Pocos KPIs, con ícono y color.
- **Chequeo por área** (Bien / Atento / Revisar; el resumen arriba toma el peor estado). Valores iniciales de Sabor de Morenas:

| Área | Mide | Bien | Atento | Revisar |
|---|---|---|---|---|
| Ventas | Vendido vs tu normal (solo Completo) | ≥ 90% | ≥ 75% | < 75% |
| Cocina | Min para servir una mesa completa | ≤ 60 | ≤ 90 | > 90 |
| Salón | Min hasta el primer pedido | ≤ 10 | ≤ 20 | > 20 |
| Caja | Min de cuenta pedida a cobrada | ≤ 10 | ≤ 20 | > 20 |
| Carta | Platos agotados en el día | 0 | ≤ 2 | > 2 |
| Equipo | Mesas abiertas por mozo | ≤ 4 | ≤ 6 | > 6 |

- **Avisos** (minutos, configurables): plato atrasado 40, bebida 10, mesa sin pedir 15, cuenta sin cobrar 10.
- **Tu equipo:** la mesa cuenta para el mozo que la abrió; "ayudó a cobrar" se muestra aparte.
- "Casi no salen" siempre usa 30 días. El efectivo en caja solo aparece en "Hoy".

## Por plan
- **Básico:** solo hoy, chequeo contra los valores configurados, mesas y vendido por mozo.
- **Completo:** 7 y 30 días, comparación con tu normal (cálculo nocturno con pg_cron), mozos a fondo, ventas por hora, tiempos por tramo y análisis de carta.
