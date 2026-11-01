# Mikuy — Modelo de datos del MVP

Todo vive en el esquema `mikuy`. Cada tabla de negocio lleva `restaurante_id`, RLS por membresía (el usuario debe tener perfil activo en ese restaurante) y solo lectura desde el cliente: las escrituras van por funciones RPC. Montos en `numeric(10,2)`, soles.

## Principios que guían el modelo

1. **Cada plato pedido es una fila por unidad.** "Sopa seca ×13" son 13 filas en `items`; la UI siempre agrupa. Así funcionan las tandas en cocina, el cobro por partes y separar mesas sin lógica especial.
2. **El precio se congela al pedir.** `items` guarda nombre, presentación, precio y estación del momento. Cambiar la carta no altera lo vendido.
3. **"Hoy" es la fecha del calendario** en la zona horaria del restaurante (`jornada`), sin importar turnos ni cierres de caja.
4. **Todo es configurable por restaurante**: estaciones, tiempos de preparación, umbrales de Salud, minutos de aviso, uso de portero. Nada propio de Sabor de Morenas queda fijo en el código.
5. **Lo delicado lo hace la administradora y con motivo**: anular un plato, cortesías y descuentos.
6. **Cada cambio de estado deja un evento** en `eventos` (append-only), en la misma transacción.

## Restaurante y personas

| Tabla | Campos clave | Notas |
|---|---|---|
| `restaurantes` | nombre, slug, plan (`basico`/`completo`), color (`aji`/`anil`/`algarrobo`), zona_horaria (`America/Lima`), usa_portero, tiempo_prep_min_defecto, pin_minutos (30) | Un registro por cliente. |
| `config_salud` | restaurante_id, umbrales por área (bien/atento), minutos de aviso (plato, bebida, mesa sin pedir, cuenta) | Valores iniciales del onboarding; editables en "Cómo lo calculamos". |
| `perfiles` | restaurante_id, user_id (auth), nombre, rol, estacion_id, activo | Roles: `admin`, `dueno`, `mozo`, `estacion`, `portero`. `estacion` usa `estacion_id` (cocina, bebidas, barra…). |
| `pines` | perfil_id, hash, expira_en, usado_en | Un uso, vence según `pin_minutos`. Generar uno nuevo invalida el anterior. Nunca en texto plano. |

## Carta

| Tabla | Campos clave | Notas |
|---|---|---|
| `estaciones` | restaurante_id, nombre, orden | Las define cada restaurante: Cocina, Bebidas, Barra… |
| `categorias` | restaurante_id, nombre, orden, estacion_id | `estacion_id` nulo = no se prepara (p. ej. derecho de corcho). |
| `platos` | categoria_id, nombre, descripcion, estacion_id (anula la de la categoría), tiempo_prep_min, disponible, orden | `disponible` lo prende y apaga la administradora (platos con horario, feriados). `tiempo_prep_min` nulo usa el del restaurante. |
| `presentaciones` | plato_id, nombre, precio, activa, agotada_en (fecha) | Todo plato tiene al menos una ("Normal"). Tamaños, proteína o porción son presentaciones. Cocina marca `agotada_en = hoy`. |

## Salón y pedidos

| Tabla | Campos clave | Notas |
|---|---|---|
| `mesas` | restaurante_id, nombre, orden, activa | La administradora agrega o quita mesas cuando quiere, incluso en plena atención. |
| `atenciones` | restaurante_id, tipo (`mesa`/`llevar`), nombre_llevar, mozo_id, personas, estado, jornada, abierta_en, cerrada_en | Una visita. Es del mozo que toma el primer pedido. Para llevar: sin mesa, con nombre. |
| `atencion_mesas` | atencion_id, mesa_id, desde, hasta | Juntar = varias filas abiertas; separar = cerrar una fila. Índice único parcial: una mesa solo en una atención abierta. |
| `envios` | atencion_id, mozo_id, llave_idempotencia (única), enviado_en | Lo que el mozo manda a cocina de una vez. Reintentar con la misma llave no duplica. |
| `items` | atencion_id, envio_id, presentacion_id, plato_nombre, presentacion_nombre, precio, estacion_id, nota, estado, tanda_id, cortesia_motivo, anulado_motivo, actualizado_en | **Una fila por unidad.** Estados: `pendiente` → `preparando` → `listo` → `entregado`; `pendiente` → `no_disponible`; cualquiera antes de entregado → `anulado` (solo admin, con motivo). |
| `tandas` | estacion_id, iniciada_por, iniciada_en | Agrupa las unidades que cocina empieza juntas. Mikuy sugiere las más antiguas; cocina elige. |

## Caja

| Tabla | Campos clave | Notas |
|---|---|---|
| `cajas` | restaurante_id, abierta_por, abierta_en, monto_inicial, cerrada_en, monto_contado | Puede haber varias por día; Salud suma todo bajo "Hoy". |
| `cobros` | atencion_id, caja_id, cobrado_por, llave_idempotencia (única), subtotal, descuento, descuento_motivo, total, creado_en | Un pago parcial o total. Descuento solo admin, con motivo. |
| `cobro_items` | cobro_id, item_id (**único**) | Cada unidad se cobra una sola vez: la base impide el doble cobro. |
| `pagos` | cobro_id, medio (`efectivo`/`tarjeta`/`yape`/`plin`/`otro`), monto, recibido, vuelto | Pagos mixtos = varias filas. |

La atención se cierra cuando todas sus unidades no anuladas están cobradas (y, si es para llevar, entregadas). El cobro no depende de la entrega: lo de llevar se paga antes o después.

## Trazabilidad

| Tabla | Campos clave | Notas |
|---|---|---|
| `eventos` | id (bigserial), restaurante_id, tipo, entidad, entidad_id, de, a, perfil_id, datos (jsonb), creado_en | Solo INSERT. Fuente de los tiempos de Salud y del historial de anulaciones y cortesías. |

## Comandos (RPC) previstos

Salón: `abrir_atencion`, `juntar_mesas`, `separar_mesa`, `enviar_pedido`.
Cocina/estaciones: `iniciar_tanda`, `marcar_listo`, `marcar_no_disponible`, `marcar_agotada`.
Mozo: `marcar_entregado`.
Caja: `abrir_caja`, `cerrar_caja`, `cobrar`.
Administración: `anular_item`, `dar_cortesia`, `activar_plato`, CRUD de carta, mesas, estaciones y perfiles, `generar_pin`.
Edge Function: `mikuy-canjear-pin`.

## Fuera del MVP (anotado)

Propina, horarios automáticos de platos, reportes de anulaciones (Completo), inventario, facturación SUNAT, club de fidelización.
