import 'package:flutter_test/flutter_test.dart';

// Lógica replicada de barber_stats_screen.dart (funciones privadas)
class _Rank {
  final String name;
  final int minXp;
  final int maxXp;
  const _Rank({required this.name, required this.minXp, required this.maxXp});
}

const _ranks = [
  _Rank(name: 'Recluta',      minXp: 0,    maxXp: 449),
  _Rank(name: 'Aprendiz',     minXp: 450,  maxXp: 949),
  _Rank(name: 'Navajero',     minXp: 950,  maxXp: 1699),
  _Rank(name: 'Maestro',      minXp: 1700, maxXp: 3199),
  _Rank(name: 'Gran Maestro', minXp: 3200, maxXp: 6199),
  _Rank(name: 'Leyenda',      minXp: 6200, maxXp: -1),
];

_Rank _getRank(int xp) {
  for (final rank in _ranks.reversed) {
    if (xp >= rank.minXp) return rank;
  }
  return _ranks.first;
}

double _getRankProgress(int xp) {
  final rank = _getRank(xp);
  if (rank.maxXp == -1) return 1.0;
  final range = rank.maxXp - rank.minXp + 1;
  return ((xp - rank.minXp) / range).clamp(0.0, 1.0);
}

double _acceptanceRate(int completed, int totalRequests) =>
    totalRequests == 0 ? 0 : completed / totalRequests;

void main() {
  group('Barber Stats — progreso de rango', () {
    group('_getRank identifica el rango correcto', () {
      test('XP 0 → Recluta', () => expect(_getRank(0).name, 'Recluta'));
      test('XP 449 → Recluta', () => expect(_getRank(449).name, 'Recluta'));
      test('XP 450 → Aprendiz', () => expect(_getRank(450).name, 'Aprendiz'));
      test('XP 6200 → Leyenda', () => expect(_getRank(6200).name, 'Leyenda'));
      test('XP 99999 → Leyenda', () => expect(_getRank(99999).name, 'Leyenda'));
    });

    group('_getRankProgress calcula progreso correcto', () {
      test('Inicio de Recluta (XP=0) → 0.0', () {
        expect(_getRankProgress(0), closeTo(0.0, 0.001));
      });
      test('Mitad de Recluta (XP=225) → ~0.5', () {
        // Recluta: 0-449, rango=450 → 225/450 ≈ 0.5
        expect(_getRankProgress(225), closeTo(0.5, 0.01));
      });
      test('Casi límite de Recluta (XP=449) → ~1.0', () {
        // (449-0)/450 ≈ 0.998
        expect(_getRankProgress(449), closeTo(0.998, 0.002));
      });
      test('Inicio de Aprendiz (XP=450) → 0.0', () {
        expect(_getRankProgress(450), closeTo(0.0, 0.001));
      });
      test('Leyenda siempre → 1.0 (maxXp=-1)', () {
        expect(_getRankProgress(6200), equals(1.0));
        expect(_getRankProgress(100000), equals(1.0));
      });
      test('Progreso siempre entre 0.0 y 1.0', () {
        for (final xp in [0, 100, 450, 950, 1700, 3200, 6200, 50000]) {
          final p = _getRankProgress(xp);
          expect(p, greaterThanOrEqualTo(0.0), reason: 'XP=$xp');
          expect(p, lessThanOrEqualTo(1.0), reason: 'XP=$xp');
        }
      });
    });

    group('Tasa de aceptación', () {
      test('Sin solicitudes → 0%', () {
        expect(_acceptanceRate(0, 0), equals(0.0));
      });
      test('Mitad aceptadas → 50%', () {
        expect(_acceptanceRate(5, 10), equals(0.5));
      });
      test('Todas aceptadas → 100%', () {
        expect(_acceptanceRate(10, 10), equals(1.0));
      });
      test('Ninguna aceptada → 0%', () {
        expect(_acceptanceRate(0, 10), equals(0.0));
      });
    });
  });
}
