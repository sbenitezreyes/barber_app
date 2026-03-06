import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _subscribeAppointments();
  }

  @override
  void dispose() {
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
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _allAppointments =
            snap.docs.map((d) => _ClientAppointment.fromDoc(d)).toList()
              ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
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
    final theme = Theme.of(context);
    final now = DateTime.now();
    
    // Verificar si el usuario es invitado
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    if (isGuest) {
      return const GuestAuthPrompt(
        title: 'Gestiona tus citas',
        subtitle: 'Inicia sesión para ver y administrar tus citas agendadas',
        icon: Icons.calendar_today_outlined,
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // ── Calendario ──
        Container(
          color: const Color(0xFF111217),
          child: TableCalendar<_ClientAppointment>(
            locale: 'es_ES',
            firstDay: DateTime.utc(now.year - 1, 1, 1),
            lastDay: DateTime.utc(now.year + 1, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getForDay,
            onDaySelected: _onDaySelected,
            onPageChanged: (focused) =>
                setState(() => _focusedDay = focused),
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

        // ── Citas del día seleccionado ──
        Expanded(
          child: Builder(builder: (context) {
            final selected = _selectedDay ?? now;
            final appointments = _getForDay(selected);
            final dateLabel =
                DateFormat("EEEE d 'de' MMMM", 'es').format(selected);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        _capitalize(dateLabel),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const Spacer(),
                      if (appointments.isNotEmpty)
                        Text(
                          '${appointments.length} cita${appointments.length != 1 ? 's' : ''}',
                          style: TextStyle(
                              color: theme.colorScheme.primary, fontSize: 13),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: appointments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_available,
                                  size: 48, color: Colors.grey[700]),
                              const SizedBox(height: 10),
                              Text(
                                'Sin citas este día',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: appointments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _AppointmentCard(appointment: appointments[i]),
                        ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ── Tarjeta de cita ──────────────────────────────────────────────
class _AppointmentCard extends StatelessWidget {
  final _ClientAppointment appointment;
  const _AppointmentCard({required this.appointment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (appointment.status) {
      case 'completed':
        statusColor = Colors.greenAccent;
        statusLabel = 'Completada';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'cancelled':
        statusColor = Colors.redAccent;
        statusLabel = 'Cancelada';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = theme.colorScheme.primary;
        statusLabel = appointment.isImmediate ? 'Inmediata' : 'Próxima';
        statusIcon = Icons.schedule;
    }

    final timeLabel = appointment.isImmediate
        ? 'Ahora mismo'
        : DateFormat('hh:mm a').format(appointment.scheduledAt);

    // ¿El barbero está en camino ahora mismo?
    // Mostramos tan pronto como la cita es confirmed + immediate
    // (no esperamos a que barberCurrentLat esté disponible)
    final barberOnWay = appointment.isImmediate &&
        appointment.status == 'confirmed';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181C),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: barberOnWay ? Colors.blueAccent : statusColor,
            width: 3,
          ),
        ),
      ),
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
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appointment.serviceName,
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(
                          timeLabel,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (barberOnWay ? Colors.blueAccent : statusColor)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      barberOnWay ? Icons.two_wheeler : statusIcon,
                      size: 13,
                      color: barberOnWay ? Colors.blueAccent : statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      barberOnWay ? 'En camino' : statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              barberOnWay ? Colors.blueAccent : statusColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Botón de tracking en vivo (solo cuando el barbero está en camino)
          if (barberOnWay) ...[  
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.location_on, size: 16),
                label: const Text('Ver barbero en tiempo real',
                    style: TextStyle(fontSize: 13)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BarberTrackingScreen(
                    appointmentId: appointment.id,
                    barberName: appointment.barberName,
                  ),
                )),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}