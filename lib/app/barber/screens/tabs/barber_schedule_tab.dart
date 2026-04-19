import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../client_route_screen.dart';
import '../../../shared/theme/app_theme.dart';

//  Modelo
class _Appt {
  final String id;
  final String clientName;
  final String clientUid;
  final String serviceName;
  final int serviceDuration;
  final double servicePrice;
  final bool isImmediate;
  final DateTime scheduledAt;
  final String status; // pending | confirmed | rejected | completed
  final double? clientLat;
  final double? clientLng;
  final bool barberDeparting;

  const _Appt({
    required this.id,
    required this.clientName,
    required this.clientUid,
    required this.serviceName,
    required this.serviceDuration,
    required this.servicePrice,
    required this.isImmediate,
    required this.scheduledAt,
    required this.status,
    this.clientLat,
    this.clientLng,
    this.barberDeparting = false,
  });

  factory _Appt.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['scheduledAt'] as Timestamp?;
    return _Appt(
      id: doc.id,
      clientName: d['clientName'] ?? 'Cliente',
      clientUid: d['clientUid'] ?? '',
      serviceName: d['serviceName'] ?? '',
      serviceDuration: (d['serviceDuration'] ?? 0) as int,
      servicePrice: (d['servicePrice'] ?? 0.0).toDouble(),
      isImmediate: d['isImmediate'] ?? false,
      scheduledAt: ts?.toDate() ?? DateTime.now(),
      status: d['status'] ?? 'pending',
      clientLat: (d['clientLat'] as num?)?.toDouble(),
      clientLng: (d['clientLng'] as num?)?.toDouble(),
      barberDeparting: d['barberDeparting'] as bool? ?? false,
    );
  }

  DateTime get dayKey =>
      DateTime.utc(scheduledAt.year, scheduledAt.month, scheduledAt.day);
}

//  Tab principal
class BarberScheduleTab extends StatefulWidget {
  const BarberScheduleTab({super.key});

  @override
  State<BarberScheduleTab> createState() => _BarberScheduleTabState();
}

