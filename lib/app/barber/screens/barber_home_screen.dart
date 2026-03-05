import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/fcm_service.dart';
import '../services/gps_service.dart';
import 'client_route_screen.dart';
import 'tabs/barber_home_tab.dart';
import 'tabs/barber_schedule_tab.dart';
import 'tabs/barber_settings_tab.dart';
import 'tabs/barber_profile_tab.dart';

class BarberHomeScreen extends StatefulWidget {
  const BarberHomeScreen({super.key});

  @override
  State<BarberHomeScreen> createState() => _BarberHomeScreenState();
}

class _BarberHomeScreenState extends State<BarberHomeScreen> {
  int _currentIndex = 0;
  final _notificationRefreshController = StreamController<void>.broadcast();

  static const _tabTitles = ['Agenda', 'ConfiguraciÃ³n', 'Perfil'];

  @override
  void initState() {
    super.initState();    // Arrancar el servicio GPS de fondo (tracking de citas en tiempo real)
    BarberGpsService.instance.start();    // Init FCM (token saving, foreground notifications, tap routing)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmService.instance.init(context: context);
    });
    // Listen for notification taps â†’ switch to Agenda tab (index 1)
    scheduleTabRequested.addListener(_onScheduleTabRequested);    
    // Emitir evento inicial para que se calcule el contador al inicio
    Future.microtask(() => _notificationRefreshController.add(null));  }

  @override
  void dispose() {
    scheduleTabRequested.removeListener(_onScheduleTabRequested);
    _notificationRefreshController.close();
    super.dispose();
  }

  void _onScheduleTabRequested() {
    if (mounted) setState(() => _currentIndex = 1);
  }

  // Stream de notificaciones que requieren atención (pending + cancelled recientes)
  // excluye las que ya fueron vistas
  Stream<int> get _notificationCountStream {
    final controller = StreamController<int>.broadcast();
    
    // Helper para calcular y emitir el contador
    Future<void> emitCount() async {
      final prefs = await SharedPreferences.getInstance();
      final viewedIds = prefs.getStringList('viewedNotifications') ?? [];
      
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('barberUid',
              isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .get();

      final oneDayAgo = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 1)));
      
      final unviewedCount = snap.docs.where((d) {
        // Si ya fue vista, no contar
        if (viewedIds.contains(d.id)) return false;
        
        final data = d.data();
        final status = data['status'] as String?;
        final createdAt = data['createdAt'] as Timestamp?;
        
        // Incluir pending + cancelled de las últimas 24h
        return status == 'pending' ||
            (status == 'cancelled' &&
                createdAt != null &&
                createdAt.compareTo(oneDayAgo) >= 0);
      }).length;
      
      if (!controller.isClosed) {
        controller.add(unviewedCount);
      }
    }
    
    // Escuchar cambios en Firestore
    final firestoreSubscription = FirebaseFirestore.instance
        .collection('appointments')
        .where('barberUid',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
        .snapshots()
        .listen((_) => emitCount());
    
    // Escuchar refresh manual
    final refreshSubscription = _notificationRefreshController.stream
        .listen((_) => emitCount());
    
    // Cleanup cuando se cancele
    controller.onCancel = () {
      firestoreSubscription.cancel();
      refreshSubscription.cancel();
      controller.close();
    };
    
    // Emitir contador inicial
    emitCount();
    
    return controller.stream;
  }

  // Solo 2 filtros (barberUid + status) para evitar índice compuesto en Firestore.
  // El filtro isImmediate se aplica en Dart.
  Stream<List<QueryDocumentSnapshot>> get _activeRouteStream =>
      FirebaseFirestore.instance
          .collection('appointments')
          .where('barberUid',
              isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
          .where('status', isEqualTo: 'confirmed')
          .snapshots()
          .map((s) => s.docs
              .where((d) => d.data()['isImmediate'] == true)
              .toList());

  void _openNotificationsPanel(BuildContext context) async {
    // Marcar todas las notificaciones actuales como vistas
    await _markNotificationsAsViewed();
    
    // Forzar refresh del contador
    _notificationRefreshController.add(null);
    
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationsPanel(
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
    );
  }

  Future<void> _markNotificationsAsViewed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('barberUid', isEqualTo: uid)
          .get();

      final oneDayAgo = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 1)));

      final notificationIds = snap.docs.where((d) {
        final data = d.data();
        final status = data['status'] as String?;
        final createdAt = data['createdAt'] as Timestamp?;
        
        return status == 'pending' ||
            (status == 'cancelled' &&
                createdAt != null &&
                createdAt.compareTo(oneDayAgo) >= 0);
      }).map((d) => d.id).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('viewedNotifications', notificationIds);
    } catch (_) {}
  }

  final _tabs = const [
    BarberHomeTab(),
    BarberScheduleTab(),
    BarberSettingsTab(),
    BarberProfileTab(),
  ];

  String _appBarTitle() {
    if (_currentIndex == 0) {
      final fullName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Barbero';
      final firstName = fullName.split(' ').first;
      return 'Hola, $firstName';
    }
    return _tabTitles[_currentIndex - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle()),
        centerTitle: _currentIndex != 0,
        actions: [
          StreamBuilder<int>(
            stream: _notificationCountStream,
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => _openNotificationsPanel(context),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$count',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner: retomar ruta activa si el barb volvio a abrir la app
          StreamBuilder<List<QueryDocumentSnapshot>>(
            stream: _activeRouteStream,
            builder: (context, snap) {
              final docs = snap.data ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              final doc = docs.first;
              final d = doc.data() as Map<String, dynamic>;
              final clientName = d['clientName'] as String? ?? 'Cliente';
              final clientLat = (d['clientLat'] as num?)?.toDouble();
              final clientLng = (d['clientLng'] as num?)?.toDouble();
              // Si el cliente no compartíó GPS el botón se muestra de todas formas
              // pero solo abre el mapa si hay coordenadas
              return _ActiveRouteBanner(
                clientName: clientName,
                onTap: clientLat == null || clientLng == null
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'El cliente no compartió su ubicación GPS'),
                            duration: Duration(seconds: 3),
                          ),
                        )
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ClientRouteScreen(
                            appointmentId: doc.id,
                            clientName: clientName,
                            clientLat: clientLat,
                            clientLng: clientLng,
                          ),
                        )),
                onCancel: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF18181C),
                      title: const Text('Cancelar cita'),
                      content: Text(
                          '¿Cancelar la cita con $clientName?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('No'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Sí, cancelar',
                              style:
                                  TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await FirebaseFirestore.instance
                      .collection('appointments')
                      .doc(doc.id)
                      .update({'status': 'cancelled'});
                },
              );
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _tabs,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF111217),
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey[600],
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Agenda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'ConfiguraciÃ³n',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Centro de notificaciones â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _NotificationsPanel extends StatefulWidget {
  final String uid;
  const _NotificationsPanel({required this.uid});

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
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
          .doc(widget.uid)
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

  Future<void> _setStatus(
    BuildContext context,
    String id,
    String status,
    String clientName, {
    bool isImmediate = false,
    double? clientLat,
    double? clientLng,
  }) async {
    if (status == 'rejected') {
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
                child: const Text('Rechazar',
                    style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(id)
        .update({'status': status});
    if (status == 'confirmed' &&
        isImmediate &&
        clientLat != null &&
        clientLng != null &&
        mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClientRouteScreen(
          appointmentId: id,
          clientName: clientName,
          clientLat: clientLat,
          clientLng: clientLng,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sevenDaysAgo =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where('barberUid', isEqualTo: widget.uid)
              .snapshots(),
          builder: (context, snap) {
            // â”€â”€ Separar por categorÃ­a â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            final allDocs = snap.data?.docs ?? [];
            final pending = allDocs
                .where((d) => (d.data() as Map)['status'] == 'pending')
                .toList();
            final recent = allDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final status = data['status'] as String? ?? '';
              final ts = data['createdAt'] as Timestamp?;
              if (ts == null) return false;
              return (status == 'confirmed' ||
                      status == 'rejected' ||
                      status == 'completed' ||
                      status == 'cancelled') &&
                  ts.compareTo(sevenDaysAgo) >= 0;
            }).toList()
              ..sort((a, b) {
                final ta =
                    ((a.data() as Map)['createdAt'] as Timestamp?)?.seconds ??
                        0;
                final tb =
                    ((b.data() as Map)['createdAt'] as Timestamp?)?.seconds ??
                        0;
                return tb.compareTo(ta); // mÃ¡s recientes primero
              });

            final totalCount = pending.length + recent.length;

            return Column(
              children: [
                // â”€â”€ Handle + header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    const Icon(Icons.notifications_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    const Text('Notificaciones',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (totalCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$totalCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.white12),

                // â”€â”€ Contenido â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                Expanded(
                  child: !snap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : totalCount == 0
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_none,
                                      size: 56, color: Colors.grey[700]),
                                  const SizedBox(height: 12),
                                  Text('Sin notificaciones',
                                      style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 15)),
                                ],
                              ),
                            )
                          : ListView(
                              controller: controller,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              children: [
                                // â”€â”€ SecciÃ³n: Solicitudes pendientes
                                if (pending.isNotEmpty) ...[
                                  _SectionLabel(
                                    icon: Icons.schedule_rounded,
                                    label:
                                        'Solicitudes pendientes  â€¢  ${pending.length}',
                                    color: Colors.orangeAccent,
                                  ),
                                  const SizedBox(height: 8),
                                  ...pending.map((doc) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    final id = doc.id;
                                    final clientName =
                                        d['clientName'] ?? 'Cliente';
                                    final serviceName =
                                        d['serviceName'] ?? '';
                                    final price =
                                        (d['servicePrice'] ?? 0).toDouble();
                                    final duration =
                                        (d['serviceDuration'] ?? 0) as int;
                                    final isImmediate =
                                        d['isImmediate'] ?? false;
                                    final ts =
                                        d['scheduledAt'] as Timestamp?;
                                    final dt =
                                        ts?.toDate() ?? DateTime.now();
                                    final timeLabel = isImmediate
                                        ? 'Ahora mismo'
                                        : DateFormat('EEE d MMM, HH:mm',
                                                'es')
                                            .format(dt);

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF111217),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                              color: Colors.orangeAccent
                                                  .withValues(alpha: 0.4)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              const CircleAvatar(
                                                radius: 18,
                                                backgroundColor:
                                                    Color(0xFF2A2A30),
                                                child: Icon(Icons.person,
                                                    size: 18,
                                                    color: Colors.white54),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(clientName,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600,
                                                            fontSize: 14)),
                                                    Text(serviceName,
                                                        style: TextStyle(
                                                            color: Colors
                                                                .grey[400],
                                                            fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.orangeAccent
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(timeLabel,
                                                    style: const TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontSize: 11)),
                                              ),
                                            ]),
                                            const SizedBox(height: 6),
                                            Text(
                                              '\$$price Â· $duration min',
                                              style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 12),
                                            ),                                            // Distance chip
                                            Builder(builder: (_) {
                                              final cLat = (d['clientLat'] as num?)?.toDouble();
                                              final cLng = (d['clientLng'] as num?)?.toDouble();
                                              if (cLat == null ||
                                                  cLng == null ||
                                                  _barberLat == null ||
                                                  _barberLng == null) {
                                                return const SizedBox.shrink();
                                              }
                                              final meters = _haversineMeters(
                                                  _barberLat!, _barberLng!, cLat, cLng);
                                              final km = meters / 1000;
                                              final distLabel = km < 1
                                                  ? '${(km * 1000).round()} m'
                                                  : '${km.toStringAsFixed(1)} km';
                                              final walkMin = (meters / 83).round();   // ~5 km/h
                                              final motoMin = (meters / 667).round();  // ~40 km/h
                                              return Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 3,
                                                  children: [
                                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                                      const Icon(Icons.location_on,
                                                          size: 11, color: Colors.lightBlueAccent),
                                                      const SizedBox(width: 3),
                                                      Text(distLabel,
                                                          style: const TextStyle(
                                                              color: Colors.lightBlueAccent, fontSize: 11)),
                                                    ]),
                                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                                      const Icon(Icons.directions_walk,
                                                          size: 11, color: Colors.lightBlueAccent),
                                                      const SizedBox(width: 3),
                                                      Text(walkMin < 1 ? '< 1 min' : '~$walkMin min',
                                                          style: const TextStyle(
                                                              color: Colors.lightBlueAccent, fontSize: 11)),
                                                    ]),
                                                    Row(mainAxisSize: MainAxisSize.min, children: [
                                                      const Icon(Icons.two_wheeler,
                                                          size: 11, color: Colors.lightBlueAccent),
                                                      const SizedBox(width: 3),
                                                      Text(motoMin < 1 ? '< 1 min' : '~$motoMin min',
                                                          style: const TextStyle(
                                                              color: Colors.lightBlueAccent, fontSize: 11)),
                                                    ]),
                                                  ],
                                                ),
                                              );
                                            }),                                            const SizedBox(height: 12),
                                            Row(children: [
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  icon: const Icon(Icons.close,
                                                      size: 15),
                                                  label: const Text('Rechazar'),
                                                  onPressed: () => _setStatus(
                                                      context,
                                                      id,
                                                      'rejected',
                                                      clientName),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.redAccent,
                                                    side: const BorderSide(
                                                        color:
                                                            Colors.redAccent),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  icon: const Icon(Icons.check,
                                                      size: 15),
                                                  label: const Text('Aceptar'),
                                                  onPressed: () => _setStatus(
                                                      context,
                                                      id,
                                                      'confirmed',
                                                      clientName,
                                                      isImmediate: isImmediate as bool,
                                                      clientLat: (d['clientLat'] as num?)?.toDouble(),
                                                      clientLng: (d['clientLng'] as num?)?.toDouble()),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: theme
                                                        .colorScheme.primary,
                                                    foregroundColor:
                                                        Colors.black,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                  ),
                                                ),
                                              ),
                                            ]),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
                                ],

                                // â”€â”€ SecciÃ³n: Actividad reciente
                                if (recent.isNotEmpty) ...[
                                  if (pending.isNotEmpty)
                                    const SizedBox(height: 6),
                                  _SectionLabel(
                                    icon: Icons.history_rounded,
                                    label: 'Actividad reciente',
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(height: 8),
                                  ...recent.map((doc) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    final clientName =
                                        d['clientName'] ?? 'Cliente';
                                    final serviceName =
                                        d['serviceName'] ?? '';
                                    final status =
                                        d['status'] as String? ?? '';
                                    final ts =
                                        d['createdAt'] as Timestamp?;
                                    final dt =
                                        ts?.toDate() ?? DateTime.now();
                                    final timeAgo = _timeAgo(dt);

                                    Color statusColor;
                                    IconData statusIcon;
                                    String statusLabel;
                                    switch (status) {
                                      case 'confirmed':
                                        statusColor = Colors.greenAccent;
                                        statusIcon =
                                            Icons.check_circle_outline;
                                        statusLabel = 'Confirmada';
                                        break;
                                      case 'rejected':
                                        statusColor = Colors.redAccent;
                                        statusIcon = Icons.cancel_outlined;
                                        statusLabel = 'Rechazada';
                                        break;
                                      case 'cancelled':
                                        statusColor = Colors.redAccent;
                                        statusIcon = Icons.event_busy;
                                        statusLabel = 'Cancelada';
                                        break;
                                      default:
                                        statusColor =
                                            theme.colorScheme.primary;
                                        statusIcon =
                                            Icons.task_alt_rounded;
                                        statusLabel = 'Completada';
                                    }

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF111217),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border(
                                            left: BorderSide(
                                                color: statusColor, width: 3),
                                          ),
                                        ),
                                        child: Row(children: [
                                          Icon(statusIcon,
                                              color: statusColor, size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '$statusLabel Â· $clientName',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13),
                                                ),
                                                Text(serviceName,
                                                    style: TextStyle(
                                                        color: Colors.grey[400],
                                                        fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                          Text(timeAgo,
                                              style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 11)),
                                        ]),
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} dÃ­as';
  }
}
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
// â”€â”€ Etiqueta de secciÃ³n â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionLabel(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Banner retomar ruta activa ────────────────────────────────────
class _ActiveRouteBanner extends StatelessWidget {
  final String clientName;
  final VoidCallback onTap;
  final Future<void> Function()? onCancel;
  const _ActiveRouteBanner(
      {required this.clientName,
      required this.onTap,
      this.onCancel});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ruta activa · $clientName',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                  const Text(
                    'Toca para retomar la navegación',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (onCancel != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onCancel!(),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }
}
