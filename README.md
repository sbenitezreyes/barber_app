# YaCut — Barbería a Demanda

Plataforma completa de barbería a domicilio construida en Flutter, con dos apps separadas (cliente y barbero), tracking GPS en tiempo real, sistema de notificaciones push y seguridad de API keys a través de Cloud Functions.

## Características

### App Cliente
- Reservar citas inmediatas o programadas con barberos cercanos
- Tracking en tiempo real del barbero en camino (ruta por calles, no línea recta)
- Mapa interactivo con marcadores, ruta calculada y ETA actualizado en tiempo real
- Cancelar citas con notificación automática al barbero
- Historial y calendario de citas con colores por estado
- Direcciones guardadas con mapa y geocoding inverso
- Favoritos de barberos
- Modo invitado para explorar la app sin registro
- Botón SOS con contactos de emergencia y detección de agitación del teléfono
- Gestión de perfil y foto de usuario

### App Barbero
- Recibir y gestionar solicitudes de citas en tiempo real
- Notificaciones push con badge contador persistente
- Aceptar o rechazar citas de clientes
- Navegación GPS automática hacia el cliente al aceptar una cita inmediata
- Agenda con calendario por día y estados de citas
- Panel de estadísticas con logros desbloqueables por hitos
- Publicación automática de ubicación GPS cada 5 segundos durante citas activas
- Horario de trabajo configurable por días
- Gestión de servicios y precios
- Contactos de emergencia y botón SOS con detección de agitación
- Verificación de identidad por cédula (OCR)

## Tecnologías

### Frontend
- **Flutter** — framework multiplataforma con flavors (client / barber)
- **Google Maps Flutter** — mapas, marcadores y polilíneas de ruta
- **Geolocator** — GPS y permisos de ubicación
- **Shake** — detección de agitación para activar SOS
- **Google Fonts (Playfair Display + Figtree)** — sistema de diseño "La Navaja"
- **SharedPreferences** — persistencia local de flags y preferencias

### Backend
- **Firebase Authentication** — email/contraseña, Google Sign-In, usuarios anónimos (invitados)
- **Cloud Firestore** — base de datos en tiempo real con reglas de seguridad por rol
- **Firebase Cloud Messaging (FCM)** — notificaciones push
- **Cloud Functions (Node.js v2)** — lógica de servidor y proxies seguros de Google Maps
- **Firebase Secret Manager** — almacenamiento seguro de API keys (nunca en el APK)

## Arquitectura

```
lib/
├── app/
│   ├── barber/
│   │   ├── screens/         # home, agenda, ruta cliente, estadísticas, notificaciones
│   │   ├── services/        # FcmService (singleton), BarberGpsService
│   │   └── ...tabs/         # mapa, agenda, perfil, configuración
│   ├── client/
│   │   ├── screens/         # home, tracking, reserva, direcciones, perfil
│   │   └── ...tabs/         # mapa, citas, favoritos, perfil
│   └── shared/
│       ├── auth/            # login, registro, Google Auth, verificación cédula
│       ├── theme/           # AppColors, AppTextStyles, AppDecorations ("La Navaja")
│       └── ...              # splash, app_config, guest_auth_prompt
├── main_barber.dart         # entry point app barbero
└── main_client.dart         # entry point app cliente

functions/
└── index.js                 # Cloud Functions: notificaciones + proxies Google Maps
```

## Seguridad de API Keys

Las llamadas a Google Directions API y Geocoding API se realizan desde **Cloud Functions**, no desde el APK. La clave del servidor se almacena en **Firebase Secret Manager** y nunca se incluye en el código compilado.

- `getRoute` — proxy para Google Directions API (ruta por calles)
- `reverseGeocode` — proxy para Geocoding API (coordenadas → dirección)
- `geocodeAddress` — proxy para Geocoding API (dirección → coordenadas)

La Maps SDK key del AndroidManifest.xml está protegida por restricción de SHA-1 + package name (solo funciona desde el APK firmado), lo que es aceptable para uso en dispositivo.

