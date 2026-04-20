class RankInfo {
  final String name;
  final int minXp;
  final int maxXp; // -1 = sin límite
  const RankInfo(this.name, this.minXp, this.maxXp);
}

const rankTable = [
  RankInfo('Recluta',      0,    449),
  RankInfo('Aprendiz',     450,  949),
  RankInfo('Navajero',     950,  1699),
  RankInfo('Maestro',      1700, 3199),
  RankInfo('Gran Maestro', 3200, 6199),
  RankInfo('Leyenda',      6200, -1),
];

RankInfo rankFromXp(int xp) {
  for (final r in rankTable.reversed) {
    if (xp >= r.minXp) return r;
  }
  return rankTable.first;
}
