# Contrato de API DevicePlatform — Flutter F1 (congelado en Phase 0)

Fuente de verdad: backend AssistantGamma, `src/api/device_routes.py`,
`src/features/devices/models.py`, `tests/test_device_api.py`, verificado en
el commit `ba81ff0` (más los commits del backend `a746095` con campos de
topología y `e8b7ed7` que agrega `is_gateway` y la semántica de limpieza del
área física).

URL base del backend: la misma `ApiClient.baseUrl` que usa la API legacy
(por ejemplo `http://127.0.0.1:8420`).

## Rutas (exactas)

| Operación | Método | Path | Body | Respuesta |
|---|---|---|---|---|
| inventory/list | GET | `/api/v1/devices` | — (`?pending=true` opcional) | `{"devices": [DeviceDTO]}` |
| device detail | GET | `/api/v1/devices/{device_id}` | — | `DeviceDTO` |
| provider health | GET | `/api/v1/devices/health` | — | `{provider_id: ProviderHealth}` |
| discovery | POST | `/api/v1/devices/discovery` | — | `{provider_id: {generation, candidates, enriched, new, missing}}` |
| refresh device | POST | `/api/v1/devices/{device_id}/refresh` | — | `DeviceDTO` |
| physical area | PUT | `/api/v1/devices/{device_id}/physical-area` | `{"area_id": str\|null}` (clave requerida; null limpia) | `DeviceDTO` |
| endpoint area | PUT | `/api/v1/devices/{device_id}/endpoints/{endpoint_id}` | `{"controlled_area_id": str\|null}` | `DeviceDTO` |
| binding create | POST | `/api/v1/devices/{device_id}/bindings` | `{"endpoint_id", "entity_id", "capability", "controlled_area_id"?}` | `DeviceDTO` |
| binding remove | DELETE | `/api/v1/devices/{device_id}/bindings/{binding_id}` | — | `DeviceDTO` |
| identify | POST | `/api/v1/devices/{device_id}/identify` | — | `{"supported": false, "reason"}` — NO se usa en F1 |
| enable/disable | PUT | `/api/v1/devices/{device_id}/enabled`, `/endpoints/{endpoint_id}/enabled` | `{"enabled": bool}` | `DeviceDTO` (fuera del alcance UI de F1) |

Mapeo de errores: device/endpoint/binding/discovery desconocido → **404**;
fallo de persistencia/proyección → **503**; valor inválido (falta `area_id`,
enum inválido, binding inválido) → **422**. No existe 409 ni PATCH.

Semántica de presencia del área física: un body **sin** `area_id` →
422 `area_id required`; `{"area_id": null}` → limpia el área física (200);
`{"area_id": "living_room"}` → asigna (200).

## DeviceDTO (exacto)

```json
{
  "device_id": "str",
  "provider_id": "str",
  "display_name": "str|null",
  "manufacturer": "str|null",
  "model": "str|null",
  "product_id": "str|null",
  "category": "str|null",
  "physical_area_id": "str|null",
  "parent_device_id": "str|null",
  "is_subdevice": false,
  "is_gateway": false,
  "provisioning_state": "str",
  "enabled": true,
  "endpoints": [{
    "endpoint_id": "str",
    "display_name": "str|null",
    "controlled_area_id": "str|null",
    "enabled": true,
    "exposed_to_resolver": true,
    "binding_id": "str|null",
    "binding_entity": "str|null",
    "capabilities": [{
      "capability": "str",
      "readable": true,
      "writable": true,
      "range": [0.0, 100.0] | null,
      "enum_values": ["str"] | null,
      "confidence": "HIGH|MEDIUM|LOW|UNKNOWN",
      "evidence": ["str"]
    }]
  }]
}
```

Los campos de topología `parent_device_id` / `is_subdevice` se agregaron al
DTO en el commit del backend `a746095` (extensión aprobada del contrato
Flutter F1); antes se persistían pero se quitaban de la API. `is_gateway` se
agregó en el commit del backend `e8b7ed7` y es el rol de gateway autoritativo.

## Estados de topología (todos válidos, serializados independientemente)

Los tres hechos `is_gateway`, `is_subdevice`, `parent_device_id` son
independientes; ninguno se infiere de otro.

| Estado | is_gateway | is_subdevice | parent_device_id |
|---|---|---|---|
| Dispositivo directo | false | false | null |
| Gateway | true | false | null |
| Subdispositivo, padre sin resolver (Cloud-only real) | false | true | null |
| Subdispositivo, padre resuelto (post-LAN) | false | true | `"<PhysicalDevice.id estable de GAMMA>"` |