class _BarberScheduleTabState extends State<BarberScheduleTab> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  //  Stream (sin orderBy para evitar índice compuesto)
  Stream<List<_Appt>> get _stream => FirebaseFirestore.instance
      .collection('appointments')
      .where('barberUid', isEqualTo: _uid)
      .snapshots()
      .map((s) {
        final list = s.docs.map(_Appt.fromDoc).toList();
        list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        return list;
      });

  //  Accept / Reject
  Future<void> _setStatus(String apptId, String status, [_Appt? appt]) async {
    if (status == 'confirmed') {
      HapticFeedback.mediumImpact();
    } else if (status == 'completed') {
      HapticFeedback.heavyImpact();
    }
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(apptId)
        .update({'status': status});
    if (status == 'confirmed' &&
        appt != null &&
        appt.isImmediate &&
        appt.clientLat != null &&
        appt.clientLng != null &&
        mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientRouteScreen(
            appointmentId: apptId,
            clientName: appt.clientName,
            clientLat: appt.clientLat!,
            clientLng: appt.clientLng!,
          ),
        ),
      );
    }
  }

  //  Helpers
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<_Appt> _forDay(List<_Appt> all, DateTime day) =>
      all.where((a) => _isSameDay(a.scheduledAt, day)).toList();

  static Color _markerColor(String status) {
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

  //  Build
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_Appt>>(
      stream: _stream,
      builder: (context, snap) {
        final appointments = snap.data ?? [];
        final forDay = _forDay(appointments, _selectedDay);

        return LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              //  Calendario
              Container(
                color: AppColors.surface,
                child: TableCalendar<_Appt>(
                  locale: 'es_ES',
                  firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
                  lastDay: DateTime.utc(DateTime.now().year + 1, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (d) => _isSameDay(d, _selectedDay),
                  eventLoader: (day) => _forDay(appointments, day),
                  onDaySelected: (sel, foc) => setState(() {
                    _selectedDay = sel;
                    _focusedDay = foc;
                  }),
                  onPageChanged: (foc) => setState(() => _focusedDay = foc),
                  calendarStyle: AppCalendarStyles.calendarStyle,
                  headerStyle: AppCalendarStyles.headerStyle,
                  daysOfWeekStyle: AppCalendarStyles.daysOfWeekStyle,
                  calendarBuilders: CalendarBuilders<_Appt>(
                    markerBuilder: (context, day, appts) {
                      if (appts.isEmpty) return const SizedBox.shrink();
                      final colors = <Color>{};
                      for (final a in appts) {
                        colors.add(_markerColor(a.status));
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

              //  Citas del día
              Expanded(
                child: _DayList(
                  appts: forDay,
                  selectedDay: _selectedDay,
                  onMarkCompleted: (id) => _setStatus(id, 'completed'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

//  Lista de citas del día
class _DayList extends StatelessWidget {
  final List<_Appt> appts;
  final DateTime selectedDay;
  final ValueChanged<String> onMarkCompleted;
  const _DayList({
    required this.appts,
    required this.selectedDay,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat("EEEE d 'de' MMMM", 'es').format(selectedDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(
                _capitalize(dateLabel),
                style: AppTextStyles.ui(size: 14, weight: FontWeight.w600),
              ),
              const Spacer(),
              if (appts.isNotEmpty)
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
                    '${appts.length} cita${appts.length != 1 ? 's' : ''}',
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
          child: appts.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                                  Icons.content_cut_rounded,
                                  size: 24,
                                  color: AppColors.textTertiary.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Sin citas este día',
                                style: AppTextStyles.display(
                                  size: 15,
                                  weight: FontWeight.w600,
                                ).copyWith(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Las citas confirmadas\naparecerán aquí',
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
                    );
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: appts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ApptCard(
                    appt: appts[i],
                    index: i,
                    onMarkCompleted: () => onMarkCompleted(appts[i].id),
                  ),
                ),
        ),
      ],
    );
  }
}

//  Tarjeta de cita confirmada/completada
class _ApptCard extends StatefulWidget {
  final _Appt appt;
  final VoidCallback onMarkCompleted;
  final int index;
  const _ApptCard({
    required this.appt,
    required this.onMarkCompleted,
    this.index = 0,
  });

  @override
  State<_ApptCard> createState() => _ApptCardState();
}

class _ApptCardState extends State<_ApptCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _canComplete = false;
  Timer? _enableTimer;
  final _tooltipKey = GlobalKey<TooltipState>();

  bool _showDepartButton = false;
  Timer? _departTimer;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
      if (mounted) _enter.forward();
    });
    _scheduleCompleteEnable();
    _scheduleDepartButton();
  }

  /// Activa el botón "Completar" exactamente cuando termina la cita.
  void _scheduleCompleteEnable() {
    final endTime = widget.appt.scheduledAt.add(
      Duration(minutes: widget.appt.serviceDuration),
    );
    final now = DateTime.now();
    if (now.isAfter(endTime)) {
      _canComplete = true;
    } else {
      final delay = endTime.difference(now);
      _enableTimer = Timer(delay, () {
        if (mounted) setState(() => _canComplete = true);
      });
    }
  }

  /// Muestra el botón "Salir ahora" 30 min antes de la cita.
  void _scheduleDepartButton() {
    final appt = widget.appt;
    if (appt.isImmediate || appt.status != 'confirmed' || appt.barberDeparting) return;
    final departTime = appt.scheduledAt.subtract(const Duration(minutes: 30));
    final now = DateTime.now();
    if (now.isAfter(departTime)) {
      _showDepartButton = true;
    } else {
      _departTimer = Timer(departTime.difference(now), () {
        if (mounted) setState(() => _showDepartButton = true);
      });
    }
  }

  /// Marca barberDeparting en Firestore y abre la pantalla de ruta.
  Future<void> _depart() async {
    final appt = widget.appt;
    if (appt.clientLat == null || appt.clientLng == null) return;
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(appt.id)
        .update({'barberDeparting': true});
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientRouteScreen(
          appointmentId: appt.id,
          clientName: appt.clientName,
          clientLat: appt.clientLat!,
          clientLng: appt.clientLng!,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(_ApptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-evaluar botón "Salir ahora" cuando la cita pasa a confirmada
    if (oldWidget.appt.status != 'confirmed' && widget.appt.status == 'confirmed') {
      _departTimer?.cancel();
      _showDepartButton = false;
      _scheduleDepartButton();
    }
  }

  @override
  void dispose() {
    _enableTimer?.cancel();
    _departTimer?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appt;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (appt.status) {
      case 'pending':
        statusColor = AppColors.gold;
        statusLabel = 'Pendiente';
        statusIcon = Icons.schedule_outlined;
        break;
      case 'confirmed':
        statusColor = AppColors.gold;
        statusLabel = 'Confirmada';
        statusIcon = Icons.event_available_outlined;
        break;
      case 'completed':
        statusColor = AppColors.success;
        statusLabel = 'Completada';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'en_servicio':
        statusColor = AppColors.teal;
        statusLabel = 'En servicio';
        statusIcon = Icons.content_cut_rounded;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        statusLabel = 'Rechazada';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'cancelled':
        statusColor = Colors.redAccent;
        statusLabel = 'Cancelada';
        statusIcon = Icons.do_not_disturb_on_outlined;
        break;
      case 'missed':
        statusColor = AppColors.error;
        statusLabel = 'Cita perdida';
        statusIcon = Icons.event_busy_outlined;
        break;
      default:
        statusColor = AppColors.gold;
        statusLabel = 'Desconocido';
        statusIcon = Icons.help_outline;
    }

    final timeStr = appt.isImmediate
        ? 'Inmediata'
        : DateFormat('HH:mm', 'es').format(appt.scheduledAt);
    final initial = appt.clientName.isNotEmpty
        ? appt.clientName[0].toUpperCase()
        : 'C';

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  (appt.status == 'confirmed' || appt.status == 'en_servicio')
                  ? AppColors.borderAccent
                  : AppColors.borderSubtle,
            ),
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
                      statusColor,
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
                        // Avatar con inicial del cliente (teal = cliente)
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: appt.status == 'completed'
                                  ? [
                                      AppColors.success.withValues(alpha: 0.5),
                                      AppColors.success.withValues(alpha: 0.2),
                                    ]
                                  : [
                                      AppColors.teal.withValues(alpha: 0.45),
                                      AppColors.teal.withValues(alpha: 0.18),
                                    ],
                            ),
                            border: Border.all(
                              color: appt.status == 'completed'
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : AppColors.teal.withValues(alpha: 0.3),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: AppTextStyles.display(size: 16).copyWith(
                              color: appt.status == 'completed'
                                  ? AppColors.success
                                  : AppColors.teal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appt.clientName,
                                style: AppTextStyles.display(size: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                appt.serviceName,
                                style: AppTextStyles.ui(
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Badge de estado
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 11, color: statusColor),
                              const SizedBox(width: 5),
                              Text(
                                statusLabel,
                                style: AppTextStyles.ui(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Botón "Salir ahora" / "En camino" / "Cita perdida" para citas programadas
                    if (!appt.isImmediate && appt.status == 'confirmed' && appt.clientLat != null) ...[
                      if (appt.barberDeparting)
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ClientRouteScreen(
                                appointmentId: appt.id,
                                clientName: appt.clientName,
                                clientLat: appt.clientLat!,
                                clientLng: appt.clientLng!,
                              ),
                            ),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: AppColors.teal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.navigation_rounded, size: 13, color: AppColors.teal),
                                const SizedBox(width: 6),
                                Text('En camino — Ver ruta',
                                    style: AppTextStyles.ui(size: 12, weight: FontWeight.w600, color: AppColors.teal)),
                              ],
                            ),
                          ),
                        )
                      else if (_showDepartButton && !_canComplete)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _depart,
                            icon: const Icon(Icons.navigation_rounded, size: 14),
                            label: const Text('Salir ahora'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.gold,
                              side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
                              backgroundColor: AppColors.goldSubtle,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              textStyle: AppTextStyles.ui(size: 13, weight: FontWeight.w700),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                    // Hora + precio + duración + botón completar
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_outlined,
                                size: 11,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeStr,
                                style: AppTextStyles.ui(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '\$${appt.servicePrice.toStringAsFixed(0)}',
                          style: AppTextStyles.ui(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.gold,
                          ),
                        ),
                        Text(
                          '  ·  ${appt.serviceDuration} min',
                          style: AppTextStyles.ui(
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const Spacer(),
                        if (appt.status == 'confirmed' ||
                            appt.status == 'en_servicio')
                          Tooltip(
                            key: _tooltipKey,
                            message: 'No puedes completar una cita que aún no ha terminado',
                            triggerMode: TooltipTriggerMode.manual,
                            preferBelow: false,
                            textStyle: AppTextStyles.ui(
                              size: 11,
                              color: Colors.white,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.borderSubtle,
                              ),
                            ),
                            child: OutlinedButton.icon(
                              onPressed: _canComplete
                                  ? widget.onMarkCompleted
                                  : () {
                                      _tooltipKey.currentState
                                          ?.ensureTooltipVisible();
                                    },
                              icon: Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: _canComplete
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                              ),
                              label: Text(
                                'Completar',
                                style: AppTextStyles.ui(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: _canComplete
                                      ? AppColors.success
                                      : AppColors.textTertiary,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _canComplete
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                                side: BorderSide(
                                  color: _canComplete
                                      ? AppColors.success.withValues(alpha: 0.4)
                                      : AppColors.borderSubtle,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                textStyle: AppTextStyles.ui(
                                  size: 11,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//  Section header
String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
