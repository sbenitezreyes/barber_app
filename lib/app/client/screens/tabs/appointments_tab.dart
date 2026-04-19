import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../shared/theme/app_theme.dart';
import '../barber_tracking_screen.dart';
import '../../../shared/guest_auth_prompt.dart';

// ── Modelo de cita del cliente ───────────────────────────────────
class _ClientAppointment {
  final String id;
  final String barberName;
  final String serviceName;
  final DateTime scheduledAt;
  final bool isImmediate;
  final String status;
  final double? barberCurrentLat;
  final double? barberCurrentLng;

  const _ClientAppointment({
    required this.id,
    required this.barberName,
    required this.serviceName,
    required this.scheduledAt,
    required this.isImmediate,
    required this.status,
    this.barberCurrentLat,
    this.barberCurrentLng,
  });

  factory _ClientAppointment.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return _ClientAppointment(
      id: doc.id,
      barberName: d['barberName'] ?? 'Barbero',
      serviceName: d['serviceName'] ?? 'Servicio',
      scheduledAt: (d['scheduledAt'] as Timestamp).toDate(),
      isImmediate: d['isImmediate'] == true,
      status: d['status'] ?? 'pending',
      barberCurrentLat: (d['barberCurrentLat'] as num?)?.toDouble(),
      barberCurrentLng: (d['barberCurrentLng'] as num?)?.toDouble(),
    );
  }
}

// ── Tab principal ────────────────────────────────────────────────
class AppointmentsTab extends StatefulWidget {
  const AppointmentsTab({super.key});

