# Provisioning de dispositivos (Flutter F1)

Iteración F1 conecta la interfaz de dispositivos con el DevicePlatform real,
provider-neutral, sin control físico.

## Modelo visible para la app

- `PhysicalDevice`: hardware real y su `physicalAreaId`.
- `DeviceEndpoint`: canal o componente funcional del hardware y su `controlledAreaId`.
- `DeviceBinding`: relación semántica entre un endpoint y una entidad funcional de Gamma.
- `GatewayInfo`: topología gateway → subdispositivos (derivada de
  `parent_device_id` / `is_subdevice` del DTO).
- `DeviceProvisioningState`: `discovered`, `enriched`, `partiallyConfigured`,
  `configured`, `missing`, `disabled`.
- `DeviceHealthState`: `online`, `offline`, `unknown`, `sleeping`,
  `unreachable`, `authError` (fallback seguro `unknown`).
- `HomeArea`: espacio de la casa (directorio desde el catálogo legacy).

Un switch triple puede estar físicamente en `pasillo` y tener endpoints
asociados a `cocina`, `comedor` y `patio`.

## Frontera con el backend

`DeviceInventoryRepository` es el seam entre la UI y el transporte:

- `load()`
- `discover()`
- `assignPhysicalArea(deviceId, areaId)`
- `assignEndpointArea(deviceId, endpointId, areaId)`
- `identify(deviceId, endpointId?)` — inerte en producción F1
- `supportsIdentify` — false en `HttpDeviceInventoryRepository`

`HttpDeviceInventoryRepository` implementa el seam contra la API de
DevicePlatform (`/api/v1/devices`). El contrato exacto está en
`docs/deviceplatform_contract.md`.

## Estado actual (F1 cerrado)

- `HttpDeviceInventoryRepository` es el repositorio por defecto de
  `DevicesPage`; el mock queda solo para tests/dev.
- Inventario real renderizado: dispositivos nuevos/pendientes, áreas, detalle,
  gateways bajo infraestructura, health agregado del proveedor.
- `ENRICHED` es pendiente; `CONFIGURED`/`MISSING`/`DISABLED` no.
- Área física y área controlada por endpoint persisten por API y el estado
  canónico del backend reemplaza el local.
- Discovery (`Buscar dispositivos`) usa `POST /api/v1/devices/discovery`
  (solo lectura/refresco; sin efectos físicos) y recarga el snapshot canónico.
- Identificar está deshabilitado/oculto en el flujo HTTP:
  “Disponible después de validar el control local.”
- No hay toggle ON/OFF en la pantalla nueva.

## Pendientes

- Control físico (ON/OFF, identify) tras el smoke LAN/hardware.
- Selector real de `DeviceBinding`: el backend expone CRUD de bindings pero
  aún no publica un catálogo de entidades lógicas seleccionables. Se conserva
  el placeholder y se documenta la falta de contrato.
