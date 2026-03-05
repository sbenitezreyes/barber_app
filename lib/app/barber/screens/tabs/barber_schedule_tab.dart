import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../client_route_screen.dart';

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
  double? _barberLat;
  double? _barberLng;

  @override
  void initState() {
    super.initState();
    _loadBarberLocation();
  }

  Future<void> _loadBarberLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
      final loc = doc.data()?['location'];
      if (loc != null && mounted) {
        setState(() {
          _barberLat = (loc['lat'] as num?)?.toDouble();
          _barberLng = (loc['lng'] as num?)?.toDouble();
        });
      }
    } catch (_) {}
  }

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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClientRouteScreen(
          appointmentId: apptId,
          clientName: appt.clientName,
          clientLat: appt.clientLat!,
          clientLng: appt.clientLng!,
        ),
      ));
    }
  }

  Future<void> _confirmReject(String apptId, String clientName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF18181C),
        title: const Text('Rechazar cita'),
        content: Text('¿Rechazar la cita de $clientName?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Rechazar', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) await _setStatus(apptId, 'rejected');
  }

  //  Helpers 
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<_Appt> _forDay(List<_Appt> all, DateTime day) => all
      .where((a) =>
          (a.status == 'confirmed' || a.status == 'completed') &&
          _isSameDay(a.scheduledAt, day))
      .toList();

  List<_Appt> _pending(List<_Appt> all) =>
      all.where((a) => a.status == 'pending').toList();

  //  Build 
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_Appt>>(
      stream: _stream,
      builder: (context, snap) {
        final appointments = snap.data ?? [];
        final pending = _pending(appointments);
        final forDay = _forDay(appointments, _selectedDay);
        final theme = Theme.of(context);

        return Column(
          children: [
            //  Solicitudes pendientes 
            if (pending.isNotEmpty) ...[
              _SectionHeader(
                label: 'Solicitudes pendientes    ',
                color: Colors.orangeAccent,
              ),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: pending.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _PendingCard(
                    appt: pending[i],
                    barberLat: _barberLat,
                    barberLng: _barberLng,
                    onAccept: () => _setStatus(pending[i].id, 'confirmed', pending[i]),
                    onReject: () => _confirmReject(pending[i].id, pending[i].clientName),
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
            ],

            //  Calendario 
            Container(
              color: const Color(0xFF111217),
              child: TableCalendar<_Appt>(
                locale: 'es_ES',
                firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
                lastDay: DateTime.utc(DateTime.now().year + 1, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (d) => _isSameDay(d, _selectedDay),
                eventLoader: (day) => _forDay(appointments, day),
                onDaySelected: (sel, foc) =>
                    setState(() { _selectedDay = sel; _focusedDay = foc; }),
                onPageChanged: (foc) => setState(() => _focusedDay = foc),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  todayDecoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  weekendTextStyle: const TextStyle(color: Colors.white70),
                  defaultTextStyle: const TextStyle(color: Colors.white),
                  outsideTextStyle: TextStyle(color: Colors.grey[700]!),
                  todayTextStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  selectedTextStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  markerSize: 5,
                  markersMaxCount: 3,
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  leftChevronIcon:
                      const Icon(Icons.chevron_left, color: Colors.white70),
                  rightChevronIcon:
                      const Icon(Icons.chevron_right, color: Colors.white70),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle:
                      TextStyle(color: Colors.grey[400]!, fontSize: 12),
                  weekendStyle:
                      TextStyle(color: Colors.grey[400]!, fontSize: 12),
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
        );
      },
    );
  }
}

//  Tarjeta de solicitud pendiente 
class _PendingCard extends StatelessWidget {
  final _Appt appt;
  final double? barberLat;
  final double? barberLng;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _PendingCard(
      {required this.appt,
      this.barberLat,
      this.barberLng,
      required this.onAccept,
      required this.onReject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = appt.isImmediate
        ? 'Ahora mismo'
        : DateFormat('EEE d MMM, HH:mm', 'es').format(appt.scheduledAt);

    return Container(
      width: 230,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Client + time
          Row(children: [
            const Icon(Icons.person, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
            Expanded(
              child: Text(appt.clientName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 4),
          Text(appt.serviceName,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.schedule, size: 12, color: Colors.orangeAccent),
            const SizedBox(width: 4),
            Expanded(
              child: Text(timeLabel,
                  style:
                      const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '\$${appt.servicePrice.toStringAsFixed(0)} \u00b7 ${appt.serviceDuration} min',
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          // Distance chip
          if (appt.clientLat != null &&
              appt.clientLng != null &&
              barberLat != null &&
              barberLng != null)
            Builder(builder: (_) {
              final meters = _haversineMeters(
                  barberLat!, barberLng!, appt.clientLat!, appt.clientLng!);
              final km = meters / 1000;
              final distLabel = km < 1
                  ? '${(km * 1000).round()} m'
                  : '${km.toStringAsFixed(1)} km';
              final walkMin = (meters / 83).round();   // ~5 km/h
              final motoMin = (meters / 667).round();  // ~40 km/h
              return Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.location_on,
                          size: 10, color: Colors.lightBlueAccent),
                      const SizedBox(width: 2),
                      Text(distLabel,
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 10)),
                    ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.directions_walk,
                          size: 10, color: Colors.lightBlueAccent),
                      const SizedBox(width: 2),
                      Text(walkMin < 1 ? '< 1 min' : '~$walkMin min',
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 10)),
                    ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.two_wheeler,
                          size: 10, color: Colors.lightBlueAccent),
                      const SizedBox(width: 2),
                      Text(motoMin < 1 ? '< 1 min' : '~$motoMin min',
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 10)),
                    ]),
                  ],
                ),
              );
            }),
          const Spacer(),
          // Accept / Reject buttons
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Rechazar', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Aceptar', style: TextStyle(fontSize: 11)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

//  Lista de citas del día 
class _DayList extends StatelessWidget {
  final List<_Appt> appts;
  final DateTime selectedDay;
  final ValueChanged<String> onMarkCompleted;
  const _DayList(
      {required this.appts,
      required this.selectedDay,
      required this.onMarkCompleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat("EEEE d 'de' MMMM", 'es').format(selectedDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Text(
              _capitalize(dateLabel),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const Spacer(),
            if (appts.isNotEmpty)
              Text(
                ' cita',
                style:
                    TextStyle(color: theme.colorScheme.primary, fontSize: 13),
              ),
          ]),
        ),
        Expanded(
          child: appts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_available,
                          size: 48, color: Colors.grey[700]),
                      const SizedBox(height: 10),
                      Text('Sin citas confirmadas',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 14)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: appts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ApptCard(
                      appt: appts[i],
                      onMarkCompleted: () => onMarkCompleted(appts[i].id)),
                ),
        ),
      ],
    );
  }
}

