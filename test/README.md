# Test Suite - Barber App

## Test Coverage

Esta suite de pruebas cubre la lógica de negocio crítica de la aplicación sin depender de Firebase o servicios externos.

### 📊 Tests Implementados (54 tests)

#### 1. **Distance Tests** (`test/utils/distance_test.dart`)
- ✅ Cálculo de distancia Haversine entre coordenadas GPS
- ✅ Validación de simetría (A→B = B→A)
- ✅ Distancia cero para misma ubicación
- ✅ Distancias positivas siempre
- ✅ Formateo de distancias (metros vs kilómetros)

**Cobertura:** Cálculo de distancias usado en mapas y tracking

#### 2. **Time Formatting Tests** (`test/utils/time_formatting_test.dart`)
- ✅ Formateo de tiempo relativo ("hace X min/h/d")
- ✅ Manejo de eventos recientes ("Ahora")
- ✅ Cálculo de ETA (tiempo estimado de llegada)
- ✅ Redondeo de minutos
- ✅ Mensaje "Llegando" para distancias cortas

**Cobertura:** Formateo de timestamps en notificaciones y tracking

#### 3. **Notification Logic Tests** (`test/models/notification_logic_test.dart`)
- ✅ Identificación del destinatario correcto según quién canceló
- ✅ Generación de mensajes personalizados (barbero vs cliente)
- ✅ Mensajes en panel de notificaciones (ambas apps)
- ✅ Manejo de casos edge (UIDs vacíos, desconocidos)

**Cobertura:** Lógica crítica de cancelaciones y notificaciones

#### 4. **Appointment Status Tests** (`test/models/appointment_status_test.dart`)
- ✅ Transiciones válidas de estado
- ✅ Estados terminales (no pueden cambiar)
- ✅ Validación de estados que requieren notificación
- ✅ Conversión string ↔ enum
- ✅ Asignación de colores por estado

**Cobertura:** Máquina de estados de citas

#### 5. **Widget Tests** (`test/widget_test.dart`)
- ✅ Renderizado básico de MaterialApp
- ✅ Interacciones con botones
- ✅ Badges de notificaciones
- ✅ Diálogos de confirmación
- ✅ Estructura de containers

**Cobertura:** Componentes UI básicos

---

## 🚀 Ejecutar Tests

### Todos los tests
```bash
flutter test
```

### Tests específicos
```bash
# Tests de distancia
flutter test test/utils/distance_test.dart

# Tests de notificaciones
flutter test test/models/notification_logic_test.dart

# Tests de estados
flutter test test/models/appointment_status_test.dart
```

### Con cobertura
```bash
flutter test --coverage
```

---

## 📝 Resultados Actuales

✅ **54/54 tests pasando** (100%)

```
test/models/appointment_status_test.dart: All tests passed!
test/models/notification_logic_test.dart: All tests passed!
test/utils/distance_test.dart: All tests passed!
test/utils/time_formatting_test.dart: All tests passed!
test/widget_test.dart: All tests passed!
```

---

## 🎯 Qué NO está cubierto aún

Por complejidad de mocking, no se incluyeron tests para:

- **Firebase Authentication**: Login, registro, sign out
- **Firestore**: Queries, actualizaciones, listeners
- **Firebase Storage**: Upload de imágenes
- **Firebase Messaging**: Push notifications
- **Google Maps**: Renderizado de mapas, marcadores, cámara
- **Geolocator**: Permisos, ubicación en tiempo real

Estos requerirían:
- `mockito` o `mocktail` para mocks
- `firebase_auth_mocks`, `fake_cloud_firestore`
- Configuración compleja de dependencias

---

## 🔍 Casos de Uso Testeados

### Escenario 1: Barbero cancela cita
```dart
cancelledBy = barberUid
→ Notificación va al cliente ✅
→ Mensaje: "{barberName} canceló la cita" ✅
→ Panel barbero: "Haz cancelado la cita a: {clientName}" ✅
```

### Escenario 2: Cliente cancela cita
```dart
cancelledBy = clientUid
→ Notificación va al barbero ✅
→ Mensaje: "{clientName} canceló la cita" ✅
→ Panel cliente: "Cancelada · {barberName}" ✅
```

### Escenario 3: Tracking de distancia
```dart
barberLat = 4.6097, barberLng = -74.0817
clientLat = 4.6187, clientLng = -74.0817
→ Distancia ≈ 1 km ✅
→ ETA ≈ 2 min (a 40 km/h) ✅
→ Formato: "1.0 km" ✅
```

### Escenario 4: Transiciones de estado
```dart
pending → confirmed ✅
confirmed → completed ✅
cancelled → [ningún estado] ✅ (terminal)
```

---

## 🛠️ Mantenimiento

### Agregar nuevos tests:

1. Crear archivo en `test/[carpeta]/nombre_test.dart`
2. Importar `flutter_test`
3. Definir `main() { group('...', () { test('...') }) }`
4. Ejecutar `flutter test`

### Verificar cobertura:

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## ✅ Próximos Pasos

1. ✅ **Tests unitarios completados**
2. 🔄 **Hacer commit con cambios**
3. 📤 **Push a rama santiago**
4. 🧪 **Testing manual en dispositivos reales**

---

**Última actualización:** 6 de marzo de 2026  
**Total de tests:** 54  
**Estado:** ✅ Todos pasando
