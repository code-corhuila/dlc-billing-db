# Correcciones de integridad financiera — 2026-11-07

Aplicación posterior en la BD local persistente y aceptación entre servicios:
[registro de aplicación e integración](local-application-and-integration-2026-11-07.md).

La migración nueva `billing-031-financial-boundaries` corrige los hallazgos
A01–A03 de la [auditoría](auditoria-bd-2026-11-07.md). No modifica changesets
anteriores, importes ni datos históricos para hacerlos pasar silenciosamente.

| Hallazgo | Corrección |
|---|---|
| A01: agregar ítems después de emitir | Cada INSERT en `invoice_items` bloquea su factura con `FOR UPDATE` y exige estado DRAFT. El bloqueo serializa la asignación con la emisión. |
| A02: emitir sin ítems o con total arbitrario | Las facturas deben insertarse como borradores. Al emitir, la BD exige al menos un ítem, todos BILLED, y suma de líneas igual al total. Se mantienen los controles previos de versión, identidad e historial de pagos/correcciones. |
| A03: precios NaN | Restricciones nuevas de límite finito en ambos catálogos, además de las reglas de positividad existentes. Los datos anteriores se validan al aplicar las restricciones. |

Las funciones de trigger usan un `search_path` explícito y no conceden capacidades
nuevas al runtime. Las validaciones actuales de elegibilidad, autorización y
Appointment finalizada permanecen en la API; estos controles de BD no las sustituyen.

## Compatibilidad y datos previos

La migración también comprueba facturas ya emitidas/parcialmente pagadas/pagadas.
Si faltan ítems, no están facturados o su suma difiere del total, la migración se
detiene y revierte el changeset. Un catálogo con NaN también la detiene. El owner
debe investigar y preparar una recuperación auditada; no borrar facturas ni
recalcular dinero histórico como solución automática.

Dos fixtures Java de la API necesitaban adaptación porque construían estados
ahora inválidos: `PaymentTransactionTest` emitía una factura vacía y
`PriceCorrectionRecordingTest` insertaba una factura directamente emitida.
Ahora crean ítems y transitan desde DRAFT. No se cambió código productivo de API
ni contratos HTTP. Las fixtures SQL de pagos/recibos usan el mismo principio.

## Verificación reproducible

`python tests/run-isolated.py --upgrade --restore` ejecuta:

- Migración real desde cero y repetición sin cambios de historial.
- Las 13 suites SQL, incluidas regresiones negativas de A01–A03, inserción directa
  de factura emitida, totales incorrectos y asignación tras pagos parciales/totales.
- Dos transacciones reales en ambos órdenes: emisión antes de asignación y
  asignación antes de emisión. Se observa la espera de bloqueo en
  `pg_stat_activity` y se exige que la operación competidora sea rechazada.
- Actualización desde la revisión previa `5c0df70` a la versión actual con datos de factura,
  ítems, precio y pago parcial; compara conteos y hashes de las filas y conserva
  la desactivación de CASH. Inyecta una factura histórica inválida y exige que
  detenga la migración antes de volver a probar con datos consistentes.
- Respaldo lógico real, restauración en otra BD del contenedor, comparación de
  todos los conteos/hashes de tablas Billing y verificación de permisos restaurados.

`python tests/run-isolated.py --api-only` ejecuta cuatro clases transaccionales
de la API contra PostgreSQL real con owner `billing_migrator` y `billing_runtime`.
No acepta resultados con errores, fallos o pruebas omitidas.

El antiguo script que confirmaba vulnerabilidades fue sustituido por
`tests/financial-boundaries.sql`: ahora el éxito exige rechazar los estados
inválidos y aceptar el flujo financiero válido.

Resultados ejecutados el 2026-11-07: 13 suites SQL correctas, ambas carreras
concurrentes correctas, migración/repetición correctas, actualización desde
`5c0df70908f8` sin cambios en hashes financieros y rechazo del historial inválido.
Respaldo/restauración y verificación de datos/permisos: 10,30 segundos en el
entorno desechable. Las 26 pruebas reales de las cuatro clases Java pasaron con
cero fallos, errores u omisiones. Ambos ejecutores terminaron correctamente y
eliminaron sus contenedores/redes. Ese tiempo local no es una medición de RTO de producción.

## Límites pendientes en destino

Esta verificación usa datos sintéticos y bases desechables. No acredita despliegue
ni aceptación integrada con Clinical/IAM/Appointments/Worker/Portal. La restauración
local dentro del mismo clúster no verifica aprovisionamiento de roles/secretos en
un clúster nuevo, backups de producción, PITR ni los RPO/RTO institucionales.
La coordinación de versiones compartidas y la aceptación operativa del entorno
destino siguen pendientes. Los tres defectos reproducidos tienen corrección local;
eso no equivale a autorización final de producción.