## Configuración del Proyecto

### Requisitos
- Flutter SDK ≥ 3.19
- Firebase CLI
- Cuenta Google Cloud Platform con facturación activa (para Cloud Functions y Secret Manager)
- Android Studio con NDK

### 1. Clonar y dependencias
```bash
git clone https://github.com/sbenitezreyes/barber_app.git
cd barber_app
flutter pub get
```

### 2. Firebase
```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

### 3. API Keys de Google Maps

**AndroidManifest.xml** — Maps SDK for Android (restringida por SHA-1 + package name):
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="TU_MAPS_SDK_KEY"/>
```

**Firebase Secret Manager** — clave sin restricción de plataforma para Cloud Functions (Directions API + Geocoding API):
```bash
firebase functions:secrets:set GOOGLE_MAPS_KEY
# pegar la clave cuando lo pida
```

APIs a habilitar en Google Cloud Console:
- Maps SDK for Android
- Directions API
- Geocoding API

### 4. Deploy

```bash
# Reglas de Firestore
firebase deploy --only firestore:rules

# Cloud Functions
cd functions && npm install && cd ..
firebase deploy --only functions

# Todo en un paso
firebase deploy
```

### 5. Ejecutar

```bash
# App cliente
flutter run --flavor client -t lib/main_client.dart

# App barbero
flutter run --flavor barber -t lib/main_barber.dart
```

### APKs de release

```bash
flutter build apk --flavor client -t lib/main_client.dart \
  --release --obfuscate --split-debug-info=build/symbols/client

flutter build apk --flavor barber -t lib/main_barber.dart \
  --release --obfuscate --split-debug-info=build/symbols/barber
```

## Flujo de Cita Inmediata

1. Cliente solicita cita inmediata → `status: 'pending'`
2. Notificación push al barbero
3. Barbero acepta → `status: 'confirmed'`
4. BarberGpsService publica ubicación cada 5 s en Firestore
5. Cliente ve banner "El barbero va en camino" → pantalla de tracking
6. Ruta por calles calculada via Cloud Function (Google Directions API)
7. Barbero ve navegación GPS hacia el cliente (ClientRouteScreen)
8. Al terminar → `status: 'completed'`; GPS se detiene automáticamente

## Flujo de Estado de Citas

```
pending → confirmed → en_servicio → completed
pending | confirmed → cancelled   (cancelledBy: "client" | "barber")
pending             → rejected    (barbero rechaza)
```

## Reglas de Firestore

Seguridad por rol implementada en `firestore.rules`:
- Barbero puede actualizar `status` (confirmed / en_servicio / completed / missed / cancelled / **rejected**), coordenadas GPS, `cancelledBy` y flags de salida
- Cliente puede cancelar su propia cita (`status: 'cancelled'` + `cancelledBy`)
- Clientes pueden crear reseñas; solo el autor puede eliminarlas
- Clientes pueden actualizar rating del barbero
- Solo el dueño del documento puede leer/escribir su subcolección `addresses`

## Tests

```bash
flutter test
```

54 tests unitarios en `test/` — cálculos Haversine, formateo de tiempo, lógica de notificaciones y transiciones de estado. Firebase y Google Maps no están testeados (sin mocks de integración).

## Dependencias Principales

```yaml
google_maps_flutter: ^2.9.0
geolocator: ^13.0.2
firebase_core: ^3.13.0
firebase_auth: ^5.5.2
cloud_firestore: ^5.6.5
firebase_messaging: ^15.2.5
cloud_functions: ^6.0.6
shake: ^3.0.0
google_fonts: ^6.2.1
table_calendar: ^3.1.3
flutter_polyline_points: ^2.1.0
```

## Autor

**Santiago Benítez Reyes**
- GitHub: [@sbenitezreyes](https://github.com/sbenitezreyes)

---

Desarrollado con Flutter y Firebase