`parent_device_id` siempre referencia el `PhysicalDevice.id` estable de GAMMA,
nunca un provider id / node id / IP. Cloud puede clasificar un dispositivo
como gateway o subdispositivo sin resolver la relación hijo→padre; la relación
puede poblarse después mediante enriquecimiento LAN/topología. Un padre null
es válido y no bloquea el provisioning.

Flutter trata `is_gateway` como la autoridad de partición; la relación
has-child solo se usa para agrupar (`GatewayInfo.childDeviceIds`).

## Enums

- **ProvisioningState**: `DISCOVERED`, `ENRICHED`, `PARTIALLY_CONFIGURED`,
  `CONFIGURED`, `MISSING`, `DISABLED`.
  Inbox pendiente = DISCOVERED / ENRICHED / PARTIALLY_CONFIGURED.
- **CanonicalCapability**: `POWER`, `BRIGHTNESS`, `COLOR`, `COLOR_TEMPERATURE`,
  `SPEED`, `MODE`, `TEMPERATURE_READ`, `HUMIDITY_READ`, `POSITION`,
  `OPEN_CLOSE`, `UNKNOWN`, `UNMAPPED`.
- **Confidence**: `HIGH`, `MEDIUM`, `LOW`, `UNKNOWN`.
- **ProviderHealth**: `status` ∈ `LAN_READY`, `CLOUD_READY`, `CLOUD_DEGRADED`,
  `CLOUD_NOT_CONFIGURED`, `AUTH_ERROR`; booleanos `lan_ready`, `cloud_ready`.
- No hay salud operacional por dispositivo serializada (el enum `DeviceHealth`
  del backend existe pero ninguna ruta lo expone).

## Áreas

El directorio de áreas es `GET /api/v1/areas` → `{"areas": [{id, name,
aliases, parent_id, created_at, updated_at}]}`. Los ids son canónicos
(`area_<hex>`), sin nombre embebido; `name` es la etiqueta legible. El
catálogo legacy `GET /api/v1/catalog` fue retirado y ya no se consume.

## Rutinas (6c — retirement)

`RoutineAction.device_id` es el único id de dispositivo admitido y es un
**objetivo endpoint-canonical**: `"<device_id>:<endpoint_id>"` (p. ej.
`dev_6:relay_1`, ver `composition.py`), restringido a endpoints con
`enabled && exposed_to_resolver`. La forma token legacy (`device`) se
rechaza en validación (422). `location` / `floor`, cuando presentes, deben
ser ids canónicos de área (`area_<hex>`).

El whitelist del backend (`utils/catalog_validation.py`) admite solo los
intents `TURN_ON`, `TURN_OFF`, `SET_VALUE`, `MEDIA_CONTROL`, `GET_STATUS`,
`FETCH_NEWS`, `CAMERA_CONTROL`; el editor no ofrece clima, esperar, anuncio
ni encadenar rutina porque sus intents/scopes no están admitidos.

## Bindings

Estable: `POST /bindings` (requiere `endpoint_id`, `entity_id`, `capability`)
y `DELETE /bindings/{binding_id}`; `binding_id` determinista
(`b_{device_id}_{endpoint_id}_{capability}`), visible vía
`endpoint.binding_id` / `endpoint.binding_entity`.

Faltante: ningún endpoint lista entidades lógicas seleccionables
(`entity_id` es texto libre sin validar). Flutter mantiene el placeholder
"Vincular entidad" y no fabrica un catálogo de entidades.

## Huecos conocidos del contrato (registrados)

1. Sin salud operacional por dispositivo en ninguna ruta (solo a nivel
   provider).
2. El directorio de áreas vive en `/api/v1/areas` (ruta propia, fuera del
   namespace de dispositivos); `GET /catalog` quedó retirado.
3. Sin catálogo de entidades lógicas para bindings (el placeholder queda).
4. Discovery es un POST que muta persistencia (sin dry-run); el fallo mapea a
   404.
5. Sin eventos SSE por dispositivo (solo `/api/v1/events` global).

## Baseline (repo Flutter, HEAD 8865174)

- `flutter test`: 54 passed, 1 failed —
  `devices_skeleton_test.dart` "devices skeleton exposes pending devices,
  spaces and infrastructure" (sliver `gateways-row` debajo del doblez en el
  viewport de test de 600px; pre-existente, corregido durante F1).
- `flutter analyze`: 9 issues info-level (pre-existentes, sin errores).
- Archivos sin trackear del usuario (SPECS/ROADMAP/zips de docs) dejados
  intactos.

## Resultado del gate final de F1 (repo Flutter, HEAD tras el gate final)

- `flutter test`: 129 passed, 0 failed (baseline 54 passed / 1 failed).
- `flutter analyze`: 0 errores, 0 warnings; 9 issues info-level pre-existentes
  sin cambios.
- Archivos de F1 limpios para el formatter; `git diff --check` limpio;
  worktree trackeado limpio.
