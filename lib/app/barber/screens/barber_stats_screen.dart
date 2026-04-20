import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

// ── Modelos ───────────────────────────────────────────────────────

class _Stats {
  final int completed;
  final int totalRequests;
  final int thisMonth;
  final Map<int, int> byWeekday;
  final Map<String, int> byService;
  final double rating;
  final int ratingCount;
  final Map<int, int> ratingDist;
  final int xp;

  const _Stats({
    required this.completed,
    required this.totalRequests,
    required this.thisMonth,
    required this.byWeekday,
    required this.byService,
    required this.rating,
    required this.ratingCount,
    required this.ratingDist,
    required this.xp,
  });

  double get acceptanceRate =>
      totalRequests == 0 ? 0 : completed / totalRequests;
}

// ── Sistema de rangos ─────────────────────────────────────────────

class _Rank {
  final String name;
  final String icon;
  final int minXp;
  final int maxXp; // -1 = sin límite (rango máximo)
  final Color color;

  const _Rank({
    required this.name,
    required this.icon,
    required this.minXp,
    required this.maxXp,
    required this.color,
  });
}

const _ranks = [
  _Rank(
    name: 'Recluta',
    icon: '🪒',
    minXp: 0,
    maxXp: 449,
    color: Color(0xFF9E9E9E),
  ),
  _Rank(
    name: 'Aprendiz',
    icon: '✂️',
    minXp: 450,
    maxXp: 949,
    color: Color(0xFF66BB6A),
  ),
  _Rank(
    name: 'Navajero',
    icon: '⚔️',
    minXp: 950,
    maxXp: 1699,
    color: Color(0xFF42A5F5),
  ),
  _Rank(
    name: 'Maestro',
    icon: '🏆',
    minXp: 1700,
    maxXp: 3199,
    color: Color(0xFFC9A84C),
  ),
  _Rank(
    name: 'Gran Maestro',
    icon: '💎',
    minXp: 3200,
    maxXp: 6199,
    color: Color(0xFFAB47BC),
  ),
  _Rank(
    name: 'Leyenda',
    icon: '👑',
    minXp: 6200,
    maxXp: -1,
    color: Color(0xFFE55252),
  ),
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

// ── Sistema de logros ─────────────────────────────────────────────

class _Achievement {
  final String icon;
  final String title;
  final String description;
  final bool Function(_Stats) unlocked;
  final String Function(_Stats) progress;

  const _Achievement({
    required this.icon,
    required this.title,
    required this.description,
    required this.unlocked,
    required this.progress,
  });
}

final _achievements = <_Achievement>[
  _Achievement(
    icon: '🪒',
    title: 'Primera cita',
    description: 'Completa tu primera cita como barbero.',
    unlocked: (s) => s.completed >= 1,
    progress: (s) => '${s.completed.clamp(0, 1)} / 1 cita completada',
  ),
  _Achievement(
    icon: '🔥',
    title: 'En el ritmo',
    description: 'Completa 5 citas en total.',
    unlocked: (s) => s.completed >= 5,
    progress: (s) => '${s.completed.clamp(0, 5)} / 5 citas completadas',
  ),
  _Achievement(
    icon: '✂️',
    title: 'Barbero en forma',
    description: 'Completa 15 citas en total.',
    unlocked: (s) => s.completed >= 15,
    progress: (s) => '${s.completed.clamp(0, 15)} / 15 citas completadas',
  ),
  _Achievement(
    icon: '⚔️',
    title: 'Navaja afilada',
    description: 'Completa 30 citas en total.',
    unlocked: (s) => s.completed >= 30,
    progress: (s) => '${s.completed.clamp(0, 30)} / 30 citas completadas',
  ),
  _Achievement(
    icon: '🏆',
    title: 'Maestro del filo',
    description: 'Completa 60 citas en total.',
    unlocked: (s) => s.completed >= 60,
    progress: (s) => '${s.completed.clamp(0, 60)} / 60 citas completadas',
  ),
  _Achievement(
    icon: '👑',
    title: 'Leyenda',
    description: 'Completa 100 citas en total.',
    unlocked: (s) => s.completed >= 100,
    progress: (s) => '${s.completed.clamp(0, 100)} / 100 citas completadas',
  ),
  _Achievement(
    icon: '⭐',
    title: 'Favorito',
    description: 'Mantén un promedio de 4.5★ o más con al menos una reseña.',
    unlocked: (s) => s.ratingCount > 0 && s.rating >= 4.5,
    progress: (s) => s.ratingCount == 0
        ? 'Sin reseñas aún'
        : 'Promedio actual: ${s.rating.toStringAsFixed(1)}★ (meta: 4.5★)',
  ),
  _Achievement(
    icon: '💎',
    title: 'Perfecto',
    description: 'Mantén un promedio de 4.8★ o más con al menos una reseña.',
    unlocked: (s) => s.ratingCount > 0 && s.rating >= 4.8,
    progress: (s) => s.ratingCount == 0
        ? 'Sin reseñas aún'
        : 'Promedio actual: ${s.rating.toStringAsFixed(1)}★ (meta: 4.8★)',
  ),
  _Achievement(
    icon: '🛡️',
    title: 'Confiable',
    description: 'Alcanza una tasa de aceptación del 80% o más.',
    unlocked: (s) => s.acceptanceRate >= 0.80,
    progress: (s) => s.totalRequests == 0
        ? 'Sin solicitudes aún'
        : '${(s.acceptanceRate * 100).round()}% de aceptación (meta: 80%)',
  ),
  _Achievement(
    icon: '🎯',
    title: 'Sin fallas',
    description: 'Alcanza una tasa de aceptación del 95% o más.',
    unlocked: (s) => s.acceptanceRate >= 0.95,
    progress: (s) => s.totalRequests == 0
        ? 'Sin solicitudes aún'
        : '${(s.acceptanceRate * 100).round()}% de aceptación (meta: 95%)',
  ),
];

// ── Modelo de reseña ──────────────────────────────────────────────

class _Review {
  final String clientUid;
  final String clientName;
  final double rating;
  final String comment;
  final DateTime createdAt;

  const _Review({
    required this.clientUid,
    required this.clientName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });
}

// ── Pantalla principal ────────────────────────────────────────────

class BarberStatsScreen extends StatefulWidget {
  const BarberStatsScreen({super.key});

  @override
  State<BarberStatsScreen> createState() => _BarberStatsScreenState();
}

class _BarberStatsScreenState extends State<BarberStatsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  _Stats? _stats;
  bool _loading = true;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _loadStats();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final apptSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('barberUid', isEqualTo: _uid)
          .get();

      int completed = 0;
      int totalRequests = 0;
      int thisMonth = 0;
      final byWeekday = <int, int>{};
      final byService = <String, int>{};
      final now = DateTime.now();

      for (final doc in apptSnap.docs) {
        final d = doc.data();
        final status = d['status'] as String? ?? '';
        final ts = d['scheduledAt'] as Timestamp?;
        final date = ts?.toDate();
        final service = d['serviceName'] as String? ?? 'Servicio';

        totalRequests++;

        if (status == 'completed') {
          completed++;
          if (date != null) {
            byWeekday[date.weekday] = (byWeekday[date.weekday] ?? 0) + 1;
            byService[service] = (byService[service] ?? 0) + 1;
            if (date.year == now.year && date.month == now.month) {
              thisMonth++;
            }
          }
        }
      }

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
      final userData = userSnap.data() ?? {};
      final rating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
      final ratingCount = (userData['ratingCount'] as num?)?.toInt() ?? 0;
      final xp = (userData['xp'] as num?)?.toInt() ?? 0;

      final reviewsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('reviews')
          .get();

      final ratingDist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      for (final doc in reviewsSnap.docs) {
        final r = ((doc.data()['rating'] as num?)?.toDouble() ?? 0).round();
        if (r >= 1 && r <= 5) ratingDist[r] = (ratingDist[r] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _stats = _Stats(
            completed: completed,
            totalRequests: totalRequests,
            thisMonth: thisMonth,
            byWeekday: byWeekday,
            byService: byService,
            rating: rating,
            ratingCount: ratingCount,
            ratingDist: ratingDist,
            xp: xp,
          );
          _loading = false;
        });
        _ctrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Animation<double> _slide(double begin, double end) => CurvedAnimation(
    parent: _ctrl,
    curve: Interval(begin, end, curve: Curves.easeOut),
  );

  Widget _section(double from, Widget child) {
    final anim = _slide(from, (from + 0.35).clamp(0.0, 1.0));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Estadísticas', style: AppTextStyles.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _stats == null
          ? Center(
              child: Text(
                'No se pudieron cargar los datos',
                style: AppTextStyles.body,
              ),
            )
          : _buildContent(_stats!),
    );
  }

  Widget _buildContent(_Stats stats) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _section(0.00, _RankCard(stats: stats)),
        const SizedBox(height: 20),
        _section(0.08, _StatsGrid(stats: stats)),
        const SizedBox(height: 20),
        _section(0.16, _ActivityChart(stats: stats)),
        const SizedBox(height: 20),
        if (stats.byService.isNotEmpty) ...[
          _section(0.24, _ServicesCard(stats: stats)),
          const SizedBox(height: 20),
        ],
        if (stats.ratingCount > 0) ...[
          _section(0.32, _RatingsCard(stats: stats)),
          const SizedBox(height: 20),
          _section(0.36, _ReviewsListCard(barberUid: _uid)),
          const SizedBox(height: 20),
        ],
        _section(0.44, _AchievementsCard(stats: stats)),
      ],
    );
  }
}

