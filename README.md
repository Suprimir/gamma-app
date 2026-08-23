# gamma-app

Cliente Flutter para la plataforma de automatización del hogar GAMMA.
Corre en Android y Linux desktop, con una experiencia dedicada para
paneles montados en pared.

## Funcionalidades

- **Dispositivos y áreas** — inventario de dispositivos físicos con
  organización por área, interruptores multi-gang y estado canónico de
  mutaciones compartido entre superficies.
- **Rutinas** — editor visual de rutinas con paleta de acciones.
- **Cámaras** — streams en vivo por WebRTC sub más reproducción HD HLS
  (HEVC) vía media_kit.
- **Asistente de voz** — sesión de voz remota con transcript en vivo (SSE),
  VAD Silero y captura de micrófono en el dispositivo.
- **Shell adaptativo** — un solo código, tres superficies: móvil, desktop y
  panel de pared, manejadas por un sistema de layout adaptativo por clase
  de ventana.

## Requisitos

- Flutter SDK (Dart ^3.12)
- Un backend GAMMA corriendo (por defecto `http://127.0.0.1:8420`,
  se puede sobrescribir con `--dart-define=GAMMA_PI=<url>`)

## Para empezar

```bash
flutter pub get
flutter run --dart-define=GAMMA_PI=http://<backend-host>:8420
```

## Verificación

```bash
flutter analyze   # debe reportar cero errores
flutter test      # la suite completa debe pasar antes de mergear
```

## Estructura del proyecto

```
lib/
├── main.dart        # entry point; conecta ApiClient con GammaApp
├── app/             # shells (mobile/desktop/wall) + navegación
├── adaptive/        # sistema responsivo por clase de ventana
├── data/            # API client, modelos de inventario + repositorios
├── ui/              # colores de tema, widgets compartidos, orbe del asistente
└── features/        # una carpeta por feature de producto
    ├── areas/  cameras/  chat/  dashboard/  devices/
    ├── health/ modules/  routines/  settings/ voice/  wall_home/
```

Mirá [`AGENTS.md`](AGENTS.md) para las convenciones de contribución y
[`docs/deviceplatform_contract.md`](docs/deviceplatform_contract.md) para el
contrato congelado de la API DevicePlatform.
