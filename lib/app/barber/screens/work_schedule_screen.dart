import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

// ── Modelos ──────────────────────────────────────────────────────

class TimeInterval {
  TimeOfDay open;
  TimeOfDay close;

  TimeInterval({required this.open, required this.close});

  int get openMinutes => open.hour * 60 + open.minute;
  int get closeMinutes => close.hour * 60 + close.minute;

  Map<String, String> toMap() => {'open': _fmt(open), 'close': _fmt(close)};

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static TimeInterval fromMap(Map<String, dynamic> m) => TimeInterval(
    open: _parse(m['open'] as String),
    close: _parse(m['close'] as String),
  );
}

class DaySchedule {
  final String name;
  final String shortName;
  bool enabled;
  List<TimeInterval> intervals;

  DaySchedule({
    required this.name,
    required this.shortName,
    this.enabled = false,
    List<TimeInterval>? intervals,
  }) : intervals =
           intervals ??
           [
             TimeInterval(
               open: const TimeOfDay(hour: 8, minute: 0),
               close: const TimeOfDay(hour: 18, minute: 0),
             ),
           ];
}

// ── Pantalla principal ───────────────────────────────────────────

class WorkScheduleScreen extends StatefulWidget {
  const WorkScheduleScreen({super.key});

  @override
  State<WorkScheduleScreen> createState() => _WorkScheduleScreenState();
}

class _WorkScheduleScreenState extends State<WorkScheduleScreen> {
  final List<DaySchedule> _schedule = [
    DaySchedule(name: 'Lunes', shortName: 'L', enabled: true),
    DaySchedule(name: 'Martes', shortName: 'M', enabled: true),
    DaySchedule(name: 'Miércoles', shortName: 'X', enabled: true),
    DaySchedule(name: 'Jueves', shortName: 'J', enabled: true),
    DaySchedule(name: 'Viernes', shortName: 'V', enabled: true),
    DaySchedule(name: 'Sábado', shortName: 'S', enabled: false),
    DaySchedule(name: 'Domingo', shortName: 'D', enabled: false),
  ];

  bool _hasChanges = false;
  bool _loading = true;

