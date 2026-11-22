# AbogaRed para iOS (Swift / SwiftUI)

Aplicación nativa iOS para **AbogaRed** (`com.abogared.app`) desarrollada en **Swift 5 / SwiftUI + WKWebView + UNUserNotificationCenter + BGTaskScheduler**, lista para compilar tu archivo `.ipa` **100% gratis en la nube sin necesitar una Mac ni cuenta de pago de Apple (USD $99/año)**.

---

## Características Nativas Incluidas
- **WebView nativo de alto rendimiento** conectado a `https://abogared.health-tech.com.mx` con cookies/sesión persistente, gestos de deslizamiento lateral (*atrás/adelante*), *pull-to-refresh* y barra de progreso dorada.
- **Notificaciones nativas estilo WhatsApp (`AbogaRedNotificationManager` + `BackgroundAlertService`)**:
  - Banners en primer y segundo plano, sonido, vibración, agrupación de alertas y navegación directa al expediente o calendario al tocar la notificación.
  - Puente JavaScript `window.AbogaRedIOS` sincronizado con la campana de AbogaRed y botón **Probar**.
  - Actualización en segundo plano (`BGAppRefreshTask` cada ~15 minutos) consultando `/api/mobile/alerts` con token guardado de forma segura en **Keychain**.
- **Google Sign-In / OAuth compatible con iOS** mediante User-Agent limpio de Safari móvil y soporte de deep link `abogared://`.
- **Descarga y compartición nativa** de archivos Word (`.docx`), PDF y comprobantes mediante Hoja de Compartir de iOS (`UIActivityViewController`), además de apertura de boletines judiciales externos en `SFSafariViewController`.

---

## Cómo Generar el `.ipa` Gratis en GitHub (Sin Mac)

1. Crea un **repositorio público** en GitHub llamado `abogared-ios` (los repositorios públicos tienen minutos gratuitos ilimitados en runners **macOS** de GitHub Actions; en repositorios privados tienes cuota mensual gratuita incluida).
2. Sube este proyecto a la rama `main`:
   ```bash
   git remote add origin https://github.com/TU_USUARIO/abogared-ios.git
   git push -u origin main
   ```
3. Entra a la pestaña **Actions** de tu repositorio en GitHub: el workflow **`Compilar AbogaRed iOS (.ipa) Gratis`** (`macos-latest`) arrancará automáticamente, instalará `XcodeGen`, compilará el binario ARM64 en Xcode y empaquetará **`AbogaRed-unsigned.ipa`**.
4. Al terminar (~3-5 minutos), entra a la ejecución y descarga el artefacto **`AbogaRed-iOS-IPA`** (contiene `AbogaRed-unsigned.ipa`). También puedes ejecutarlo manualmente con *Run workflow -> create_release: true* para publicarlo en **Releases**.

---

## Alternativas Gratuitas Adicionales para Compilar o Instalar el `.ipa`

### A) Alternativas gratuitas en la nube para generar el `.ipa`
1. **GitHub Actions (incluido en `.github/workflows/build-ios-ipa.yml`):** Compilación directa en `macos-latest` (gratis e ilimitada en repos públicos).
2. **Codemagic (incluido en `codemagic.yaml`):** Plan gratuito con **500 minutos/mes en Mac mini M2**. Conecta tu repo de GitHub en [codemagic.io](https://codemagic.io) y descarga `AbogaRed-unsigned.ipa`.

### B) Cómo instalar gratis `AbogaRed-unsigned.ipa` en tu iPhone desde Windows (sin pagar $99 USD a Apple)
Un `.ipa` sin firma comercial se instala gratis en tu iPhone usando tu Apple ID gratuito normal mediante cualquiera de estas herramientas en Windows:
1. **Sideloadly (la más fácil desde Windows):**
   - Descarga [Sideloadly](https://sideloadly.io/) en Windows e instala iTunes (versión web Apple, no Microsoft Store).
   - Conecta tu iPhone por cable USB (o Wi-Fi tras la primera vez).
   - Arrastra `AbogaRed-unsigned.ipa`, escribe tu Apple ID normal y pulsa **Start**.
   - En el iPhone ve a **Ajustes > General > Gestión de VPN y dispositivos**, toca tu correo Apple ID y elige **Confiar**.
   *(Con cuenta Apple gratuita el certificado de sideload dura 7 días y Sideloadly/AltStore lo renuevan automáticamente por Wi-Fi).*
2. **AltStore / SideStore:** Permiten instalar y auto-renovar el `.ipa` directamente desde el teléfono o tu PC Windows vía Wi-Fi.
3. **Alternativa sin vencimiento (PWA en Safari iOS):** También puedes abrir `https://abogared.health-tech.com.mx` en **Safari**, pulsar **Compartir -> Añadir a pantalla de inicio** y activar alertas web en iOS 16.4+.

### C) Firma oficial para TestFlight / App Store (Opcional a futuro)
Si más adelante adquieres una cuenta **Apple Developer Program**, solo añade en GitHub (`Settings > Secrets and variables > Actions`):
- `APPLE_CERTIFICATE_BASE64` (archivo `.p12` en Base64)
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64` (`.mobileprovision` en Base64)
- `APPLE_TEAM_ID`

El mismo workflow detectará esos 4 secrets y generará automáticamente **`AbogaRed-signed.ipa`**.
