# Auditoría de Billing DB — 2026-11-07

> Informe histórico previo a las correcciones. La migración 031 y las pruebas
> posteriores se describen en [correcciones de integridad](financial-boundary-corrections.md).
> Las reproducciones positivas citadas abajo se sustituyeron por regresiones negativas.

Dictamen: **no está lista para aprobación final ni producción**. La cobertura
funcional es amplia y las pruebas existentes pasan, pero se reprodujeron brechas
de integridad con el rol real de ejecución. La afirmación anterior de que la BD
estaba completa fue demasiado amplia.

## Alcance y criterio

Se auditó el árbol de trabajo local, incluidas las migraciones nuevas 029/030;
el último commit es `5c0df70`. No se auditó una base desplegada. No se cambiaron
migraciones ni restricciones durante esta auditoría. Se agregaron reproducciones
y una opción de ejecución para conservar la evidencia.

Fuentes locales consultadas:

- `dlc-docs/09-microservices/services/06-billing-service/data-model.md` y `events.md`.
- `dlc-docs/02-domain/entities-and-rules.md`, reglas BIL-001 a BIL-016.
- `dlc-docs/06-data/monetary-calculation.md`, `data-dictionary.md` y `migration-strategy.md`.
- ADR-015, contrato OpenAPI de Billing y NFR-008 de recuperación.
- Migraciones, permisos, pruebas y documentación de este repositorio.
- Repositorios locales de API, Portal e Infra. La documentación histórica de
  integración se distingue de una verificación actual de esos servicios.

## Hallazgos reproducidos

| ID | Prioridad | Hallazgo y efecto |
|---|---|---|
| A01 | Alta | `billing_runtime` puede agregar un `invoice_item` después de emitir la factura. La composición cambia sin actualizar total, versión ni evidencia de emisión. Viola la protección del historial emitido (BIL-006/BIL-009). |
| A02 | Alta | `billing_runtime` puede cambiar un borrador vacío a `ISSUED` con total 10. El trigger no verifica que existan ítems ni que su suma coincida con el total. Contradice el requisito de emisión con al menos un ítem y totales calculados por Billing. |
| A03 | Media | Ambos catálogos aceptan `NaN` como precio. PostgreSQL considera que satisface `> 0`; no representa un importe COP válido y puede causar fallos en los consumidores que esperan `BigDecimal`/Money. |

### A01: composición posterior a la emisión

Evidencia: `01_ddl/03_tables/010_invoice_storage.sql:25` solo declara claves y
referencias para `invoice_items`; `03_dcl/01_grants/changelog.yaml:43` concede
INSERT al runtime. No hay trigger que compruebe el estado de la factura al
insertar una relación. La reproducción agregó un ítem de 99 a una factura emitida
de total 10; ambas escrituras fueron aceptadas.

Corrección requerida: nueva migración que serialice la asignación con el bloqueo
de la factura y rechace nuevas relaciones en estados emitidos/pagados/cancelados.
Probar también la carrera entre asignación y emisión. No basta proteger UPDATE
del ítem: INSERT en la tabla de relaciones cambia la factura igualmente.

### A02: emisión sin contenido o total validado por la BD

Evidencia: la definición vigente de `protect_invoice_issuance` en
`01_ddl/03_tables/026_price_corrections.sql:47` valida transición e identidad,
pero no cantidad/suma de ítems. La reproducción emitió el borrador vacío.

`JdbcInvoiceIssuance` sí verifica contenido, elegibilidad y suma antes del UPDATE.
Por tanto, esta prueba demuestra una brecha de integridad de la BD; **no demuestra
que un usuario pueda hacerlo por el endpoint actual**. A01 también se reprodujo
mediante SQL autorizado al runtime, no mediante una explotación HTTP.

Corrección requerida: validar la emisión en una capacidad transaccional o trigger
de BD, conservando el flujo de la API y bloqueos compatibles. Las fixtures de
pagos que actualmente emiten facturas vacías deberán representar facturas válidas.

### A03: precios no finitos

Evidencia: `01_ddl/03_tables/changelog.yaml:24` y `:115` verifican únicamente
positividad. Dos INSERT con `'NaN'::numeric` fueron aceptados como runtime.

Corrección requerida: restricciones nuevas de precio finito dentro del rango
monetario, revisión de datos previos y pruebas para ambos catálogos. Mantener
intactos los changesets aplicados. La validación Java no reemplaza esta restricción.

## Evidencia ejecutada

Comando: `python tests/run-isolated.py --audit`.

Entorno: PostgreSQL 16 y Liquibase 4.31.1, contenedor/red desechables, sin puertos
publicados y sin URL ni credenciales de bases existentes.

- Liquibase validate, actualización desde cero y segunda actualización: correctos.
- Las 12 suites SQL actuales: correctas.
- Configuración de métodos: los seis códigos funcionan; métodos desconocidos o
  desactivados se rechazan y el runtime no puede editar la configuración.
- Reejecución del SQL de configuración conserva decisiones del owner y agrega
  códigos faltantes.
- Pruebas de auditoría: confirmaron A01, A02 y A03; todas sus escrituras se revirtieron.
- El ejecutor terminó correctamente y eliminó sus recursos desechables.

La reproducción se conserva en `tests/audit/financial-boundaries.sql`.
Su éxito **confirma los defectos**, no significa que esas invariantes estén
aprobadas. Se mantiene fuera de las suites normales por ese motivo.

## Cobertura que sí está implementada

Existen almacenamiento y controles para catálogos/versiones/vigencias, fuentes
clínicas, deduplicación, cuentas por encuentro, admisiones/congelamiento, cargos
manuales, correcciones auditadas, asignación única por paciente, emisión, pagos
parciales/totales, rechazo de sobrepago, recibos históricos, idempotencia y outbox.
La aritmética de snapshots usa decimal exacto y redondeo por línea; los roles de
migración y ejecución están separados. Esto permite continuar desarrollo y QA,
pero no neutraliza los hallazgos anteriores.

## Pendientes de evidencia y operación

| ID | Estado | Requisito pendiente |
|---|---|---|
| E01 | No verificado para 029/030 | Actualizar una copia con datos de la revisión anterior y comprobar preservación de datos/compatibilidad. Aplicar dos veces desde cero no equivale a esta prueba; la estrategia de migración exige ambos caminos. |
| E02 | Sin evidencia localizada en DB/Infra | Restauración real de backup y medición de recuperación; NFR-008 y el DoD exigen comprobarla. No se afirma que un backup externo no exista, sino que no se aportó evidencia verificable. |
| E03 | Aceptación diferida | Integración actual con Clinical, IAM, Appointments, Worker y navegador. La API documenta estas puertas pendientes en `docs/integration/pre-integration-readiness.md`. No se ejecutaron aquí ni se sustituyeron por SQL. |
| E04 | Por coordinar en destino | Verificar secuencia de migraciones compartida, privilegios reales, revisión desplegada y preparación operativa. Las migraciones locales 029/030 aún no acreditan ejecución en destino. |

Observación de rendimiento: el listado global de facturas ordena por
`created_at,invoice_id`, pero el índice existente empieza por `patient_id`.
También falta evidencia de un índice por estado/fecha solicitado por el modelo.
Evaluar con EXPLAIN y volumen representativo; sin medición no se afirma un
incumplimiento de latencia ni se prescribe un índice innecesario.

## Condición para aprobar

Cerrar A01–A03 mediante migraciones nuevas y pruebas negativas/de concurrencia,
verificar actualización con datos previos y aportar evidencia de recuperación e
integración en el entorno destino. Hasta entonces: cobertura funcional avanzada,
con integridad y aceptación final pendientes.
