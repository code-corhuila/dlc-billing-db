# Aplicación local e integración — 2026-11-07

Actualización posterior: a solicitud del usuario, la base `billing_test` y el
contenedor `dlc-billing-db-test` se renombraron a **`dlc-billing-db`**. Se conservó
el mismo OID de base y almacenamiento. Verificación posterior: 31 changesets,
dos precios y seis métodos activos. Los nombres antiguos que aparecen debajo
corresponden al registro histórico de la aplicación inicial. El administrador
PostgreSQL sigue siendo `billing_test`; cambiar el nombre no rota credenciales.

## Base persistente actualizada

Destino identificado y actualizado: contenedor `dlc-billing-db-test`, PostgreSQL 16,
base `billing_test`, red privada `dlc-billing-test-net`. Es una base local de pruebas;
no se identificó ni modificó un entorno de producción/QA remoto.

Antes tenía seis changesets, dos precios y ningún registro en reglas adicionales
o idempotencia. El esquema y tres tablas pertenecían al administrador heredado
`billing_test`; el historial Liquibase estaba en `public`.

Se hizo un respaldo lógico completo antes de cambiar propietarios o aplicar SQL.
La transición DBA explícita de `deploy/legacy-local-owner-transition.sql` conservó
los objetos/datos y trasladó las dos tablas de historial a `billing`. Esquema,
tablas e historial quedaron bajo `billing_migrator`. No se rotaron credenciales
existentes ni se concedió DDL al runtime. Liquibase se ejecutó con un login
temporal limitado a `billing_migrator`; ese login se eliminó al finalizar.

Resultado comprobado:

- 31 changesets aplicados, incluido `billing-031-financial-boundaries`.
- Liquibase validate y update correctos; status informa actualizado.
- Los seis métodos de pago están activos.
- Conteos y hashes de los datos previos sin cambios.
- Identidades, rutas y checksums de los seis changesets históricos sin cambios.
- Función nueva y esquema pertenecen al migrador; no quedan logins temporales.
- Regresiones de A01–A03 correctas directamente en esta BD con `billing_runtime`;
  las filas de prueba se revirtieron.
- El respaldo anterior se restauró en una BD temporal y se compararon los datos
  originales de las tres tablas. La copia temporal se eliminó; el respaldo se conserva.

Evidencia privada local, excluida de Git: `.local-validation/application-result.json`,
`liquibase-{validate,update,status}.log`, `persistent-boundary-regression.log` y
el archivo `billing-before-b791fb2c4542.dump`. El respaldo puede contener datos;
no se adjunta a este informe ni se publica.

## Integración real del flujo financiero

La aplicación persistente y la aceptación integrada se separaron para no cargar
identidades/servicios sintéticos en la BD existente. La integración utiliza la
misma revisión del changelog, aplicada a otra base desechable, y los servicios
reales IAM, Appointments, Billing, Gateway, Shell y Portal.

Artefactos usados:

| Componente | Imagen / revisión |
|---|---|
| Billing API | `dlc-billing-api:db031-local`, empaquetada desde el código local actual |
| Billing Portal | `dlc-billing-portal:db031-local`, artefacto `2.0.4-local-20261107` |
| IAM API | `dlc-iam-api:billing-integration-5d53afa` |
| Appointments API | `dlc-appointments-api:billing-integration-73ed387` |
| Gateway | `dlc-api-gateway:billing-runtime-test` |
| Shell | `dlc-front:billing-logout-local` |

Los IDs completos de imágenes y SHA-256 de JAR/entry.js se guardaron en
`.local-validation/artifact-identities.json`. No se publicaron imágenes.
Se utilizaron los checkouts reales de IAM y Appointments ya disponibles en
`dlc-billing-api/target`; la carpeta hermana `dlc-iam-db` es una plantilla vacía
y no se presentó como implementación del owner.

El escenario HTTP de `test_payment_pdf_real_owners` pasó: login real, creación y
emisión de borrador, pago parcial/final, conflictos de versión/sobrepago,
concurrencia, replay, rechazo por rol, historial, PDF actual y PDF/resumen por
evento después de pagos posteriores. Se validaron los eventos contra los schemas
oficiales y la revocación tras logout. También se comprobó commit financiero
con el broker detenido. El token de servicio de la prueba observa el contrato
privado; no constituye una implementación de Worker.

La prueba Chromium también pasó: login real, emisión desde el Portal, dos pagos
por la interfaz, tres descargas PDF (emitida/parcial/pagada), estado final
`PAID:0.00`, logout y rechazo 401 de la sesión revocada. No se interceptaron
ni simularon respuestas del navegador.

Resultados finales: HTTP 1/1 correcto en 192,687 s; Chromium 1/1 correcto en
140,860 s. Evidencia: `.local-validation/test_payment_pdf_real_owners.log` y
`test_browser_financial.log`. El resultado, tres PDF y captura de pantalla
del navegador están en `dlc-billing-api/target/billing-e2e-10bdc3ee34-browser`.
Ambos entornos temporales terminaron y se limpiaron; la BD local persistente
quedó activa. No se dejaron servicios de integración abiertos.

Reproducción: `python deploy/validate-local-integration.py`, después de preparar
las imágenes locales indicadas. Las credenciales y usuarios del harness son
temporales; no se usan credenciales de la BD persistente. El harness elimina
sus propios contenedores, red y archivos de credenciales al terminar.

## Alcance pendiente

Los procedimientos/precios y la cita terminal del escenario son datos sintéticos
de prueba, no ejecución del productor Clinical. No se validó una entrega real de
email por Worker ni la obtención real de destinatarios por Patients. Eso requiere
sus servicios/configuraciones reales. Tampoco se verificaron TLS, credenciales
institucionales, RPO/RTO o promoción de artefactos en un destino remoto.

La integración financiera local no equivale a declarar completa toda la plataforma.