// ── Rank card ─────────────────────────────────────────────────────

class _RankCard extends StatelessWidget {
  final _Stats stats;
  const _RankCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rank = _getRank(stats.xp);
    final rankIndex = _ranks.indexOf(rank);
    final nextRank = rankIndex < _ranks.length - 1
        ? _ranks[rankIndex + 1]
        : null;
    final progress = _getRankProgress(stats.xp);
    final toNext = nextRank != null
        ? nextRank.minXp - stats.xp
        : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            rank.color.withValues(alpha: 0.18),
            AppColors.surfaceElevated,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rank.color.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Icono de rango
          Text(rank.icon, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 8),
          Text(
            rank.name,
            style: AppTextStyles.display(
              size: 22,
              weight: FontWeight.w700,
            ).copyWith(color: rank.color),
          ),
          const SizedBox(height: 4),
          Text(
            nextRank != null
                ? '$toNext XP para ${nextRank.name}'
                : '¡Rango máximo alcanzado!',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 18),
          // Barra de progreso animada
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: progress),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: AppColors.borderMedium,
                      valueColor: AlwaysStoppedAnimation(rank.color),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${rank.minXp} XP',
                        style: AppTextStyles.caption,
                      ),
                      Text(
                        '${stats.xp} XP',
                        style: AppTextStyles.caption.copyWith(
                          color: rank.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        nextRank != null ? '${nextRank.minXp} XP' : 'Máx.',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final _Stats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final acceptPct = (stats.acceptanceRate * 100).round();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          icon: Icons.check_circle_rounded,
          iconColor: AppColors.teal,
          label: 'Completadas',
          animValue: stats.completed,
          display: '${stats.completed}',
        ),
        _StatCard(
          icon: Icons.star_rounded,
          iconColor: AppColors.gold,
          label: 'Valoración',
          animValue: stats.ratingCount > 0 ? (stats.rating * 10).round() : 0,
          display: stats.ratingCount > 0
              ? '${stats.rating.toStringAsFixed(1)}★'
              : '—',
          animateTo: stats.ratingCount > 0 ? (stats.rating * 10).round() : 0,
          divisor: stats.ratingCount > 0 ? 10.0 : null,
          suffix: stats.ratingCount > 0 ? '★' : '',
        ),
        _StatCard(
          icon: Icons.calendar_month_rounded,
          iconColor: AppColors.success,
          label: 'Este mes',
          animValue: stats.thisMonth,
          display: '${stats.thisMonth}',
        ),
        _StatCard(
          icon: Icons.verified_rounded,
          iconColor: AppColors.warning,
          label: 'Aceptación',
          animValue: acceptPct,
          display: '$acceptPct%',
          suffix: '%',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int animValue;
  final String display;
  final double? divisor;
  final String? suffix;
  final int? animateTo;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.animValue,
    required this.display,
    this.divisor,
    this.suffix,
    this.animateTo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: iconColor, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: animValue),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOut,
                builder: (context, v, _) {
                  final text = divisor != null
                      ? '${(v / divisor!).toStringAsFixed(1)}${suffix ?? ''}'
                      : '$v${suffix ?? ''}';
                  return Text(
                    text,
                    style: AppTextStyles.display(
                      size: 22,
                      weight: FontWeight.w700,
                    ),
                  );
                },
              ),
              const SizedBox(height: 2),
              Text(label, style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Actividad semanal ─────────────────────────────────────────────

class _ActivityChart extends StatelessWidget {
  final _Stats stats;
  const _ActivityChart({required this.stats});

  static const _labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final maxVal = [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ].map((d) => stats.byWeekday[d] ?? 0).fold(0, max);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.bar_chart_rounded,
            title: 'Actividad semanal',
          ),
          const SizedBox(height: 16),
          // Área de barras (altura fija) — etiquetas en Row separado abajo
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final weekday = i + 1;
                final count = stats.byWeekday[weekday] ?? 0;
                final ratio = maxVal > 0 ? count / maxVal : 0.0;
                final isToday = DateTime.now().weekday == weekday;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (count > 0)
                        Text(
                          '$count',
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 3),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: ratio),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOut,
                        builder: (context, value, _) {
                          return Container(
                            height: max(4.0, value * 72),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: isToday
                                  ? AppColors.gold
                                  : AppColors.gold.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          // Etiquetas de días en Row independiente — sin riesgo de overflow
          Row(
            children: List.generate(7, (i) {
              final isToday = DateTime.now().weekday == i + 1;
              return Expanded(
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: isToday ? AppColors.gold : AppColors.textTertiary,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            'Basado en tus citas completadas · hoy resaltado',
            style: AppTextStyles.caption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Servicios populares ───────────────────────────────────────────

class _ServicesCard extends StatelessWidget {
  final _Stats stats;
  const _ServicesCard({required this.stats});

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final sorted = stats.byService.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final maxVal = top.isEmpty ? 1 : top.first.value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.content_cut_rounded,
            title: 'Servicios populares',
          ),
          const SizedBox(height: 14),
          ...List.generate(top.length, (i) {
            final entry = top[i];
            final ratio = maxVal > 0 ? entry.value / maxVal : 0.0;
            final medal = i < 3 ? _medals[i] : '  ';
            final barColor = i == 0
                ? AppColors.gold
                : i == 1
                ? AppColors.textSecondary
                : AppColors.textTertiary;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(medal, style: const TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                entry.key,
                                style: AppTextStyles.body,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${entry.value} ${entry.value == 1 ? 'vez' : 'veces'}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: ratio),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOut,
                          builder: (context, value, _) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 6,
                                backgroundColor: AppColors.borderMedium,
                                valueColor: AlwaysStoppedAnimation(barColor),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Valoraciones ──────────────────────────────────────────────────

class _RatingsCard extends StatelessWidget {
  final _Stats stats;
  const _RatingsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final maxDist = stats.ratingDist.values.fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.star_rounded, title: 'Valoraciones'),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Promedio grande
              Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: stats.rating),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: AppTextStyles.display(
                          size: 44,
                          weight: FontWeight.w700,
                        ).copyWith(color: AppColors.gold),
                      );
                    },
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: i < stats.rating.round()
                            ? AppColors.gold
                            : AppColors.borderMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.ratingCount} reseñas',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              const SizedBox(width: 20),
              // Distribución
              Expanded(
                child: Column(
                  children: List.generate(5, (i) {
                    final star = 5 - i;
                    final count = stats.ratingDist[star] ?? 0;
                    final ratio = maxDist > 0 ? count / maxDist : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text(
                            '$star',
                            style: AppTextStyles.label.copyWith(fontSize: 11),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.star_rounded,
                            size: 11,
                            color: AppColors.gold,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: ratio),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOut,
                              builder: (context, value, _) {
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: value,
                                    minHeight: 8,
                                    backgroundColor: AppColors.borderMedium,
                                    valueColor: const AlwaysStoppedAnimation(
                                      AppColors.gold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 18,
                            child: Text(
                              '$count',
                              style: AppTextStyles.label.copyWith(fontSize: 11),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Lista de reseñas con nombre del cliente ───────────────────────

class _ReviewsListCard extends StatefulWidget {
  final String barberUid;
  const _ReviewsListCard({required this.barberUid});

  @override
  State<_ReviewsListCard> createState() => _ReviewsListCardState();
}

class _ReviewsListCardState extends State<_ReviewsListCard> {
  List<_Review> _reviews = [];
  bool _loading = true;
  static const _previewCount = 4;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.barberUid)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();

      final reviews = <_Review>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        String clientName = d['clientName'] as String? ?? '';
        if (clientName.isEmpty) {
          try {
            final userSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(doc.id)
                .get();
            clientName = userSnap.data()?['name'] as String? ?? 'Cliente';
          } catch (_) {
            clientName = 'Cliente';
          }
        }
        reviews.add(_Review(
          clientUid: doc.id,
          clientName: clientName,
          rating: (d['rating'] as num?)?.toDouble() ?? 0,
          comment: d['comment'] as String? ?? '',
          createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));
      }

      if (mounted) setState(() { _reviews = reviews; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAllReviews() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllReviewsSheet(reviews: _reviews),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _reviews.take(_previewCount).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.rate_review_rounded,
            title: 'Reseñas de clientes',
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
              ),
            )
          else if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Sin reseñas aún.', style: AppTextStyles.caption),
            )
          else ...[
            ...preview.map((r) => _ReviewItemCard(review: r)),
            if (_reviews.length > _previewCount) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _showAllReviews,
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: Text('Ver más (${_reviews.length - _previewCount} más)'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Tarjeta individual de reseña ──────────────────────────────────

class _ReviewItemCard extends StatelessWidget {
  final _Review review;
  const _ReviewItemCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final initial = review.clientName.isNotEmpty
        ? review.clientName[0].toUpperCase()
        : 'C';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.teal.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: AppTextStyles.display(size: 15).copyWith(color: AppColors.teal),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.clientName,
                      style: AppTextStyles.ui(size: 13, weight: FontWeight.w600),
                    ),
                    Text(
                      '${review.createdAt.day}/${review.createdAt.month}/${review.createdAt.year}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (j) => Icon(
                  j < review.rating.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 14,
                  color: AppColors.gold,
                )),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment, style: AppTextStyles.body),
          ],
        ],
      ),
    );
  }
}

// ── Bottom sheet con todas las reseñas ────────────────────────────

class _AllReviewsSheet extends StatelessWidget {
  final List<_Review> reviews;
  const _AllReviewsSheet({required this.reviews});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.rate_review_rounded, size: 18, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Text(
                    'Todas las reseñas (${reviews.length})',
                    style: AppTextStyles.subtitle.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.borderSubtle, height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: reviews.length,
                itemBuilder: (_, i) => _ReviewItemCard(review: reviews[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Logros ────────────────────────────────────────────────────────

class _AchievementsCard extends StatelessWidget {
  final _Stats stats;
  const _AchievementsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final unlockedCount = _achievements.where((a) => a.unlocked(stats)).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.emoji_events_rounded,
            title: 'Logros',
          ),
          const SizedBox(height: 4),
          Text(
            '$unlockedCount / ${_achievements.length} desbloqueados',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: _achievements.map((a) {
              final isUnlocked = a.unlocked(stats);
              return _AchievementBadge(
                achievement: a,
                isUnlocked: isUnlocked,
                stats: stats,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final _Achievement achievement;
  final bool isUnlocked;
  final _Stats stats;

  const _AchievementBadge({
    required this.achievement,
    required this.isUnlocked,
    required this.stats,
  });

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono grande
            Text(
              achievement.icon,
              style: TextStyle(
                fontSize: 52,
                color: isUnlocked ? null : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            // Título + estado
            Text(
              achievement.title,
              style: AppTextStyles.display(size: 18, weight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isUnlocked
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : AppColors.borderSubtle,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isUnlocked
                      ? AppColors.gold.withValues(alpha: 0.5)
                      : AppColors.borderMedium,
                ),
              ),
              child: Text(
                isUnlocked ? '✓ Desbloqueado' : '🔒 Bloqueado',
                style: AppTextStyles.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: isUnlocked ? AppColors.gold : AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Descripción (qué hacer)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Qué debo hacer?',
                    style: AppTextStyles.ui(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(achievement.description, style: AppTextStyles.body),
                  const SizedBox(height: 10),
                  Text(
                    'Progreso',
                    style: AppTextStyles.ui(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achievement.progress(stats),
                    style: AppTextStyles.ui(
                      size: 13,
                      weight: FontWeight.w600,
                      color: isUnlocked ? AppColors.gold : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cerrar',
              style: AppTextStyles.ui(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: isUnlocked
              ? AppColors.gold.withValues(alpha: 0.10)
              : AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnlocked
                ? AppColors.gold.withValues(alpha: 0.50)
                : AppColors.borderSubtle,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isUnlocked
                ? Text(achievement.icon, style: const TextStyle(fontSize: 30))
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        achievement.icon,
                        style: TextStyle(
                          fontSize: 30,
                          color: AppColors.textTertiary.withValues(alpha: 0.15),
                        ),
                      ),
                      const Icon(
                        Icons.lock_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
            const SizedBox(height: 6),
            Text(
              achievement.title,
              style: AppTextStyles.label.copyWith(
                fontSize: 10,
                color: isUnlocked
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
                fontWeight: isUnlocked ? FontWeight.w600 : FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared header ─────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.gold),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.subtitle.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
