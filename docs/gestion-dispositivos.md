# Gestión de dispositivos — estado actual y plan

Contexto: instalación real en la casa (Raspberry Pi + provider Tuya), escrituras
físicas **bloqueadas por diseño** (`GAMMA_PHYSICAL_EXECUTION_ENABLED=false`).

## 1. Qué hay hoy (funcionando)

**Descubrimiento y estado**
- Escaneo automático LAN + Cloud (ciclo cada 5 min) y persistencia en estado
  pendiente para configurar.
- 13 dispositivos en el hogar: 1 gateway Zigbee ("Hub") + 9 hijos Zigbee + 2
  directos + 1 gateway legacy offline.
- Reporte de estado por canal: barrido de **solo lectura** al abrir la lista de
  dispositivos y en pull-to-refresh (mobile y panel táctil).

**Organización**
- Nombres editables de **dispositivo** y de **canal** en mobile, panel y desktop.
- Habitación física por dispositivo; habitación controlada + rol por canal
  ("Qué controla").
- Tarjetas: agregado por canal ("2 de 3 encendidos" / pill "2/3"); detalle:
  estado por canal (Encendido / Apagado / Sin datos).
- Offline: la lista principal muestra solo activos; los inactivos viven en
  "Desconectados" (mobile) o en el botón "Sin acceso" (panel).
- Gateways: sección de infraestructura; sus hijos aparecen vinculados.
- Dispositivos sin credenciales muestran el badge "Sin credenciales".

**Configuración**
- Al asignar habitación/rol, el sistema crea **automáticamente** los vínculos
  internos (bindings canónicos) y el dispositivo pasa a **Configurado**.
  No hace falta "probar conexión" ni vincular entidades a mano.
- "Probar conexión / Identificar" es un ping opcional, nunca un requisito.

## 2. Flujo recomendado por dispositivo

1. (Opcional) Renombrar el dispositivo y cada canal.
2. Asignar habitación (al dispositivo o a cada canal).
3. Asignar rol por canal (Luz / Interruptor / Persiana / …).
4. → Estado "Configurado".

## 3. Pendientes y decisiones

### A. Prender/apagar por canal (control real) — DECISIÓN PENDIENTE
- ✅ Switches por canal disponibles en los detalles (mobile, panel y desktop):
  cada canal tiene su switch, ejecuta su acción canónica y muestra el resultado
  honesto. Con el gate cerrado responde "Escritura deshabilitada en el modo
  actual" (sin inventar estado).
- Para una prueba real: habilitar el gate de forma **explícita y temporal**
  (idealmente con alguien presente). Sugerido: "Sala Comedor" (3 relays) en una
  ventana corta.

### B. Nombres — mejora pendiente
- La edición ya existe. Mejora: mostrar el nombre del canal en las tarjetas de
  lista (hoy muestran "Canal N" o el rol).

### C. Entidades vinculadas (avanzado)
- Los vínculos son automáticos. La UI manual "Vincular entidad" queda solo para
  integraciones avanzadas con el catálogo de entidades.

### D. Dispositivo sin credenciales (192.168.1.9)
- No pertenece a la cuenta Tuya del hogar; sin local key → "Sin datos" + badge
  "Sin credenciales". Identificar físicamente y decidir: conseguir su key,
  vincularlo a la cuenta, o marcarlo/ignorarlo.

### E. QoL
- Mobile: falta confirmación visual al guardar nombre/área/rol (guarda en
  silencio).
- Desktop: "Guardar cambios" se ve deshabilitado si no hay cambios de
  capacidades; los campos de configuración se persisten solos (aclarar la UX).

## 4. Propuesta de diseño (UX)

Basada en investigación de patrones reales (Nielsen Norman Group, patrón
"desagrupar" de HomeKit, dashboards de Home Assistant) y en las restricciones
del sistema: estados honestos, gate de escrituras, panel táctil.

### Principios

1. **Estado primero**: al abrir, todo estado visible con color + ícono + texto
   (nunca solo color).