  DocumentReference<Map<String, dynamic>> get _userDoc {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  String _dayKey(String name) {
    const map = {
      'Lunes': 'monday',
      'Martes': 'tuesday',
      'Miércoles': 'wednesday',
      'Jueves': 'thursday',
      'Viernes': 'friday',
      'Sábado': 'saturday',
      'Domingo': 'sunday',
    };
    return map[name] ?? name.toLowerCase();
  }

  Future<void> _loadSchedule() async {
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        // Intentar desde caché primero (respuesta instantánea)
        snap = await _userDoc.get(const GetOptions(source: Source.cache));
      } catch (_) {
        // Si no hay caché, traer desde network
        snap = await _userDoc.get();
      }
      final data = snap.data();
      if (data != null && data['schedule'] is Map) {
        final saved = Map<String, dynamic>.from(data['schedule'] as Map);
        setState(() {
          for (final day in _schedule) {
            final key = _dayKey(day.name);
            if (!saved.containsKey(key)) continue;
            final d = Map<String, dynamic>.from(saved[key] as Map);
            day.enabled = d['enabled'] == true;

            // Nuevo formato: intervals[]
            if (d['intervals'] is List) {
              final raw = d['intervals'] as List;
              final parsed = raw
                  .whereType<Map>()
                  .map(
                    (m) => TimeInterval.fromMap(Map<String, dynamic>.from(m)),
                  )
                  .toList();
              if (parsed.isNotEmpty) day.intervals = parsed;
            }
            // Formato antiguo: open/close strings → convertir a 1 intervalo
            else if (d['open'] is String && d['close'] is String) {
              day.intervals = [
                TimeInterval(
                  open: TimeInterval._parse(d['open'] as String),
                  close: TimeInterval._parse(d['close'] as String),
                ),
              ];
            }
          }
        });
      }
    } catch (_) {
      // Si no hay datos, usamos valores por defecto
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSchedule() async {
    final Map<String, dynamic> scheduleData = {};
    for (final day in _schedule) {
      scheduleData[_dayKey(day.name)] = {
        'enabled': day.enabled,
        'intervals': day.intervals.map((i) => i.toMap()).toList(),
      };
    }
    try {
      await _userDoc.set({'schedule': scheduleData}, SetOptions(merge: true));
      if (mounted) {
        setState(() => _hasChanges = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Horario guardado correctamente'),
            backgroundColor: AppColors.gold,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al guardar. Intenta de nuevo.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ── Time picker con validación ────────────────────────────────

  Future<void> _pickTime(
    DaySchedule day,
    int intervalIndex,
    bool isOpen,
  ) async {
    final interval = day.intervals[intervalIndex];
    final initial = isOpen ? interval.open : interval.close;

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: AppColors.gold,
            surface: AppColors.surface,
          ),
          dialogTheme: const DialogThemeData(
            backgroundColor: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final pickedMin = picked.hour * 60 + picked.minute;

    if (isOpen) {
      if (pickedMin >= interval.closeMinutes) {
        _showError('La apertura debe ser anterior al cierre');
        return;
      }
      // Verificar solapamiento con otros intervalos
      if (_overlapsOthers(
        day,
        intervalIndex,
        pickedMin,
        interval.closeMinutes,
      )) {
        _showError('Este intervalo se solapa con otro');
        return;
      }
      setState(() {
        interval.open = picked;
        _sortIntervals(day);
        _hasChanges = true;
      });
    } else {
      if (pickedMin <= interval.openMinutes) {
        _showError('El cierre debe ser posterior a la apertura');
        return;
      }
      if (_overlapsOthers(
        day,
        intervalIndex,
        interval.openMinutes,
        pickedMin,
      )) {
        _showError('Este intervalo se solapa con otro');
        return;
      }
      setState(() {
        interval.close = picked;
        _sortIntervals(day);
        _hasChanges = true;
      });
    }
  }

  bool _overlapsOthers(
    DaySchedule day,
    int skipIndex,
    int openMin,
    int closeMin,
  ) {
    for (int i = 0; i < day.intervals.length; i++) {
      if (i == skipIndex) continue;
      final other = day.intervals[i];
      // Solapamiento si los rangos se cruzan
      if (openMin < other.closeMinutes && closeMin > other.openMinutes) {
        return true;
      }
    }
    return false;
  }

  void _sortIntervals(DaySchedule day) {
    day.intervals.sort((a, b) => a.openMinutes.compareTo(b.openMinutes));
  }

  void _addInterval(DaySchedule day) {
    // Proponer inicio justo después del último cierre + 30 min
    final lastClose = day.intervals
        .map((i) => i.closeMinutes)
        .reduce((a, b) => a > b ? a : b);
    final newOpenMin = lastClose + 30;
    final newCloseMin = newOpenMin + 120; // 2h por defecto

    if (newCloseMin > 23 * 60 + 59) {
      _showError('No hay espacio para más franjas en el día');
      return;
    }
    setState(() {
      day.intervals.add(
        TimeInterval(
          open: TimeOfDay(hour: newOpenMin ~/ 60, minute: newOpenMin % 60),
          close: TimeOfDay(hour: newCloseMin ~/ 60, minute: newCloseMin % 60),
        ),
      );
      _hasChanges = true;
    });
  }

  void _removeInterval(DaySchedule day, int index) {
    if (day.intervals.length <= 1) return;
    setState(() {
      day.intervals.removeAt(index);
      _hasChanges = true;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeDays = _schedule.where((d) => d.enabled).length;

    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Horario laboral',
          style: AppTextStyles.ui(size: 18, weight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saveSchedule,
              child: Text(
                'Guardar',
                style: AppTextStyles.ui(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.gold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Resumen ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.goldSubtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  color: AppColors.gold,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    activeDays == 0
                        ? 'No tienes días laborables configurados'
                        : '$activeDays día${activeDays != 1 ? 's' : ''} laborable${activeDays != 1 ? 's' : ''} por semana',
                    style: AppTextStyles.ui(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Lista de días ──
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _schedule.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final day = _schedule[i];
                return _DayTile(
                  day: day,
                  onToggle: (val) => setState(() {
                    day.enabled = val;
                    _hasChanges = true;
                  }),
                  onPickTime: (idx, isOpen) => _pickTime(day, idx, isOpen),
                  onAddInterval: () => _addInterval(day),
                  onRemoveInterval: (idx) => _removeInterval(day, idx),
                );
              },
            ),
          ),

          // ── Botón guardar ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _hasChanges ? _saveSchedule : null,
                  child: Text(
                    _hasChanges ? 'Guardar cambios' : 'Sin cambios',
                    style: AppTextStyles.button,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tile de un día ───────────────────────────────────────────────

class _DayTile extends StatelessWidget {
  final DaySchedule day;
  final ValueChanged<bool> onToggle;
  final void Function(int intervalIndex, bool isOpen) onPickTime;
  final VoidCallback onAddInterval;
  final void Function(int intervalIndex) onRemoveInterval;

  const _DayTile({
    required this.day,
    required this.onToggle,
    required this.onPickTime,
    required this.onAddInterval,
    required this.onRemoveInterval,
  });

  String _fmt(TimeOfDay t) {
    final suffix = t.hour < 12 ? 'am' : 'pm';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final isWeekend = day.shortName == 'S' || day.shortName == 'D';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: day.enabled ? AppColors.surface : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: day.enabled ? AppColors.borderAccent : AppColors.borderSubtle,
        ),
      ),
      child: Column(
        children: [
          // ── Encabezado del día ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: day.enabled
                        ? AppColors.goldSubtle
                        : AppColors.surfaceElevated,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    day.shortName,
                    style: AppTextStyles.ui(
                      size: 14,
                      weight: FontWeight.w700,
                      color: day.enabled
                          ? AppColors.gold
                          : isWeekend
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    day.name,
                    style: AppTextStyles.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      color: day.enabled
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Switch(
                  value: day.enabled,
                  onChanged: onToggle,
                  activeThumbColor: AppColors.gold,
                  activeTrackColor: AppColors.goldSubtle,
                  inactiveThumbColor: AppColors.textTertiary,
                  inactiveTrackColor: AppColors.surfaceElevated,
                ),
              ],
            ),
          ),

          // ── Franjas horarias (solo si está activo) ──
          if (day.enabled) ...[
            const Divider(color: AppColors.borderSubtle, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                children: [
                  // Lista de intervalos
                  for (int i = 0; i < day.intervals.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _IntervalRow(
                      interval: day.intervals[i],
                      canRemove: day.intervals.length > 1,
                      fmt: _fmt,
                      onPickOpen: () => onPickTime(i, true),
                      onPickClose: () => onPickTime(i, false),
                      onRemove: () => onRemoveInterval(i),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Botón agregar franja
                  GestureDetector(
                    onTap: onAddInterval,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Agregar franja horaria',
                            style: AppTextStyles.ui(
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Fila de un intervalo ─────────────────────────────────────────

class _IntervalRow extends StatelessWidget {
  final TimeInterval interval;
  final bool canRemove;
  final String Function(TimeOfDay) fmt;
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;
  final VoidCallback onRemove;

  const _IntervalRow({
    required this.interval,
    required this.canRemove,
    required this.fmt,
    required this.onPickOpen,
    required this.onPickClose,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Hora apertura
        Expanded(
          child: _TimeChip(
            time: fmt(interval.open),
            icon: Icons.wb_sunny_outlined,
            color: AppColors.gold,
            onTap: onPickOpen,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.arrow_forward_rounded,
            size: 14,
            color: AppColors.textTertiary,
          ),
        ),
        // Hora cierre
        Expanded(
          child: _TimeChip(
            time: fmt(interval.close),
            icon: Icons.nights_stay_outlined,
            color: AppColors.teal,
            onTap: onPickClose,
          ),
        ),
        // Botón eliminar
        if (canRemove) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withValues(alpha: 0.1),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.redAccent,
              ),
            ),
          ),
        ] else
          const SizedBox(width: 38), // espacio para alinear cuando no hay botón
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String time;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TimeChip({
    required this.time,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              time,
              style: AppTextStyles.ui(
                size: 14,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