  @override
  State<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<AppointmentsTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<_ClientAppointment> _allAppointments = [];
  bool _loading = true;
  StreamSubscription<QuerySnapshot>? _sub;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    // Re-suscribir cuando cambia el usuario (ej: invitado → real)
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        _sub?.cancel();
        _subscribeAppointments();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _subscribeAppointments() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _sub = FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _allAppointments =
                  snap.docs.map((d) => _ClientAppointment.fromDoc(d)).toList()
                    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
              _loading = false;
            });
          },
          onError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
      case 'rejected':
        return AppColors.error;
      case 'confirmed':
      case 'en_servicio':
        return AppColors.teal;
      default: // pending
        return AppColors.gold;
    }
  }

  List<_ClientAppointment> _getForDay(DateTime day) {
    return _allAppointments.where((a) {
      final d = a.scheduledAt;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Verificar si el usuario es invitado
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    if (isGuest) {
      return _GuestDemoAppointments(
        focusedDay: _focusedDay,
        selectedDay: _selectedDay ?? now,
        onDaySelected: _onDaySelected,
      );
    }

    if (_loading) {
      return const _SkeletonLoader();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Calendario ──
        Container(
          color: AppColors.surface,
          child: TableCalendar<_ClientAppointment>(
            locale: 'es_ES',
            firstDay: DateTime.utc(now.year - 1, 1, 1),
            lastDay: DateTime.utc(now.year + 1, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getForDay,
            onDaySelected: _onDaySelected,
            onPageChanged: (focused) => setState(() => _focusedDay = focused),
            calendarStyle: AppCalendarStyles.calendarStyle,
            headerStyle: AppCalendarStyles.headerStyle,
            daysOfWeekStyle: AppCalendarStyles.daysOfWeekStyle,
            calendarBuilders: CalendarBuilders<_ClientAppointment>(
              markerBuilder: (context, day, appointments) {
                if (appointments.isEmpty) return const SizedBox.shrink();
                // Un punto por color único (máx 4)
                final colors = <Color>{};
                for (final a in appointments) {
                  colors.add(_statusColor(a.status));
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: colors.map((c) => Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  )).toList(),
                );
              },
            ),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),

        // ── Citas del día seleccionado ──
        Expanded(
          child: Builder(
            builder: (context) {
              final selected = _selectedDay ?? now;
              final appointments = _getForDay(selected);
              final dateLabel = DateFormat(
                "EEEE d 'de' MMMM",
                'es',
              ).format(selected);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          _capitalize(dateLabel),
                          style: AppTextStyles.ui(
                            size: 14,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (appointments.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.goldSubtle,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: AppColors.borderAccent),
                            ),
                            child: Text(
                              '${appointments.length} cita${appointments.length != 1 ? 's' : ''}',
                              style: AppTextStyles.ui(
                                size: 12,
                                weight: FontWeight.w600,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: appointments.isEmpty
                        ? LayoutBuilder(
                            builder: (_, constraints) => SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.surfaceElevated,
                                          border: Border.all(
                                            color: AppColors.borderSubtle,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.calendar_today_outlined,
                                          size: 24,
                                          color: AppColors.textTertiary
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Sin citas este día',
                                        style:
                                            AppTextStyles.display(
                                              size: 15,
                                              weight: FontWeight.w600,
                                            ).copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Selecciona otro día o reserva\ncon un barbero en el mapa',
                                        textAlign: TextAlign.center,
                                        style: AppTextStyles.ui(
                                          size: 12,
                                          color: AppColors.textTertiary,
                                        ).copyWith(height: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: appointments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) =>
                                _AppointmentCard(appointment: appointments[i]),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Vista demo de citas para invitados ───────────────────────────
class _GuestDemoAppointments extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;

  const _GuestDemoAppointments({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = DateFormat("EEEE d 'de' MMMM", 'es').format(selectedDay);
    final isToday = isSameDay(selectedDay, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Calendario funcional (solo navegación, sin datos reales)
        Container(
          color: AppColors.surface,
          child: TableCalendar<Object>(
            locale: 'es_ES',
            firstDay: DateTime.utc(now.year - 1, 1, 1),
            lastDay: DateTime.utc(now.year + 1, 12, 31),
            focusedDay: focusedDay,
            selectedDayPredicate: (day) => isSameDay(selectedDay, day),
            eventLoader: (day) => isSameDay(day, now) ? [Object()] : [],
            onDaySelected: onDaySelected,
            onPageChanged: (_) {},
            calendarStyle: AppCalendarStyles.calendarStyle,
            headerStyle: AppCalendarStyles.headerStyle,
            daysOfWeekStyle: AppCalendarStyles.daysOfWeekStyle,
          ),
        ),
        const Divider(color: Colors.white12, height: 1),

        // Lista de citas del día seleccionado
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Text(
                      _capitalize(dateLabel),
                      style: AppTextStyles.ui(
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (isToday)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.goldSubtle,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: AppColors.borderAccent),
                        ),
                        child: Text(
                          '1 cita',
                          style: AppTextStyles.ui(
                            size: 12,
                            weight: FontWeight.w600,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: isToday
                    ? ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [_DemoAppointmentCard(scheduledAt: now)],
                      )
                    : LayoutBuilder(
                        builder: (_, constraints) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.surfaceElevated,
                                      border: Border.all(
                                        color: AppColors.borderSubtle,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.calendar_today_outlined,
                                      size: 20,
                                      color: AppColors.textTertiary.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Sin citas este día',
                                    style: AppTextStyles.display(
                                      size: 14,
                                      weight: FontWeight.w600,
                                    ).copyWith(color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Inicia sesión para reservar\ncon un barbero',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.ui(
                                      size: 12,
                                      color: AppColors.textTertiary,
                                    ).copyWith(height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const GuestCtaBanner(message: 'Inicia sesión para gestionar tus citas'),
      ],
    );
  }
}

class _DemoAppointmentCard extends StatelessWidget {
  final DateTime scheduledAt;
  const _DemoAppointmentCard({required this.scheduledAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.gold,
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 130,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 11,
                        width: 90,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 70,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 13,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Próxima',
                        style: AppTextStyles.ui(
                          size: 11,
                          weight: FontWeight.w600,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton loading ─────────────────────────────────────────────
class _SkeletonLoader extends StatefulWidget {
  const _SkeletonLoader();
  @override
  State<_SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<_SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final op = 0.28 + (_anim.value * 0.32);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Esqueleto del calendario
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  // Header mes
                  Row(
                    children: [
                      _Bone(w: 22, h: 22, r: 6, op: op),
                      const Spacer(),
                      _Bone(w: 110, h: 16, op: op),
                      const Spacer(),
                      _Bone(w: 22, h: 22, r: 6, op: op),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Días de la semana
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      7,
                      (_) => _Bone(w: 26, h: 11, op: op),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Grid 5 semanas
                  ...List.generate(
                    5,
                    (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(
                          7,
                          (i) => _Bone(w: 30, h: 30, r: 15, op: op),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // Label fecha
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: _Bone(w: 150, h: 15, op: op),
            ),
            // Tarjetas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _CardBone(op: op),
                  const SizedBox(height: 8),
                  _CardBone(op: op),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Bone extends StatelessWidget {
  final double w, h, r, op;
  const _Bone({required this.w, required this.h, this.r = 6, required this.op});

  @override
  Widget build(BuildContext context) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated.withValues(alpha: op + 0.4),
      borderRadius: BorderRadius.circular(r),
      border: Border.all(color: AppColors.borderSubtle.withValues(alpha: op)),
    ),
  );
}

class _CardBone extends StatelessWidget {
  final double op;
  const _CardBone({required this.op});

  @override
  Widget build(BuildContext context) => Container(
    height: 80,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.borderSubtle.withValues(alpha: op)),
    ),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Bone(w: 120, h: 13, op: op),
              _Bone(w: 80, h: 11, op: op),
              _Bone(w: 60, h: 10, op: op),
            ],
          ),
        ),
        _Bone(w: 72, h: 28, r: 14, op: op),
      ],
    ),
  );
}

// ── Tarjeta de cita ──────────────────────────────────────────────
class _AppointmentCard extends StatefulWidget {
  final _ClientAppointment appointment;
  const _AppointmentCard({required this.appointment});

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _glow = Tween<double>(
      begin: 0.15,
      end: 0.55,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (appointment.status) {
      case 'completed':
        statusColor = AppColors.success;
        statusLabel = 'Completada';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        statusLabel = 'Cancelada';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        statusLabel = 'Rechazada';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'confirmed':
        statusColor = AppColors.teal;
        statusLabel = appointment.isImmediate ? 'Confirmada' : 'Confirmada';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'en_servicio':
        statusColor = AppColors.teal;
        statusLabel = 'En servicio';
        statusIcon = Icons.content_cut_rounded;
        break;
      default:
        statusColor = AppColors.gold;
        statusLabel = appointment.isImmediate ? 'Inmediata' : 'Próxima';
        statusIcon = Icons.schedule;
    }

    final timeLabel = appointment.isImmediate
        ? 'Ahora mismo'
        : DateFormat('hh:mm a').format(appointment.scheduledAt);

    final barberOnWay =
        appointment.isImmediate && appointment.status == 'confirmed';
    final effectiveColor = barberOnWay ? AppColors.teal : statusColor;

    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: barberOnWay
                ? AppColors.teal.withValues(alpha: _glow.value)
                : effectiveColor == AppColors.gold
                ? AppColors.borderAccent
                : AppColors.borderSubtle,
          ),
          boxShadow: barberOnWay
              ? [
                  BoxShadow(
                    color: AppColors.teal.withValues(alpha: _glow.value * 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Línea de acento superior según estado
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  effectiveColor,
                  Colors.transparent,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.barberName,
                            style: AppTextStyles.display(size: 15),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            appointment.serviceName,
                            style: AppTextStyles.ui(
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 13,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeLabel,
                                style: AppTextStyles.ui(
                                  size: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Badge de estado
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: effectiveColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: effectiveColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (barberOnWay)
                            AnimatedBuilder(
                              animation: _glow,
                              builder: (_, __) => Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.teal.withValues(
                                    alpha: _glow.value + 0.4,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          else
                            Icon(statusIcon, size: 13, color: effectiveColor),
                          const SizedBox(width: 6),
                          Text(
                            barberOnWay ? 'En camino' : statusLabel,
                            style: AppTextStyles.ui(
                              size: 11,
                              weight: FontWeight.w600,
                              color: effectiveColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Botón tracking en vivo
                if (barberOnWay) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.location_on, size: 16),
                      label: const Text(
                        'Ver barbero en tiempo real',
                        style: TextStyle(fontSize: 13),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BarberTrackingScreen(
                            appointmentId: appointment.id,
                            barberName: appointment.barberName,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                        foregroundColor: AppColors.teal,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                          side: BorderSide(
                            color: AppColors.teal.withValues(alpha: 0.4),
                          ),
                        ),
                        textStyle: AppTextStyles.ui(
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
