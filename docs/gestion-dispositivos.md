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
- Hoy no hay toggles por canal: el toggle rápido de la tarjeta comanda el
  primer canal y las escrituras están bloqueadas por el gate global.
- Plan: switches por canal en las pantallas de detalle (estado + acción), con
  aviso honesto "Escritura deshabilitada" mientras el gate esté cerrado.
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

## 4. Fases sugeridas

1. ✅ Auto-configuración de vínculos canónicos (backend `dd1a93f`).
2. Switches por canal en detalle (sin abrir el gate; mensaje honesto). Bajo riesgo.
3. Ventana de prueba de control real por canal (gate ON temporal).
4. QoL: nombres de canal en tarjetas + feedback de guardado en mobile.