//  Tarjeta de cita confirmada/completada 
class _ApptCard extends StatelessWidget {
  final _Appt appt;
  final VoidCallback onMarkCompleted;
  const _ApptCard({required this.appt, required this.onMarkCompleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (appt.status) {
      case 'completed':
        statusColor = Colors.greenAccent;
        statusLabel = 'Completada';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'rejected':
        statusColor = Colors.redAccent;
        statusLabel = 'Rechazada';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = theme.colorScheme.primary;
        statusLabel = 'Confirmada';
        statusIcon = Icons.event_available;
    }

    final timeStr = appt.isImmediate
        ? 'Inmediata'
        : DateFormat('HH:mm', 'es').format(appt.scheduledAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: statusColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Hora
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(timeStr,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Icon(statusIcon, color: statusColor, size: 16),
            const SizedBox(width: 4),
            Text(statusLabel,
                style: TextStyle(color: statusColor, fontSize: 12)),
            const Spacer(),
            // "Marcar completada" menu
            if (appt.status == 'confirmed')
              GestureDetector(
                onTap: onMarkCompleted,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: const [
                    Icon(Icons.check, size: 13, color: Colors.greenAccent),
                    SizedBox(width: 4),
                    Text('Completada',
                        style: TextStyle(
                            color: Colors.greenAccent, fontSize: 11)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF2A2A30),
              child: Icon(Icons.person, size: 16, color: Colors.white54),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appt.clientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(
                    '${appt.serviceName}  \u00b7  \$${appt.servicePrice.toStringAsFixed(0)}  \u00b7  ${appt.serviceDuration} min',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

//  Section header 
class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      color: color.withValues(alpha: 0.08),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

double _haversineMeters(
    double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * asin(sqrt(a));
}
