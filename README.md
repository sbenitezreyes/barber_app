# 💈 Barber App

Aplicación completa de gestión de citas para barberías con tracking GPS en tiempo real y sistema de notificaciones.

## 📱 Características

### Para Clientes
- ✅ Agendar citas (inmediatas o programadas)
- 📍 **Tracking en tiempo real** del barbero en camino
- 🗺️ Mapa con ruta y ETA cuando el barbero acepta cita inmediata
- ❌ Cancelar citas con notificación automática
- 📋 Ver historial de citas
- 👤 Gestión de perfil

### Para Barberos
- 🔔 **Sistema de notificaciones** con campanita y badge contador
- ✅ Aceptar/rechazar solicitudes de citas
- 🚗 Navegación GPS automática hacia el cliente
- 📊 Agenda de citas (pendientes, confirmadas, completadas)
- 📍 Publicación automática de ubicación en tiempo real
- 👥 Gestión de perfil y servicios

## 🛠️ Tecnologías Utilizadas

### Frontend
- **Flutter** - Framework multiplataforma
- **Google Maps** - Mapas y navegación
- **Geolocator** - GPS y ubicación
- **SharedPreferences** - Persistencia local

### Backend
- **Firebase Authentication** - Autenticación de usuarios
- **Cloud Firestore** - Base de datos en tiempo real
- **Firebase Cloud Messaging (FCM)** - Notificaciones push
- **Cloud Functions** - Lógica del lado del servidor

## 🏗️ Arquitectura

```
lib/
├── app/
│   ├── barber/          # Módulo del barbero
│   │   ├── screens/     # Pantallas (home, ruta, agenda)
│   │   └── services/    # Servicios (GPS, FCM)
│   └── client/          # Módulo del cliente
│       ├── screens/     # Pantallas (home, tracking)
│       └── services/    # Servicios compartidos
├── main_barber.dart     # Entry point barbero
└── main_client.dart     # Entry point cliente
```

## 🚀 Configuración del Proyecto

### Requisitos Previos
- Flutter SDK (>=3.0.0)
- Firebase CLI
- Cuenta de Google Cloud Platform
- Android Studio / Xcode

### 1. Clonar el Repositorio
```bash
git clone https://github.com/sbenitezreyes/barber_app.git
cd barber_app
```

### 2. Instalar Dependencias
```bash
flutter pub get
```

### 3. Configurar Firebase
```bash
# Instalar FlutterFire CLI
dart pub global activate flutterfire_cli

# Configurar proyecto de Firebase
flutterfire configure
```

### 4. Google Maps API Key
1. Ir a [Google Cloud Console](https://console.cloud.google.com/)
2. Habilitar **Maps SDK for Android** y **Maps SDK for iOS**
3. Crear API Key

**Android:** Agregar en `android/app/src/main/AndroidManifest.xml`
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="TU_API_KEY"/>
```

**iOS:** Agregar en `ios/Runner/AppDelegate.swift`
```swift
GMSServices.provideAPIKey("TU_API_KEY")
```

### 5. Deploy de Firestore Rules
```bash
firebase deploy --only firestore:rules
```

### 6. Deploy de Cloud Functions
```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

## 🎯 Ejecutar el Proyecto

### App Cliente
```bash
flutter run -t lib/main_client.dart
```

### App Barbero
```bash
flutter run -t lib/main_barber.dart
```

## 📦 Dependencias Principales

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^2.24.2
  firebase_auth: ^4.16.0
  cloud_firestore: ^4.14.0
  firebase_messaging: ^14.7.10
  google_maps_flutter: ^2.5.0
  geolocator: ^10.1.0
  shared_preferences: ^2.2.2
  intl: ^0.18.1
```

## 🔐 Firestore Security Rules

Las reglas implementadas garantizan:
- ✅ Los barberos pueden actualizar `status`, `barberCurrentLat`, `barberCurrentLng`
- ✅ Los clientes pueden cancelar citas (cambiar `status` a `'cancelled'`)
- ✅ Solo usuarios autenticados pueden leer/escribir sus propios datos
- ✅ Validación de campos obligatorios en documentos

## 🔔 Sistema de Notificaciones

### Funcionamiento
1. **Cloud Function** detecta cambios en `appointments`
2. Envía notificación push al dispositivo correspondiente
3. **FCM Service** maneja la notificación:
   - App en foreground: muestra notificación local
   - App en background: notificación nativa del sistema
   - Tap en notificación: navega a la pantalla relevante

### Badge Counter
- Cuenta notificaciones no vistas (pending + cancelled recientes)
- Se resetea a 0 al abrir el panel de notificaciones
- Persistencia con `SharedPreferences`

## 🗺️ GPS Tracking

### Publicación de Ubicación
- **Barber GPS Service:** Publica coordenadas cada 5 segundos en background
- **Client Route Screen:** Publica desde foreground cuando hay ruta activa
- Solo se activa para citas con `status == 'confirmed' && isImmediate == true`

### Visualización
- Banner en vivo aparece inmediatamente al confirmar cita
- Mapa muestra marcador del barbero y ruta calculada
- ETA actualizado en tiempo real

## 📝 Flujo de Citas Inmediatas

1. Cliente solicita cita inmediata → `status: 'pending'`
2. Notificación push al barbero
3. Barbero acepta → `status: 'confirmed'`
4. **GPS Service** comienza a publicar ubicación
5. Cliente ve banner "El barbero va en camino"
6. Tap en banner → pantalla de tracking con mapa
7. Barbero ve ruta de navegación hacia cliente
8. Al llegar, barbero marca como completada

## 🔄 Versionamiento

Este proyecto usa **Git** y **GitHub** para control de versiones.

### Guardar cambios
```bash
git add .
git commit -m "descripción de cambios"
git push
```

### Ver historial
```bash
git log --oneline
```

## 🐛 Troubleshooting

### FCM: "Permission request already running"
- Solucionado con patrón singleton y try-catch en `FcmService`
- Se ignora silenciosamente en hot restart

### GPS no publica coordenadas
- Verificar permisos de ubicación en AndroidManifest.xml / Info.plist
- Verificar Firestore rules permiten `barberCurrentLat/Lng`

### Badge no se resetea
- Verificar que `SharedPreferences` esté instalado
- Hot restart completo para limpiar estado

## 📄 Licencia

Este proyecto es privado y de uso exclusivo.

## 👨‍💻 Autor

**Santiago Benítez Reyes**
- GitHub: [@sbenitezreyes](https://github.com/sbenitezreyes)

---

Desarrollado con ❤️ usando Flutter y Firebase
