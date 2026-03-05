import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ── Modelo de horario por día ────────────────────────────────────
class DaySchedule {
  final String name;
  final String shortName;
  bool enabled;
  TimeOfDay openTime;
  TimeOfDay closeTime;

  DaySchedule({
    required this.name,
    required this.shortName,
    this.enabled = false,
    TimeOfDay? openTime,
    TimeOfDay? closeTime,
  })  : openTime = openTime ?? const TimeOfDay(hour: 8, minute: 0),
        closeTime = closeTime ?? const TimeOfDay(hour: 18, minute: 0);
}

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

  Future<void> _loadSchedule() async {
    try {
      final snap = await _userDoc.get();
      final data = snap.data();
      if (data != null && data['schedule'] is Map) {
        final saved = Map<String, dynamic>.from(data['schedule'] as Map);
        setState(() {
          for (final day in _schedule) {
            final key = _dayKey(day.name);
            if (saved.containsKey(key)) {
              final d = Map<String, dynamic>.from(saved[key] as Map);
              day.enabled = d['enabled'] == true;
              if (d['open'] is String) {
                final parts = (d['open'] as String).split(':');
                day.openTime = TimeOfDay(
                  hour: int.parse(parts[0]),
                  minute: int.parse(parts[1]),
                );
              }
              if (d['close'] is String) {
                final parts = (d['close'] as String).split(':');
                day.closeTime = TimeOfDay(
                  hour: int.parse(parts[0]),
                  minute: int.parse(parts[1]),
                );
              }
            }
          }
        });
      }
    } catch (_) {
      // Si no hay datos guardados, usamos valores por defecto
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickTime(
    DaySchedule day,
    bool isOpen,
  ) async {
    final initial = isOpen ? day.openTime : day.closeTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: Theme.of(ctx).colorScheme.primary,
                surface: const Color(0xFF18181C),
              ),
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF1A1A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    // Validar que hora de cierre sea posterior a apertura
    if (!isOpen) {
      final openMinutes = day.openTime.hour * 60 + day.openTime.minute;
      final closeMinutes = picked.hour * 60 + picked.minute;
      if (closeMinutes <= openMinutes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La hora de cierre debe ser posterior a la apertura'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    } else {
      final openMinutes = picked.hour * 60 + picked.minute;
      final closeMinutes = day.closeTime.hour * 60 + day.closeTime.minute;
      if (openMinutes >= closeMinutes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La hora de apertura debe ser anterior al cierre'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    setState(() {
      if (isOpen) {
        day.openTime = picked;
      } else {
        day.closeTime = picked;
      }
      _hasChanges = true;
    });
  }

  Future<void> _saveSchedule() async {
    final Map<String, dynamic> scheduleData = {};
    for (final day in _schedule) {
      scheduleData[_dayKey(day.name)] = {
        'enabled': day.enabled,
        'open': '${day.openTime.hour}:${day.openTime.minute.toString().padLeft(2, '0')}',
        'close': '${day.closeTime.hour}:${day.closeTime.minute.toString().padLeft(2, '0')}',
      };
    }

    try {
      await _userDoc.set({'schedule': scheduleData}, SetOptions(merge: true));
      if (mounted) {
        setState(() => _hasChanges = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Horario guardado correctamente'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeDays = _schedule.where((d) => d.enabled).length;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Horario laboral'),
        centerTitle: true,
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saveSchedule,
              child: Text(
                'Guardar',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Resumen ──
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    activeDays == 0
                        ? 'No tienes días laborables configurados'
                        : '$activeDays día${activeDays != 1 ? 's' : ''} laborable${activeDays != 1 ? 's' : ''} por semana',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'Visible en mapa',
                  style: TextStyle(
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // ── Lista de días ──
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  onPickOpen: () => _pickTime(day, true),
                  onPickClose: () => _pickTime(day, false),
                  formatTime: _formatTime,
                );
              },
            ),
          ),

          // ── Botón guardar ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveSchedule,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _hasChanges ? 'Guardar cambios' : 'Guardado',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
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
  final VoidCallback onPickOpen;
  final VoidCallback onPickClose;
  final String Function(TimeOfDay) formatTime;

  const _DayTile({
    required this.day,
    required this.onToggle,
    required this.onPickOpen,
    required this.onPickClose,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeekend = day.shortName == 'S' || day.shortName == 'D';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: day.enabled
            ? const Color(0xFF18181C)
            : const Color(0xFF111114),
        borderRadius: BorderRadius.circular(12),
        border: day.enabled
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              )
            : Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          // Fila principal
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Inicial del día
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: day.enabled
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : Colors.white12,
                  ),
                  child: Center(
                    child: Text(
                      day.shortName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: day.enabled
                            ? theme.colorScheme.primary
                            : isWeekend
                                ? Colors.grey[500]
                                : Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nombre
                Expanded(
                  child: Text(
                    day.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: day.enabled ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
                // Toggle
                Switch(
                  value: day.enabled,
                  onChanged: onToggle,
                  activeThumbColor: theme.colorScheme.primary,
                  activeTrackColor:
                      theme.colorScheme.primary.withValues(alpha: 0.4),
                  inactiveThumbColor: Colors.grey[600],
                  inactiveTrackColor: Colors.white12,
                ),
              ],
            ),
          ),

          // Horarios (solo si está activo)
          if (day.enabled) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  // Apertura
                  Expanded(
                    child: _TimeButton(
                      label: 'Apertura',
                      time: formatTime(day.openTime),
                      icon: Icons.wb_sunny_outlined,
                      color: Colors.amber,
                      onTap: onPickOpen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.arrow_forward,
                      size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 10),
                  // Cierre
                  Expanded(
                    child: _TimeButton(
                      label: 'Cierre',
                      time: formatTime(day.closeTime),
                      icon: Icons.nights_stay_outlined,
                      color: Colors.blueAccent,
                      onTap: onPickClose,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
