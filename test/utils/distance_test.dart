import 'dart:math' show asin, cos, pi, sin, sqrt;
import 'package:flutter_test/flutter_test.dart';

// Helper function para calcular distancia Haversine
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // Radio de la Tierra en metros
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * asin(sqrt(a));
}

void main() {
  group('Distance Calculation Tests', () {
    test('Haversine distance between same location should be 0', () {
      const lat = 4.6097;
      const lon = -74.0817;
      
      final distance = haversineMeters(lat, lon, lat, lon);
      
      expect(distance, equals(0.0));
    });

    test('Haversine distance should be symmetric', () {
      const lat1 = 4.6097;
      const lon1 = -74.0817;
      const lat2 = 4.6117;
      const lon2 = -74.0837;
      
      final distance1 = haversineMeters(lat1, lon1, lat2, lon2);
      final distance2 = haversineMeters(lat2, lon2, lat1, lon1);
      
      expect(distance1, equals(distance2));
    });

    test('Haversine distance between 2 close points in Bogotá', () {
      // Aproximadamente 1 km de distancia
      const lat1 = 4.6097;
      const lon1 = -74.0817;
      const lat2 = 4.6187; // ~1 km al norte
      const lon2 = -74.0817;
      
      final distanceMeters = haversineMeters(lat1, lon1, lat2, lon2);
      final distanceKm = distanceMeters / 1000;
      
      // Debe estar cerca de 1 km (aproximadamente)
      expect(distanceKm, greaterThan(0.9));
      expect(distanceKm, lessThan(1.1));
    });

    test('Haversine distance should always be positive', () {
      const lat1 = 4.6097;
      const lon1 = -74.0817;
      const lat2 = 4.5097; // Sur
      const lon2 = -74.1817; // Oeste
      
      final distance = haversineMeters(lat1, lon1, lat2, lon2);
      
      expect(distance, greaterThan(0));
    });

    test('Distance formatting: less than 1km should show meters', () {
      const meters = 500.0;
      final formatted = meters < 1000 
          ? '${meters.round()} m' 
          : '${(meters / 1000).toStringAsFixed(1)} km';
      
      expect(formatted, equals('500 m'));
    });

    test('Distance formatting: more than 1km should show kilometers', () {
      const meters = 2500.0;
      final formatted = meters < 1000 
          ? '${meters.round()} m' 
          : '${(meters / 1000).toStringAsFixed(1)} km';
      
      expect(formatted, equals('2.5 km'));
    });
  });
}
