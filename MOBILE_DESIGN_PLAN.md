# Plan de Diseño y Adaptación Mobile (Android) — Inazuma Arcade Mobile

## 1. Diagnóstico y Corrección del Bug de Menú No Clickeable
1. **Emulación Táctil / Mouse en Godot (`project.godot`):**
   - **Causa raíz:** La combinación `emulate_touch_from_mouse=true` junto con `emulate_mouse_from_touch=false` convertía entradas táctiles/mouse en eventos `InputEventScreenTouch` puros sin sintetizar clics de mouse para los nodos GUI (`Button`, `TabContainer`), impidiendo que cualquier botón de menú recibiera clics.
   - **Solución:** Se configuró `pointing/emulate_touch_from_mouse=false` y `pointing/emulate_mouse_from_touch=true` en `project.godot`, garantizando que todo toque en pantalla dispare nativamente los botones de la interfaz en Android y escritorio, mientras `TouchControls.gd` filtra eventos de mouse sintetizados cuando hay pantalla táctil real (`DisplayServer.is_touchscreen_available()`).
2. **Bloqueo Automático del Overlay Táctil en Menús (`HUD.gd` + `TouchControls.gd`):**
   - `HUD._sync_touch_menu_block()` desactiva la captura de eventos (`MOUSE_FILTER_IGNORE`) y oculta `TouchControls` automáticamente siempre que `MatchSetup` (Menú Principal), `PauseMenu` o `MatchResultOverlay` estén visibles.

## 2. Identidad Visual: Beige Cálido, Rojo Carmesí, Blanco y Dorado Real
- **Paleta de Colores Unificada (`HUD.gd` & `TouchControls.gd`):**
  - **Fondos Crema y Beige:** `THEME_BG_CREAM` (`#F5EFE2`), `THEME_BG_BEIGE_SUB` (`#EAE0CC`) y `THEME_BG_CARD` (`#FDFBF6`).
  - **Acentos Rojo Carmesí Imperial:** `THEME_RED_PRIMARY` (`#BA1F2B`), `THEME_RED_DARK` (`#7A131C`) y `THEME_RED_BRIGHT` (`#D92B38`).
  - **Detalles en Dorado Real y Blanco Puro:** `THEME_GOLD` (`#D4A438`), `THEME_GOLD_BRIGHT` (`#F5C74D`) y `THEME_WHITE` (`#FFFFFF`).
  - **Césped de Alto Contraste:** Se conserva el verde esmeralda de la cancha para máxima legibilidad de jugadores, balón e indicadores tácticos.

## 3. Menú Principal Mobile-First: Grilla Táctil 3x2 de Equipos
- Se eliminaron los `OptionButton` desplegables de escritorio y las ayudas de teclado PC (`WASD / Flechas`).
- En su lugar, tanto la pestaña **Modo Torneo (6 Rondas)** como **Partido Rápido** presentan una **Grilla Táctil 3x2 de Tarjetas de Equipo (`_create_touch_team_grid_selector`)**:
  - Selección directa con **1 solo toque** sobre cualquiera de los 6 equipos.
  - Cada tarjeta muestra retrato de la estrella del equipo, divisa cromática, nivel y nombre, resaltando el equipo activo con fondo Rojo Carmesí y borde Dorado Real.
  - Vista previa superior con retrato grande y plantilla titular del equipo seleccionado.

## 4. Controles Táctiles en Arco / Diamante (Estilo eFootball / FIFA Mobile)
- **Mano Izquierda (Zona Dinámica `x <= 42%`, `y >= 240`):**
  - Joystick virtual flotante en tonos Beige/Dorado/Rojo con seguimiento multitáctil independiente por `pointer_id`.
  - **Auto-Sprint Inteligente:** Al inclinar el joystick virtual al **78% o más** (`virtual_move_vector.length() >= 0.78`), el jugador activa el sprint automáticamente con indicador visual `⚡ SPRINT` en el aro del joystick.
- **Mano Derecha (Arco / Diamante Ergonómico):**
  - **Botón Principal `TIRO / CARGAR` (Esquina inferior derecha):** Botón circular grande rojo carmesí con soporte real de **mantener presionado para cargar potencia** (`Input.action_press("action_shot")`) y arco dorado progresivo de carga en vivo.
  - **Satélites en Arco:** Botones circulares táctiles para **`PASE`** (oeste), **`BARRIDA`** (suroeste, barrida defensiva dedicada), **`CAMBIAR`** (noroeste) y botón especial **`★ HISSATSU`** en Dorado Real (norte).
  - **Pausa Táctil (`❚❚ PAUSA`):** Ubicada en la esquina superior derecha dentro del margen seguro (`Safe Area`).

## 5. Dock Inferior Central Compacto
- Las tarjetas `[BottomHomeCard]` (`x=296, y=628`), `[MiniRadar]` (`x=542, y=628`) y `[BottomAwayCard]` (`x=748, y=628`) forman un dock compacto en la base central de la pantalla.
- Esto libera por completo las esquinas inferiores izquierda y derecha para los pulgares y preserva el corredor visual superior izquierdo (`[0, 460] x [0, 360]`) 100% despejado.
