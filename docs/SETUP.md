# Configuración y alcance

## Demo

Ejecuta `npm start` con Node.js 24 o abre `index.html`. No necesita servicios ni paquetes externos. Para alojar solo la demo, publica únicamente `index.html`; no publiques la carpeta de trabajo de la aplicación personal.

## Código conectado

`index_netlify/index.html` es una copia de referencia: contiene `https://your-project.supabase.co` y `YOUR_SUPABASE_PUBLISHABLE_KEY`. Solo funcionará con un proyecto propio cuyo esquema, Auth, políticas y backend se hayan configurado.

El frontend espera las tablas `tx`, `settings` y `bank_balances`. El sincronizador espera la RPC `bank_sync_worker`, configuración bancaria privada en Vault y un estado de activación. Los archivos de evolución SQL muestran cómo se implementó el proyecto original; no constituyen una instalación completa ni deben ejecutarse indiscriminadamente. En particular, la actualización de horario presupone que ya existe un job y el bloqueo de Wallet presupone la función `add_payment` del entorno original.

No se incluyen el esquema inicial de `tx`/`settings`, el alta en el proveedor, los consentimientos, el registro de secretos ni el comando privado original del cron. Para adaptar el backend hay que completar esas piezas en un proyecto independiente, revisar el orden de las migraciones y comprobar RLS con usuarios de prueba.

## Credenciales

La URL y clave publicable del frontend son configuración de cliente; no sustituyen las políticas de autorización. Las claves privadas, credenciales de servidor, sesiones y tokens de ejecución deben permanecer fuera del repositorio y del navegador. Los archivos `.pem`, `.env` y carpetas privadas están excluidos de Git.

## Verificaciones SQL

Los archivos SQL de pruebas requieren un entorno desechable preparado con las funciones y configuración esperadas. Aunque usan transacciones revertidas, pueden depender de secretos de prueba. No se ejecutan en CI ni deben apuntarse al proyecto personal.
