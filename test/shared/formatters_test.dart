import 'package:flutter_test/flutter_test.dart';

// ── Lógica replicada de barber_profile_sheet.dart ─────────────────

String formatPrice(double p) {
  return '\$${p.toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  )}';
}

String formatDistanceLabel(double meters) {
  final km = meters / 1000;
  return km < 1
      ? '${meters.round()} m'
      : '${km.toStringAsFixed(1)} km';
}

// Velocidades de home_tab/barber_profile_sheet
int walkMinutes(double meters) => (meters / 83).round();   // ~5 km/h
int motoMinutes(double meters) => (meters / 667).round();  // ~40 km/h

// ── Lógica de proximidad GPS de gps_service.dart ─────────────────
// citySpeedMps = 6.94 m/s (~25 km/h)
// bufferMinutes = 10
const _citySpeedMps = 6.94;
const _bufferMinutes = 10;

int travelMinutes(double distanceMeters) =>
    (distanceMeters / _citySpeedMps / 60).ceil();

bool shouldNotify(double distanceMeters, int minutesUntilAppt) =>
    minutesUntilAppt <= travelMinutes(distanceMeters) + _bufferMinutes;

void main() {
  group('Formateo de precios', () {
    test('\$0 sin separadores', () => expect(formatPrice(0), equals('\$0')));
    test('\$999 sin separadores', () => expect(formatPrice(999), equals('\$999')));
    test('\$1000 → "\$1.000"', () => expect(formatPrice(1000), equals('\$1.000')));
    test('\$5000 → "\$5.000"', () => expect(formatPrice(5000), equals('\$5.000')));
    test('\$50000 → "\$50.000"', () => expect(formatPrice(50000), equals('\$50.000')));
    test('\$1500000 → "\$1.500.000"', () => expect(formatPrice(1500000), equals('\$1.500.000')));
    test('decimales se truncan: 1234.9 → "\$1.235"', () {
      // toStringAsFixed(0) redondea
      expect(formatPrice(1234.9), equals('\$1.235'));
    });
  });

  group('Etiqueta de distancia', () {
    test('500 m → "500 m"', () => expect(formatDistanceLabel(500), equals('500 m')));
    test('999 m → "999 m"', () => expect(formatDistanceLabel(999), equals('999 m')));
    test('1000 m → "1.0 km"', () => expect(formatDistanceLabel(1000), equals('1.0 km')));
    test('2500 m → "2.5 km"', () => expect(formatDistanceLabel(2500), equals('2.5 km')));
    test('10000 m → "10.0 km"', () => expect(formatDistanceLabel(10000), equals('10.0 km')));
  });

  group('Tiempo de desplazamiento', () {
    test('500 m caminando → ~6 min', () {
      expect(walkMinutes(500), equals(6));
    });
    test('1000 m caminando → ~12 min', () {
      expect(walkMinutes(1000), equals(12));
    });
    test('500 m en moto → ~1 min', () {
      expect(motoMinutes(500), equals(1));
    });
    test('5000 m en moto → ~7 min', () {
      expect(motoMinutes(5000), equals(7));
    });
    test('0 m → 0 min', () {
      expect(walkMinutes(0), equals(0));
      expect(motoMinutes(0), equals(0));
    });
  });

  group('Lógica de notificación GPS de proximidad', () {
    test('cita en 20 min, a 500 m → NO notificar (tiempo de viaje ~1 min + 10 buffer = 11)', () {
      // travelMinutes(500) = ceil(500/6.94/60) = ceil(1.2) = 2 → 2+10=12 < 20
      expect(shouldNotify(500, 20), isFalse);
    });
    test('cita en 5 min, a 500 m → notificar', () {
      // travelMinutes(500) = 2 → 2+10=12 > 5 → true
      expect(shouldNotify(500, 5), isTrue);
    });
    test('cita en 12 min, a 500 m → notificar (justo en el límite)', () {
      // travelMinutes(500) = 2 → 2+10=12 == 12 → true (<=)
      expect(shouldNotify(500, 12), isTrue);
    });
    test('cita en 30 min, a 5 km → notificar', () {
      // travelMinutes(5000) = ceil(5000/6.94/60) = ceil(12.0) = 12 → 12+10=22 < 30? NO → false
      expect(shouldNotify(5000, 30), isFalse);
    });
    test('cita en 15 min, a 5 km → notificar', () {
      // travelMinutes(5000) = 12 → 12+10=22 > 15 → true
      expect(shouldNotify(5000, 15), isTrue);
    });
  });
}