2. **Un tap = acción** para lo cotidiano; el detalle es para lo complejo.
3. **El canal es la unidad de control; el dispositivo es la unidad de
   identidad.** (Un 3-gang se comanda por canales, pero hoy pesa como "un
   dispositivo" en la UI.)
4. **Feedback inmediato y honesto**: pendiente → confirmado / deshabilitado /
   sin datos (ya implementado; se mantiene).
5. **Objetivos táctiles grandes**: ≥48dp en mobile, ≥64dp en el panel (NN/g
   recomienda ≥1cm×1cm físicos, más en pantallas grandes).
6. **Progressive disclosure**: control arriba, configuración colapsada.

### Patrón A — Tiles de canal ("Controles") ⭐ la mejora clave

Los canales con encendido se muestran como **tiles individuales**, además de
(no en lugar de) la ficha del dispositivo:

- Nombre del canal (o "Canal N"), ícono por rol, estado (color + texto).
- **Tap = prender/apagar ese canal**; long-press = acciones (detalle,
  renombrar, identificar).
- Dónde: sección "Controles" dentro de cada habitación (mobile), vista "Todos
  los controles", y sección principal del panel táctil.
- Referencia: HomeKit permite "desagrupar" multi-gang en tiles separados; es
  el patrón más rápido para el control diario.

### Patrón B — Tarjetas de dispositivo (lista)

- Resumen de canales: hasta 3 chips con estado (color + texto); más de 3 →
  "N/M encendidos".
- Tap → detalle; los toggles rápidos de tarjeta se mantienen.
- Nombres de canal visibles en las tarjetas (hoy muestran "Canal N").

### Patrón C — Detalle en 3 bloques

1. **Control** (primero): una fila por canal — nombre grande, estado, switch.
2. **Estado**: conexión, credenciales, gateway, "Probar conexión".
3. **Configuración** (colapsable): renombrar (dispositivo/canal), habitación,
   rol, vincular entidad.

### Patrón D — Panel táctil

- Tiles grandes (≥64dp), ícono + nombre + estado; tap = toggle, long-press =
  detalle.
- Se mantiene la confirmación visual ("splash") existente.
- QoL kiosco: atenuación nocturna y despertar al tacto (si el hardware lo
  permite).
- La lista de dispositivos sigue como está (activos + "Sin acceso").

### Patrón E — Acciones masivas

- "Apagar todo" por habitación y por casa (sobre canales con encendido).
- Con el gate cerrado responde honestamente; queda listo para la prueba real.
- Referencia: NN/g #5 — reducir repetición con atajos.

### Patrón F — Pestaña Dispositivos: Controles primero

- La vista principal de "Dispositivos" son los **Controles** (tiles por canal).
- La lista de dispositivos (plana, sin separación por área, seleccionable,
  con estado de configuración por fila) y la lista de **Sin acceso** viven
  detrás de **botones pequeños de ícono** en el encabezado.
- En la lista de dispositivos: chips de filtro (Todos / Sin configurar / Sin
  ubicación / Gateways), búsqueda por dispositivo/canal, **Buscar
  dispositivos** (discovery) y "Agregar dispositivo".
- Implementado: app `6820255`.

## 5. QoL propuesto (priorizado)

| # | Mejora | Nota |
|---|--------|------|
| 1 | Tiles de canal (Patrón A) | ✅ `6c461e9` — control rápido real, estilo HomeKit/Tuya |
| 2 | Nombres de canal en tarjetas | ✅ `6c461e9` — identificar canales sin entrar al detalle |
| 3 | Iconos por rol (luz/persiana/enchufe/ventilador) | ✅ `41d7fde` — reconocimiento visual rápido |
| 4 | Feedback de guardado en mobile | ✅ `41d7fde` — confirmaciones visibles |
| 5 | Estado "enviando…" en toggles | Feedback inmediato (NN/g #6) |
| 6 | Favoritos (fijar canales arriba) | Acceso diario |
| 7 | Búsqueda de canales | Con 13+ canales se agradece |
| 8 | "Apagar todo" (habitación/casa) | Reducir repetición (NN/g #5) |
| 9 | Panel: atenuación nocturna + wake on touch | Kiosco siempre encendido |
| 10 | Accesibilidad: Semantics/contraste/targets, nunca solo color | NN/g #3 |
| 11 | Orden estable de canales + renombrado en lote | Consistencia |

## 6. Fases sugeridas (actualizado)

1. ✅ Auto-configuración de vínculos canónicos (backend `dd1a93f`).
2. ✅ Switches por canal en los detalles (app `bdb4ba9`).
3. ✅ Tiles de canal ("Controles") en mobile + panel, y nombres de canal en
   tarjetas (app `6c461e9`).
4. ✅ Reorganización del detalle (Patrón C) + iconos por rol + feedback mobile
   (app `41d7fde`).
5. **Ventana de prueba de control real por canal** (gate ON temporal) — decisión.
6. Acciones masivas + favoritos + QoL de panel (Patrones D/E + QoL 5-9).

### Referencias

- NN/g — *Smart-Device Apps: 7 Best Practices* (2025).
- NN/g — *Touch Targets on Touchscreens*.
- r/HomeKit — desagrupar multi-gang en tiles separados.
- Comunidad Home Assistant — dashboards simples, tarjetas por entidad.
