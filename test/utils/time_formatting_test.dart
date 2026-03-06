import 'package:flutter_test/flutter_test.dart';

// Helper function para formatear tiempo relativo
String timeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  
  if (diff.inDays > 0) {
    return 'hace ${diff.inDays}d';
  } else if (diff.inHours > 0) {
    return 'hace ${diff.inHours}h';
  } else if (diff.inMinutes > 0) {
    return 'hace ${diff.inMinutes} min';
  } else {
    return 'Ahora';
  }
}

// Helper function para formatear ETA
String formatEta(double distanceKm) {
  const speedKmPerHour = 40.0; // Velocidad promedio de moto en ciudad
  final hours = distanceKm / speedKmPerHour;
  final minutes = (hours * 60).round();
  
  return minutes < 1 ? 'Llegando' : '~$minutes min';
}

void main() {
  group('Time Formatting Tests', () {
    test('timeAgo should return "Ahora" for very recent times', () {
      final now = DateTime.now();
      expect(timeAgo(now), equals('Ahora'));
      
      final fewSecondsAgo = now.subtract(const Duration(seconds: 30));
      expect(timeAgo(fewSecondsAgo), equals('Ahora'));
    });

    test('timeAgo should return minutes for recent events', () {
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
      
      expect(timeAgo(fiveMinutesAgo), equals('hace 5 min'));
    });

    test('timeAgo should return hours for events within a day', () {
      final now = DateTime.now();
      final twoHoursAgo = now.subtract(const Duration(hours: 2));
      
      expect(timeAgo(twoHoursAgo), equals('hace 2h'));
    });

    test('timeAgo should return days for older events', () {
      final now = DateTime.now();
      final threeDaysAgo = now.subtract(const Duration(days: 3));
      
      expect(timeAgo(threeDaysAgo), equals('hace 3d'));
    });

    test('timeAgo should handle exactly 1 minute', () {
      final now = DateTime.now();
      final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
      
      expect(timeAgo(oneMinuteAgo), equals('hace 1 min'));
    });

    test('timeAgo should handle exactly 1 hour', () {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      
      expect(timeAgo(oneHourAgo), equals('hace 1h'));
    });

    test('timeAgo should handle exactly 1 day', () {
      final now = DateTime.now();
      final oneDayAgo = now.subtract(const Duration(days: 1));
      
      expect(timeAgo(oneDayAgo), equals('hace 1d'));
    });
  });

  group('ETA Formatting Tests', () {
    test('formatEta should return "Llegando" for very short distances', () {
      expect(formatEta(0.0), equals('Llegando'));
      expect(formatEta(0.5 / 40), equals('Llegando')); // < 1 min
    });

    test('formatEta should calculate minutes correctly', () {
      // 1 km a 40 km/h = 1.5 minutos
      expect(formatEta(1.0), equals('~2 min'));
      
      // 5 km a 40 km/h = 7.5 minutos
      expect(formatEta(5.0), equals('~8 min'));
    });

    test('formatEta should round to nearest minute', () {
      // 3.3 km a 40 km/h = ~5 minutos
      expect(formatEta(3.3), equals('~5 min'));
    });

    test('formatEta should handle longer distances', () {
      // 20 km a 40 km/h = 30 minutos
      expect(formatEta(20.0), equals('~30 min'));
    });
  });
}
