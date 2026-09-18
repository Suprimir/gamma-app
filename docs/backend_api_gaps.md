# Endpoints pendientes del core (post-conexión del cliente)

El cliente Flutter quedó conectado a la API canónica en todo lo que el
contrato actual permite. Este documento lista, priorizado, lo que falta
programar en el core (`0.0.0.0:8420`) para cerrar el resto, con evidencia
exacta y la forma sugerida de cada endpoint.

**Estado (2026-09-12):** los puntos 1, 2, 3 y 4 ya fueron implementados en el
core y verificados en vivo (fix del response de acciones, las 7 acciones
canónicas, la población de `observed_state` con observaciones por
capability y los 13 endpoints de reproducción de Spotify). Sigue vigente el
resto: STT puro, rutinas (`enabled` + ejecución), catálogo de entidades,
ciclo de vida de devices y clima. Del lado app quedan pendientes el picker de
color hex (no existe UI) y `set_temperature` (no existe acción en el core).

## Camino rápido (qué programar primero)

1. **Fix del resultado de acciones** — `POST /api/v1/devices/{device_id}/endpoints/{endpoint_id}/actions` devuelve `null` en éxito.
2. **Acciones de endpoint más allá de `set_power`** — brightness, position, color, color_temperature, speed, mode.
3. **Poblar `observed_state`** en los DTOs de devices/endpoints.
4. ~~Spotify playback~~ ✅ implementado y verificado (13 endpoints). El resto
   por feature: STT puro, rutinas (`enabled` + ejecución), catálogo de
   entidades, ciclo de vida de dispositivos, clima.

---

## 1. 🔴 Bug crítico: la ruta de acciones nunca devuelve su resultado

- Ruta: `POST /api/v1/devices/{device_id}/endpoints/{endpoint_id}/actions`.
- Evidencia: `src/api/device_provisioning_routes.py:620` — el
  `return result.to_public_dict()` está indentado dentro del bloque
  `if result.error_code is EndpointActionErrorCode.UNKNOWN_ENDPOINT`
  (después de un `return`), así que es inalcanzable. En éxito la ruta
  retorna `None` → HTTP 200 con body `null`.
- Verificado en vivo:

  ```bash
  curl -X POST http://127.0.0.1:8420/api/v1/devices/dev_6/endpoints/main/actions \
       -H 'Content-Type: application/json' \
       -d '{"action":"set_power","value":true}'
  # → null (HTTP 200)
  ```

- Fix: des-indentar ese `return` al cuerpo de la función, después de los dos
  `if` de error. El shape ya está implementado en
  `EndpointExecutionResult.to_public_dict` (`src/core/devices/endpoint_actions.py:169-186`).
- Impacto en el cliente: la app ya tolera ambos shapes. Hoy, con `null`,
  muestra "Orden enviada — sin confirmación del dispositivo". Con el fix
  podrá mostrar `SUCCESS` / `NO_CHANGE` / `EXECUTION_DISABLED` / etc. y el
  `observed_state` post-ejecución.

## 2. Acciones de endpoint — ✅ implementado y verificado (2026-09-12)

Implementadas las 7 acciones vía `ACTION_SPECS`
(`src/core/devices/endpoint_actions.py`), con routing por capability
(acción sobre capability ausente → `UNSUPPORTED` tipado, sin escritura al
provider) y validación estricta (`422 invalid_value`, sin coerción). La
tabla queda como registro de lo pedido:

| Acción sugerida | Capability | Evidencia en vivo | UI del cliente que la espera |
|---|---|---|---|
| `set_brightness` | `BRIGHTNESS` (range 0–100) | `dev_3`, `dev_6` | Slider "Brillo" (desktop/wall detalle) — hoy local |
| `set_position` | `POSITION` | `dev_1` (persiana) | Control de posición en detalle |
| `set_color` | `COLOR` | cuando el provider la declare | Selector de color |
| `set_color_temperature` | `COLOR_TEMPERATURE` | cuando aplique | Selector de temperatura de color |
| `set_speed` | `SPEED` | ventiladores | Control de velocidad (desktop) |
| `set_mode` | `MODE` (`enum_values`) | cuando aplique | Selector de modo (climate) |

Mantener la misma disciplina que `set_power`: parser estricto sin coerción,
`error_code` estables (`unknown_action`, `invalid_value`), y `observed_state`
en el resultado.

## 3. Estado observado (`observed_state`) — ✅ implementado y verificado (2026-09-12)

