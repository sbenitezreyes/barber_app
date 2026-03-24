

## Descripción del Proyecto

**YaCut** — Plataforma de barbería a demanda construida en Flutter, con dos versiones separadas de la app: cliente y barbero. Firebase es el backend (Auth, Firestore, Cloud Functions, FCM, Storage).



### Estructura de Doble Versión

La app tiene dos puntos de entrada que comparten una base de código común:
- `lib/main_client.dart` → `ClientApp` → flujo del usuario cliente
- `lib/main_barber.dart` → `BarberApp` → flujo del usuario barbero
- `lib/main.dart` apunta por defecto al entry point del cliente

La detección de rol en toda la app se hace mediante `AppConfig` (un `InheritedWidget` configurado en la raíz de cada app). Se comprueba con `AppConfig.of(context).isClient` o `.isBarber`.

### Organización de Módulos

```
lib/app/
├── barber/         # Pantallas, tabs y servicios exclusivos del barbero
├── client/         # Pantallas y tabs exclusivos del cliente
└── shared/         # Auth, splash screen, AppConfig, términos
```

### Gestión de Estado

No hay framework centralizado de gestión de estado. El estado se maneja con:
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

### Backend Firebase

Cloud Functions (`functions/index.js`, Node.js):
- `onNewAppointment` — notifica al barbero cuando el cliente reserva una cita
- `onAppointmentStatusChanged` — notifica a la parte correspondiente según el cambio de estado; limpia las coordenadas GPS cuando la cita sale del estado "confirmada"
- `cleanupRejectedAppointments` — cron diario que elimina citas rechazadas antiguas

Las reglas de seguridad de Firestore (`firestore.rules`) garantizan que los clientes solo puedan actualizar los campos de valoración y los campos de cancelación (`cancelledBy`/`status`); los barberos pueden actualizar las coordenadas GPS y el estado de la cita.

### Flujo de Estado de Citas

`pendiente` → `confirmada` → `completada`
`pendiente` o `confirmada` → `cancelada` (con el campo `cancelledBy` establecido en `"client"` o `"barber"`)

### Tests

54 tests unitarios que cubren: cálculos de distancia/Haversine, formateo de tiempo, lógica de destinatario de notificaciones y transiciones de estado de citas. Firebase y Google Maps no están testeados (sin mocks ni tests de integración). Los tests están en `test/`.
