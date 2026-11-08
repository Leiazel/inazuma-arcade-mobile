# ⚽ Mini Football Champions / Inazuma Arcade Mobile

Versión mobile arcade de fútbol con controles táctiles dinámicos, supertécnicas y estilo pixel-art chibi inspirado en Inazuma Eleven (Nintendo DS). Desarrollado en **Godot Engine 4.3 Stable**.

---

## 📲 Descargar APK para tu Celular (Android)

Cada vez que se sube un cambio o nueva versión a este repositorio, GitHub Actions compila y actualiza automáticamente el APK listo para instalar.

### ⬇️ Opción 1: Descarga Directa desde el Celular
Hacé clic o tocá el siguiente enlace desde tu teléfono móvil para descargar la última versión:

[![Descargar APK](https://img.shields.io/badge/Descargar%20APK-Última%20Versión-brightgreen?style=for-the-badge&logo=android)](https://github.com/Leiazel/mf-champions-mobile/releases/latest/download/InazumaArcadeMobile.apk)

🔗 **Enlace directo permanente**:  
👉 **[https://github.com/Leiazel/mf-champions-mobile/releases/latest/download/InazumaArcadeMobile.apk](https://github.com/Leiazel/mf-champions-mobile/releases/latest/download/InazumaArcadeMobile.apk)**

---

### 📷 Opción 2: Escaneá el Código QR con tu Teléfono
Si estás viendo esto desde la computadora, apuntá la cámara de tu celular a este código QR para abrir el enlace de descarga directa:

<p align="center">
  <img src="https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=https%3A%2F%2Fgithub.com%2FLeiazel%2Fmf-champions-mobile%2Freleases%2Flatest%2Fdownload%2FInazumaArcadeMobile.apk" width="220" height="220" alt="Código QR para Descargar APK" />
</p>

---

## 🛠 Cómo Instalar en Android (Paso a Paso)

1. **Descargá el archivo**: Tocá el enlace de descarga arriba desde el navegador de tu celular (Chrome, Samsung Internet, Firefox, etc.).
2. **Abrí el archivo**: Una vez finalizada la descarga, tocá la notificación de descarga completa o buscalo en la carpeta **Descargas** (el archivo se llama `InazumaArcadeMobile.apk`).
3. **Habilitar instalación**: Si el sistema te muestra el aviso *"Por seguridad, tu teléfono no tiene permitido instalar apps desconocidas de esta fuente"*:
   - Tocá **Ajustes** o **Configuración**.
   - Activá el interruptor **Permitir desde esta fuente**.
   - Volvé atrás y tocá **Instalar**.
4. **¡A jugar!**: El juego aparecerá en tu menú de aplicaciones con su ícono y pantalla horizontal adaptativa.
5. **Actualizaciones**: Cuando haya una nueva versión, simplemente volvé a descargar e instalar el APK; se actualizará conservando toda la configuración gracias a que la firma digital es consistente entre versiones.

---

## ⚙️ Compilación Manual / Local

Si querés compilar el proyecto en tu máquina con Linux:

```bash
# 1. Ejecutar las pruebas automatizadas
./run_tests.sh

# 2. Exportar el APK localmente
./export_apk.sh
```

El APK resultante se generará en `build/android/InazumaArcadeMobile.apk`.