- Poblado en el DTO por endpoint (`power`, `quality`, `observed_at`) y con
  **observaciones por capability** (`observed_state.capabilities`:
  `BRIGHTNESS`, `COLOR`, `COLOR_TEMPERATURE`, `SPEED`, `MODE`, `POSITION`
  con `value`, `quality`, `observed_at`).
- Store compartido entre HTTP, lane de voz y DTO (commit `0cdd5d7`);
  `refresh_observations` en boot/refresh del dispositivo.
- Las respuestas de las acciones incluyen el `observed_state` actual.
- El DTO suma `bindings` por capability (aditivo).
- **Nota de identidad**: no existe señal canónica de reachability/last_seen.
  El legacy `GET /api/v1/status` (402 entradas, ids `luz_1@comedor_1`) se
  retiró justamente porque **no mapeaba** a los ids canónicos `dev_*`; esa
  señal sigue sin existir, y si la UI debe mostrar "en línea"/"última
  conexión" por dispositivo, tiene que vivir en el contrato canónico
  (p. ej. dentro de `observed_state`).

## 4. Spotify: reproducción — ✅ implementada y verificada (2026-09-12)

El core expone los 13 endpoints de reproducción (OpenAPI + curl en vivo):

- `GET /api/v1/spotify/player` → `{has_playback, is_playing, track, device,
  shuffle, repeat, volume_percent}`.
- `GET /api/v1/spotify/devices` → `{devices[], default_device_name,
  default_device_id}`.
- `POST /api/v1/spotify/play` body `{uri? | context_uri? | query?,
  device_id?, position_ms?}` (exactamente un selector; `query` resuelve al
  primer match: canción → playlist → álbum).
- `POST /api/v1/spotify/pause|resume|next|previous` body opcional
  `{device_id?}`; `PUT /volume` `{volume_percent}`; `PUT /seek`
  `{position_ms}`; `PUT /transfer` `{device_id}`; `PUT /shuffle` `{state}`;
  `PUT /repeat` `{state: off|track|context}`; `POST /queue` `{uri}`.
- Errores: 401 auth vencida, 403 Premium requerido, 409 sin dispositivo
  activo / orden rechazada, 422 inválido, 503 módulo desactivado o servicio
  sin autorizar.

**Pendiente del lado operador (no del cliente):** la cuenta todavía no está
autorizada; el server responde `503` con
"Spotify no está autorizado. Conecta tu cuenta en Ajustes." hasta conectar
la cuenta, y reproducir requiere Premium (403). El cliente muestra la CTA
de conexión y los estados "Sin reproducción" / "Sin dispositivo activo" en
vez de inventar estado.

**Lado app (2026-09-12, actualizado 2026-09-17):** `ApiClient` expone los
13 métodos; `SpotifyPlayerController` (`lib/features/spotify/`) es un único
controlador compartido por app (`SpotifyScope` en `main.dart`: tarjeta del
wall, chip de reposo y dashboard desktop comparten poll y suscripción SSE)
con comandos device-scoped y eventos SSE en tiempo real
`spotify_state_changed`/`spotify_queue_changed`. El player se publica apenas
llega (los listados de devices/cola corren detrás con cadencia propia:
15s/20s), el poll de respaldo es de 3s en primer plano (30s en segundo) y solo
lo salta un cambio de reproducción aplicado por SSE (ni la cola ni un snapshot
de Soloist inactivo cuentan como frescura, para no ocultar lo que suena en el
teléfono). Las lecturas concurrentes se unifican en una sola petición
(single-flight con una repetición acotada si llega un pedido explícito a
mitad), un error HTTP rezagado no pisa un evento SSE más nuevo, `needsAuth` en
401/503 y un 429/5xx transitorio conserva la última canción en vez de vaciar
la tarjeta. La tarjeta Spotify del desktop reproduce playlists con
`playContext`, muestra transporte/volumen/selector de dispositivo/progreso
interpolado/cola; el card de música del wall usa los mismos estados con
targets táctiles grandes.

## 5. Voz: STT puro para dictado

El dictado de nombres de dispositivos/áreas usa `POST /voice/audio-turn`,
que **ejecuta el turno completo**: lo dictado puede disparar acciones.
Falta un endpoint de transcripción sin ejecución, p. ej.
`POST /api/v1/voice/transcribe` → `{ "text": str, "confidence"?: float }`.

## 6. Rutinas: `enabled` y ejecución manual

