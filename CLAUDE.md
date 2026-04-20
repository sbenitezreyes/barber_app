# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Descripción del Proyecto

**YaCut** — Plataforma de barbería a demanda construida en Flutter, con dos versiones separadas de la app: cliente y barbero. Firebase es el backend (Auth, Firestore, Cloud Functions, FCM, Storage).

## Comandos Esenciales

### Ejecutar la app
```bash
# App cliente
flutter run --flavor client -t lib/main_client.dart

# App barbero
flutter run --flavor barber -t lib/main_barber.dart
```

### Tests
```bash
# Todos los tests
flutter test

# Un test específico
flutter test test/utils/distance_test.dart
```

### Otros comandos útiles
```bash
flutter pub get          # instalar dependencias
flutter analyze          # linting estático

# APK de release (con obfuscation y debug info separada)
flutter build apk --flavor client -t lib/main_client.dart \
  --release --obfuscate --split-debug-info=build/symbols/client
flutter build apk --flavor barber -t lib/main_barber.dart \
  --release --obfuscate --split-debug-info=build/symbols/barber

# Medir tamaño del APK (genera JSON para analizar en DevTools)
flutter build apk --flavor client -t lib/main_client.dart --analyze-size
flutter build apk --flavor barber -t lib/main_barber.dart --analyze-size
# Abrir el reporte: dart devtools → "Open app size tool" → subir el JSON de build/
```

### Cloud Functions (Node.js)
```bash
cd functions
npm install
firebase deploy --only functions
```

## Arquitectura

### Estructura de Doble Versión

La app tiene dos puntos de entrada que comparten una base de código común:
- `lib/main_client.dart` → `ClientApp` → flujo del usuario cliente
- `lib/main_barber.dart` → `BarberApp` → flujo del usuario barbero
- `lib/main.dart` apunta por defecto al entry point del cliente

Los flavors Android están configurados en `android/app/build.gradle.kts`:
- `client` → `com.example.barberapp`
- `barber` → `com.example.barberapp.barber`

La detección de rol en toda la app se hace mediante `AppConfig` (un `InheritedWidget` configurado en la raíz de cada app). Se comprueba con `AppConfig.of(context).isClient` o `.isBarber`.

### Organización de Módulos

```
lib/app/
├── barber/         # Pantallas, tabs y servicios exclusivos del barbero
├── client/         # Pantallas y tabs exclusivos del cliente
└── shared/         # Auth, splash screen, AppConfig, términos, tema
```

### Gestión de Estado

No hay framework centralizado. El estado se maneja con:
- **`ValueNotifier`** — bus de eventos global en `FcmService` (refresco del badge de notificaciones, cambio de tab)
- **Streams `.snapshots()` de Firestore** — datos en tiempo real en widgets/servicios individuales
- **`SharedPreferences`** — flags locales (`hasNewNotification`, `welcomeDialogDismissed`)
- **`FirebaseAuth.instance.currentUser`** — accedido directamente donde se necesita

### Autenticación y Enrutamiento

`SplashScreen` gestiona todo el enrutamiento de autenticación:
1. Usuario real autenticado → pantalla principal
2. Cliente sin auth → inicio de sesión anónimo (modo invitado), con fallback a `AuthScreen`
3. Barbero sin auth → `AuthScreen` (debe autenticarse)

### Servicios Clave

- **`FcmService`** (`lib/app/barber/services/fcm_service.dart`) — Singleton. Gestiona el ciclo de vida de FCM, canales de notificación, persistencia del token en Firestore y broadcasts mediante `ValueNotifier`.
- **`BarberGpsService`** (`lib/app/barber/services/gps_service.dart`) — Publica la ubicación GPS del barbero cada 5 segundos, tanto en el documento del perfil de usuario (marcador en el mapa) como en el documento de la cita activa (tracking del cliente). Solo está activo cuando la cita está confirmada e inmediata.

### Sistema de Diseño "La Navaja"

Paleta oscura de lujo definida en `lib/app/shared/theme/app_theme.dart`. Usar siempre las constantes del sistema en lugar de colores o estilos hardcodeados:

- **`AppColors`** — paleta completa (obsidiana, oro brass `#C9A84C`, crema cálida)
- **`AppTextStyles`** — tipografía con métodos factory (`display`, `ui`) y aliases (`headline`, `title`, `body`, `caption`, etc.)
  - Fuente de marca/display: **Playfair Display** (serif)
  - Fuente de UI: **Figtree** (grotesque)
- **`AppDecorations`** — decoraciones reutilizables (`card`, `surface`, `pill`, `splashClient`, `splashBarber`)
- **`AppButtonStyles`** — estilos de botón (`primary`, `secondary`, `ghost`)

### Backend Firebase

Cloud Functions (`functions/index.js`, Node.js v2):
- `onNewAppointment` — notifica al barbero cuando el cliente reserva una cita
- `onAppointmentStatusChanged` — notifica a la parte correspondiente según el cambio de estado; limpia las coordenadas GPS cuando la cita sale del estado "confirmada"
- `cleanupRejectedAppointments` — cron diario que elimina citas rechazadas antiguas

Las reglas de seguridad de Firestore (`firestore.rules`) garantizan que los clientes solo puedan actualizar los campos de valoración y los campos de cancelación (`cancelledBy`/`status`); los barberos pueden actualizar las coordenadas GPS y el estado de la cita.

### Flujo de Estado de Citas

```
pendiente → confirmada → completada
pendiente o confirmada → cancelada  (cancelledBy: "client" | "barber")
```

### Tests

54 tests unitarios en `test/` que cubren: cálculos de distancia/Haversine, formateo de tiempo, lógica de destinatario de notificaciones y transiciones de estado de citas. Firebase y Google Maps no están testeados (sin mocks ni tests de integración).
