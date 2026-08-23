# AGENTS.md

Guía para humanos y agentes de código que trabajen en este repositorio.

## Reglas base

- **Conventional Commits** en inglés (`feat:`, `fix:`, `test:`,
  `refactor:`, `docs:`, `chore:`). Con scope del feature cuando aplique
  (`fix(devices): ...`).
- **Verificación antes de dar por terminado:** `flutter analyze` (cero
  errores) y `flutter test` (suite completa en verde). Sin excepciones para
  refactors mecánicos.
- No crear documentos de baseline/evidencia por iteración. El conocimiento
  durable vive acá, en `README.md` o en el código.
- Código, comentarios e identificadores en inglés; documentación explicativa
  (README, guías) en español.

## Notas de arquitectura

- `lib/app/app_shell.dart` elige el shell de superficie (mobile / desktop /
  wall panel) vía `lib/adaptive/`. La composición de páginas cambia con la
  clase de ventana, no con la plataforma del dispositivo.
- Las mutaciones de dispositivos convergen a través del controller compartido
  (`lib/adaptive/adaptive_feature_controller.dart`) alimentado por el
  repositorio HTTP de inventario; las páginas deben renderizar estado
  canónico independiente de la selección.
- El panel de pared es room-first (`features/wall_home/`); mobile/desktop son
  page-first.
- Acoplamientos intencionales conocidos (candidatos a desacoplar a futuro):
  `devices_page` importa `areas_page`; `routine_actions` y
  `routines_editor_page` importan `formatDeviceName`/`formatLocationName`
  desde `devices_page.dart`; `navigation_destinations` importa todas las
  páginas.

## Contrato con el backend

- El contrato de la API está congelado en
  [`docs/deviceplatform_contract.md`](docs/deviceplatform_contract.md).
  La fuente de verdad vive en el backend AssistantGamma
  (`src/api/device_routes.py`, `src/features/devices/models.py`).
- La URL base del backend viene de `--dart-define=GAMMA_PI`
  (default `http://127.0.0.1:8420`).

## Especificidades de plataforma

- Entry point Android: `android/.../MainActivity.kt` expone un MethodChannel
  `gamma_app/external_url` (`openUrl`) para abrir navegadores externos.
- Los archivos de plataforma Linux viven bajo `linux/` (CMake + runner). No
  anidar copias del proyecto dentro de directorios de plataforma.
- Las funciones de voz necesitan los modelos Silero VAD en `assets/`; la
  reproducción de cámaras requiere las libs nativas de `media_kit`
  (`MediaKit.ensureInitialized()` en main).

## Higiene del repo

- Nunca commitear salida de build (`build/`, `.dart_tool/`), estado local de
  runtime (`.atl/`, `.codegraph/`) ni archivos temporales de trabajo.
- Binarios grandes requieren justificación explícita antes de entrar al
  historial de git.