- El toggle de la app envía `enabled` dentro de `PUT /routines/{id}`, pero
  `RoutineWriteRequest` / `RoutineDefinition` no tienen ese campo y el
  backend lo descarta → el switch revierte al recargar. Evidencia:
  `src/api/routes.py:266-300` (create/update/delete de rutinas).
- Falta ejecución manual: `POST /api/v1/routines/{routine_id}/execute`
  (o equivalente). Hoy no hay forma de correr una rutina desde la UI.
- Opcional: `last_run` en la definición para futuras vistas.

## 7. Bindings: catálogo de entidades

La UI ya pide el `entity_id` como texto libre y ahora llama al
`POST /bindings` real. Falta `GET /api/v1/entities` (o similar) para
ofrecer un catálogo seleccionable en vez de texto libre.

## 8. Ciclo de vida canónico de dispositivos

- El alta manual es solo local (`dev_manual_*`) y no existe `POST /devices`;
  el intake es discovery.
- No existe `DELETE /devices/{id}`; la UI solo quita de la vista local.
- Si el producto requiere gestión completa: definir rutas (o documentar que
  `PUT /enabled` es el mecanismo de baja).

## 9. Clima (opcional)

La app usa Open-Meteo externo con coordenadas hardcodeadas (Culiacán). Si se
quiere server-side: endpoint de clima por ubicación configurable.

## 10. Menores / notas

- Con `writes_enabled=false` (modo demo), el resultado tipado esperado es
  `EXECUTION_DISABLED`; la UI lo reporta honestamente una vez aplicado el
  fix del punto 1.
- `POST /devices/{provider_id}/scan` existe; la app usa discovery global.
- `GET /api/v1/shadow/*` es diagnóstico; sin UI.
- Legacy `GET /api/v1/catalog` y
  `PUT /devices/{location}/{device_id}/power`: candidatos a retiro.

---

## Lo que quedó conectado del lado app (contexto)

- **Power canónico** (`set_power`) en wall/mobile/desktop, con estados
  honestos ("Sin datos"), outcomes tipados y manejo de `null`.
- **Controles de detalle (desktop + wall) comandando el backend**:
  brillo, velocidad del ventilador (niveles ↔ percent), modo (opciones del
  descriptor), posición (persianas) y temperatura de color; los valores
  mostrados salen de `observed_state` confirmado y el guardado avisa
  honestamente cuando las escrituras están deshabilitadas.
- **`observed_state`** parseado y listo para mostrar on/off confirmado.
- **Dashboards**: sin fallback a mock, cámaras por `/cameras/status`,
  playlists con metadata real, tarjeta de estado sin inventar.
- **Spotify playback**: controller compartido por app (desktop + wall + chip
  de reposo, `SpotifyScope`), **SSE en tiempo real** con poll de respaldo de
  3s en primer plano (30s en segundo, y se salta si el SSE acaba de llegar),
  progreso interpolado en cliente (ancla `position` también para la rama Web
  API), cola "A continuación", transporte, volumen, selector de dispositivo
  con lectura forzada al abrir y lista viva, y tap de playlist →
  `playContext` (context_uri real). Fuente de estado: Soloist WS
  (`source: "soloist"`) con fallback al Web API.
- **Turns** con `session_id` desde chips mobile, acciones desktop y wall.
- **Rutinas relacionadas** reales (GET /routines filtrado), **TTS preview**,
  **card de Sistema** (health), **bindings reales**, **identify honesto**,
  **rename sin falso éxito** y **SSE de voz con Last-Event-ID**.

## Estado de verificación del cliente

- `flutter analyze`: 0 errores (9 infos preexistentes del baseline).
- `flutter test`: 527 pasan / 118 fallan — los 118 son fallos
  **preexistentes** del rediseño (expectativas de tests viejas), sin
  regresiones nuevas; los 19 tests nuevos de Spotify playback (API client,
  controller y tarjetas desktop/wall) pasan, y 5 fallos preexistentes
  quedaron arreglados durante este trabajo.

## Checklist de verificación (para el core)

- [x] `POST .../actions` con `set_power` devuelve el DTO tipado
      (`outcome`, `observed_state`).
- [x] `EXECUTION_DISABLED` se devuelve tipado con `writes_enabled=false`.
- [x] `observed_state` poblado tras una ejecución confirmada.
- [x] Las acciones nuevas rechazan valores inválidos sin coerción (mismos
      `error_code`).
- [ ] `PUT /routines/{id}` persiste `enabled` (o endpoint dedicado).
- [ ] Existe ejecución manual de rutinas.
