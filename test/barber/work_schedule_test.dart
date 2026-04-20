import 'package:flutter_test/flutter_test.dart';

// Lógica replicada de work_schedule_screen.dart — TimeInterval
// (el archivo importa Firebase/Flutter, no se puede importar directamente en tests)

String _fmt(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

({int hour, int minute}) _parse(String s) {
  final p = s.split(':');
  return (hour: int.parse(p[0]), minute: int.parse(p[1]));
}

int _toMinutes(int hour, int minute) => hour * 60 + minute;

Map<String, String> _toMap(int openH, int openM, int closeH, int closeM) =>
    {'open': _fmt(openH, openM), 'close': _fmt(closeH, closeM)};

void main() {
  group('WorkSchedule — TimeInterval', () {
    group('conversión a minutos desde medianoche', () {
      test('09:00 → 540 minutos', () => expect(_toMinutes(9, 0), equals(540)));
      test('18:00 → 1080 minutos', () => expect(_toMinutes(18, 0), equals(1080)));
      test('09:30 → 570 minutos', () => expect(_toMinutes(9, 30), equals(570)));
      test('00:00 → 0 minutos', () => expect(_toMinutes(0, 0), equals(0)));
      test('23:59 → 1439 minutos', () => expect(_toMinutes(23, 59), equals(1439)));
    });

    group('_fmt — formato HH:MM con relleno de ceros', () {
      test('9:5 → "09:05"', () => expect(_fmt(9, 5), equals('09:05')));
      test('18:0 → "18:00"', () => expect(_fmt(18, 0), equals('18:00')));
      test('0:0 → "00:00"', () => expect(_fmt(0, 0), equals('00:00')));
      test('23:59 → "23:59"', () => expect(_fmt(23, 59), equals('23:59')));
      test('12:30 → "12:30"', () => expect(_fmt(12, 30), equals('12:30')));
    });

    group('_parse — parseo de string HH:MM', () {
      test('"09:05" → hora=9, minuto=5', () {
        final t = _parse('09:05');
        expect(t.hour, equals(9));
        expect(t.minute, equals(5));
      });
      test('"18:00" → hora=18, minuto=0', () {
        final t = _parse('18:00');
        expect(t.hour, equals(18));
        expect(t.minute, equals(0));
      });
      test('"00:00" → hora=0, minuto=0', () {
        final t = _parse('00:00');
        expect(t.hour, equals(0));
        expect(t.minute, equals(0));
      });
    });

    group('toMap — serialización', () {
      test('produce claves "open" y "close"', () {
        final m = _toMap(9, 0, 18, 0);
        expect(m.containsKey('open'), isTrue);
        expect(m.containsKey('close'), isTrue);
      });
      test('valores formateados correctamente', () {
        final m = _toMap(9, 5, 18, 30);
        expect(m['open'], equals('09:05'));
        expect(m['close'], equals('18:30'));
      });
    });

    group('roundtrip: toMap → parse preserva valores', () {
      test('10:30 / 19:45 se restaura sin pérdida', () {
        final m = _toMap(10, 30, 19, 45);
        final open = _parse(m['open']!);
        final close = _parse(m['close']!);
        expect(open.hour, equals(10));
        expect(open.minute, equals(30));
        expect(close.hour, equals(19));
        expect(close.minute, equals(45));
      });
    });
  });
}
