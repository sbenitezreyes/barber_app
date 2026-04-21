import 'package:flutter_test/flutter_test.dart';
import 'package:barber_app/app/shared/xp_rank.dart';

void main() {
  group('XP Rank System — rankFromXp()', () {
    group('nombre de rango correcto por tier', () {
      test('XP 0 → Recluta', () => expect(rankFromXp(0).name, 'Recluta'));
      test('XP 449 → Recluta (límite superior)', () => expect(rankFromXp(449).name, 'Recluta'));
      test('XP 450 → Aprendiz', () => expect(rankFromXp(450).name, 'Aprendiz'));
      test('XP 949 → Aprendiz (límite superior)', () => expect(rankFromXp(949).name, 'Aprendiz'));
      test('XP 950 → Navajero', () => expect(rankFromXp(950).name, 'Navajero'));
      test('XP 1699 → Navajero (límite superior)', () => expect(rankFromXp(1699).name, 'Navajero'));
      test('XP 1700 → Maestro', () => expect(rankFromXp(1700).name, 'Maestro'));
      test('XP 3199 → Maestro (límite superior)', () => expect(rankFromXp(3199).name, 'Maestro'));
      test('XP 3200 → Gran Maestro', () => expect(rankFromXp(3200).name, 'Gran Maestro'));
      test('XP 6199 → Gran Maestro (límite superior)', () => expect(rankFromXp(6199).name, 'Gran Maestro'));
      test('XP 6200 → Leyenda', () => expect(rankFromXp(6200).name, 'Leyenda'));
      test('XP 100000 → Leyenda (desbordamiento)', () => expect(rankFromXp(100000).name, 'Leyenda'));
    });

    group('minXp y maxXp correctos', () {
      test('Recluta: minXp=0, maxXp=449', () {
        final r = rankFromXp(0);
        expect(r.minXp, equals(0));
        expect(r.maxXp, equals(449));
      });
      test('Aprendiz: minXp=450, maxXp=949', () {
        final r = rankFromXp(450);
        expect(r.minXp, equals(450));
        expect(r.maxXp, equals(949));
      });
      test('Leyenda: maxXp=-1 (sin límite)', () {
        final r = rankFromXp(6200);
        expect(r.maxXp, equals(-1));
      });
    });
  });
}
