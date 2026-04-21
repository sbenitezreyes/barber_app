import 'package:flutter_test/flutter_test.dart';

// Lógica replicada de home_tab.dart — _isWithinSchedule()
// Se inyecta [now] para que los tests sean deterministas.

bool isWithinSchedule(Map<String, dynamic> data, DateTime now) {
  const dayKeys = [
    'monday',   // weekday 1
    'tuesday',  // weekday 2
    'wednesday',// weekday 3
    'thursday', // weekday 4
    'friday',   // weekday 5
    'saturday', // weekday 6
    'sunday',   // weekday 7
  ];

  final schedule = data['schedule'];
  if (schedule == null || schedule is! Map) return true; // sin horario → mostrar

  final todayKey = dayKeys[now.weekday - 1];
  final dayData = schedule[todayKey];
  if (dayData == null || dayData is! Map) return false;

  final enabled = dayData['enabled'] == true;
  if (!enabled) return false;

  final openStr = dayData['open'] as String?;
  final closeStr = dayData['close'] as String?;
  if (openStr == null || closeStr == null) return false;

  final openParts = openStr.split(':');
  final closeParts = closeStr.split(':');
  final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
  final closeMinutes = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
  final nowMinutes = now.hour * 60 + now.minute;

  return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
}

// Helper: lunes a las 14:00
DateTime _monday(int hour, int minute) {
  // 2025-01-06 era lunes (weekday=1)
  return DateTime(2025, 1, 6, hour, minute);
}

Map<String, dynamic> _mondaySchedule({
  bool enabled = true,
  String open = '09:00',
  String close = '18:00',
}) => {
  'schedule': {
    'monday': {'enabled': enabled, 'open': open, 'close': close},
  },
};

void main() {
  group('Schedule Validation — isWithinSchedule()', () {
    group('sin horario configurado', () {
      test('schedule=null → true (mostrar barbero)', () {
        expect(isWithinSchedule({}, _monday(14, 0)), isTrue);
      });
      test('schedule vacío → true', () {
        expect(isWithinSchedule({'schedule': null}, _monday(14, 0)), isTrue);
      });
      test('schedule no es Map → true', () {
        expect(isWithinSchedule({'schedule': 'invalid'}, _monday(14, 0)), isTrue);
      });
    });

    group('día deshabilitado', () {
      test('enabled=false → false', () {
        final data = _mondaySchedule(enabled: false);
        expect(isWithinSchedule(data, _monday(14, 0)), isFalse);
      });
      test('día no configurado en schedule → false', () {
        // Solo tiene 'tuesday', consultamos lunes
        final data = {'schedule': {'tuesday': {'enabled': true, 'open': '09:00', 'close': '18:00'}}};
        expect(isWithinSchedule(data, _monday(14, 0)), isFalse);
      });
    });

    group('dentro del horario', () {
      test('exactamente al abrir (09:00) → true', () {
        expect(isWithinSchedule(_mondaySchedule(), _monday(9, 0)), isTrue);
      });
      test('mitad del día (14:00) → true', () {
        expect(isWithinSchedule(_mondaySchedule(), _monday(14, 0)), isTrue);
      });
      test('un minuto antes de cerrar (17:59) → true', () {
        expect(isWithinSchedule(_mondaySchedule(), _monday(17, 59)), isTrue);
      });
    });

    group('fuera del horario', () {
      test('antes de abrir (08:59) → false', () {
        expect(isWithinSchedule(_mondaySchedule(), _monday(8, 59)), isFalse);
      });
      test('exactamente al cerrar (18:00) → false', () {
        expect(isWithinSchedule(_mondaySchedule(), _monday(18, 0)), isFalse);
      });
      test('después de cerrar (20:00) → false', () {
        expect(isWithinSchedule(_mondaySchedule(), _monday(20, 0)), isFalse);
      });
    });

    group('horarios especiales', () {
      test('jornada nocturna 20:00–23:00 — dentro → true', () {
        final data = _mondaySchedule(open: '20:00', close: '23:00');
        expect(isWithinSchedule(data, _monday(21, 30)), isTrue);
      });
      test('jornada nocturna 20:00–23:00 — fuera → false', () {
        final data = _mondaySchedule(open: '20:00', close: '23:00');
        expect(isWithinSchedule(data, _monday(14, 0)), isFalse);
      });
    });
  });
}
