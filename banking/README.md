# Sincronizador bancario

Código de referencia del backend privado de Mis Gastos. Consulta [arquitectura](../docs/ARCHITECTURE.md) y [configuración y alcance](../docs/SETUP.md).

- `index.ts`: worker Deno con autenticación, lease y procesamiento por banco.
- `transactions.mjs`: referencias, validación, normalización y paginación.
- `balances.mjs`: selección de una representación válida del saldo EUR.
- `migrations/`: estructura privada y RPC del sincronizador.
- `updates/`: evolución de snapshots, permisos, monitorización y horario.

Los archivos no contienen la configuración bancaria real. El backend requiere infraestructura previa y no se activa al abrir la demo.
