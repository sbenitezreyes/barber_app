import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/app_theme.dart';
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

class _BarberHomeScreenState extends State<BarberHomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 1; // Iniciar en Agenda
  final _notificationRefreshController = StreamController<void>.broadcast();
  late final Stream<int> _notificationCountStream;
  StreamSubscription? _firestoreSubscription;
  StreamSubscription? _refreshSubscription;

  static const _tabTitles = ['Agenda', 'Configuración', 'Perfil'];

  @override
  void initState() {
    super.initState();
    
    // Escuchar cambios en el ciclo de vida de la app
    WidgetsBinding.instance.addObserver(this);
    
    // Inicializar stream del badge
    _notificationCountStream = _createNotificationCountStream();
    
    // Arrancar el servicio GPS de fondo (tracking de citas en tiempo real)
    BarberGpsService.instance.start();    // Init FCM (token saving, foreground notifications, tap routing)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmService.instance.init(context: context);
    });
    // Listen for notification taps → switch to Agenda tab (index 1)
    scheduleTabRequested.addListener(_onScheduleTabRequested);    
    // Listen for new notifications → refresh badge
    notificationReceived.addListener(_onNotificationReceived);
    // Emitir evento inicial para que se calcule el contador al inicio
    Future.microtask(() => _notificationRefreshController.add(null));  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    // Cuando la app vuelve a resumed (foreground), refrescar el badge
    if (state == AppLifecycleState.resumed) {
      print('🔄 [BarberHomeScreen] App volvió a foreground, refrescando badge');
      
      // Revisar si hay notificaciones nuevas desde background
      final prefs = await SharedPreferences.getInstance();
      final hasNew = prefs.getBool('hasNewNotification') ?? false;
      if (hasNew) {
        print('✅ [BarberHomeScreen] Detectada notificación nueva, limpiando flag');
        await prefs.setBool('hasNewNotification', false);
      }
      
      _notificationRefreshController.add(null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scheduleTabRequested.removeListener(_onScheduleTabRequested);
    notificationReceived.removeListener(_onNotificationReceived);
    _firestoreSubscription?.cancel();
    _refreshSubscription?.cancel();
    _notificationRefreshController.close();
    super.dispose();
  }

  void _onScheduleTabRequested() {
    if (mounted) setState(() => _currentIndex = 1);
  }

  void _onNotificationReceived() {
    // Refrescar el badge cuando llega una notificación
    print('🔔 [BarberHomeScreen] Notificación recibida, refrescando badge');
    _notificationRefreshController.add(null);
  }

  // Stream de notificaciones que requieren atención (pending + cancelled recientes)
  // excluye las que ya fueron vistas
  Stream<int> _createNotificationCountStream() {
    final controller = StreamController<int>.broadcast();
    
    // Helper para calcular y emitir el contador
    Future<void> emitCount() async {
      print('🔢 [BarberHomeScreen] Recalculando contador de badge...');
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
      
      print('✅ [BarberHomeScreen] Contador actualizado: $unviewedCount notificaciones');
      
      if (!controller.isClosed) {
        controller.add(unviewedCount);
      }
    }
    
    // Escuchar cambios en Firestore
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('appointments')
        .where('barberUid',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
        .snapshots()
        .listen((_) {
          print('📊 [BarberHomeScreen] Cambio detectado en Firestore');
          emitCount();
        });
    
    // Escuchar refresh manual
    _refreshSubscription = _notificationRefreshController.stream
        .listen((_) {
          print('🔄 [BarberHomeScreen] Refresh manual del badge');
          emitCount();
        });
    
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

  void _openHistoryPanel(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HistoryPanel(uid: uid),
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

  @override
  Widget build(BuildContext context) {
    final firstName = (FirebaseAuth.instance.currentUser?.displayName ?? 'Barbero').split(' ').first;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: _currentIndex == 0
            ? RichText(
                text: TextSpan(children: [
                  TextSpan(
                    text: 'Hola, ',
                    style: GoogleFonts.figtree(fontSize: 18, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
                  ),
                  TextSpan(
                    text: firstName,
                    style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ]),
              )
            : Text(
                _tabTitles[_currentIndex - 1],
                style: GoogleFonts.figtree(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
        centerTitle: _currentIndex != 0,
        actions: [
          if (_currentIndex == 1)
            IconButton(
              icon: const Icon(Icons.history_rounded, size: 22),
              color: AppColors.textSecondary,
              onPressed: () => _openHistoryPanel(context),
              tooltip: 'Ver historial',
            ),
          StreamBuilder<int>(
            stream: _notificationCountStream,
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, size: 22),
                    color: AppColors.textPrimary,
                    onPressed: () => _openNotificationsPanel(context),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
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
              return _ActiveRouteBanner(
                clientName: clientName,
                onTap: clientLat == null || clientLng == null
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('El cliente no compartió su ubicación GPS')),
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
                      backgroundColor: AppColors.surfaceElevated,
                      title: Text('Cancelar cita', style: AppTextStyles.title),
                      content: Text('¿Cancelar la cita con $clientName?', style: AppTextStyles.body),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('No'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('Sí, cancelar', style: AppTextStyles.button.copyWith(color: AppColors.error)),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await FirebaseFirestore.instance
                      .collection('appointments')
                      .doc(doc.id)
                      .update({
                        'status': 'cancelled',
                        'cancelledBy': FirebaseAuth.instance.currentUser?.uid,
                      });
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Mapa',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Agenda',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Configuración',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
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
                                    final cancelledBy = d['cancelledBy'] as String?;
                                    final ts =
                                        d['createdAt'] as Timestamp?;
                                    final dt =
                                        ts?.toDate() ?? DateTime.now();
                                    final timeAgo = _timeAgo(dt);

                                    Color statusColor;
                                    IconData statusIcon;
                                    String statusLabel;
                                    String displayText;
                                    
                                    switch (status) {
                                      case 'confirmed':
                                        statusColor = Colors.greenAccent;
                                        statusIcon =
                                            Icons.check_circle_outline;
                                        statusLabel = 'Confirmada';
                                        displayText = '$statusLabel · $clientName';
                                        break;
                                      case 'rejected':
                                        statusColor = Colors.redAccent;
                                        statusIcon = Icons.cancel_outlined;
                                        statusLabel = 'Rechazada';
                                        displayText = '$statusLabel · $clientName';
                                        break;
                                      case 'cancelled':
                                        statusColor = Colors.redAccent;
                                        statusIcon = Icons.event_busy;
                                        // Si el barbero canceló, mostrar mensaje personalizado
                                        if (cancelledBy == widget.uid) {
                                          statusLabel = 'Cancelada';
                                          displayText = 'Haz cancelado la cita a: $clientName';
                                        } else {
                                          // El cliente canceló
                                          statusLabel = 'Cancelada';
                                          displayText = '$clientName canceló la cita';
                                        }
                                        break;
                                      default:
                                        statusColor =
                                            theme.colorScheme.primary;
                                        statusIcon =
                                            Icons.task_alt_rounded;
                                        statusLabel = 'Completada';
                                        displayText = '$statusLabel · $clientName';
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
                                                  displayText,
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

// ── Panel de historial de citas ────────────────────────────────────
class _HistoryPanel extends StatelessWidget {
  final String uid;
  const _HistoryPanel({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('barberUid', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        
        final pastAppointments = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String?;
          final scheduledAt = (data['scheduledAt'] as Timestamp?)?.toDate();
          
          if (scheduledAt == null) return false;
          
          final apptDate = DateTime(
            scheduledAt.year,
            scheduledAt.month,
            scheduledAt.day,
          );
          
          return apptDate.isBefore(today) &&
              (status == 'completed' || status == 'confirmed');
        }).toList();

        // Ordenar por fecha descendente
        pastAppointments.sort((a, b) {
          final aDate = ((a.data() as Map<String, dynamic>)['scheduledAt'] as Timestamp).toDate();
          final bDate = ((b.data() as Map<String, dynamic>)['scheduledAt'] as Timestamp).toDate();
          return bDate.compareTo(aDate);
        });

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: Colors.white70),
                    const SizedBox(width: 10),
                    const Text(
                      'Historial de citas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${pastAppointments.length} citas',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Lista
              Expanded(
                child: pastAppointments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history, size: 64, color: Colors.grey[700]),
                            const SizedBox(height: 16),
                            Text(
                              'No hay citas en el historial',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: pastAppointments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final doc = pastAppointments[i];
                          final data = doc.data() as Map<String, dynamic>;
                          return _HistoryApptCard(data: data);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Tarjeta de cita en el historial ────────────────────────────────
class _HistoryApptCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HistoryApptCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String?;
    final clientName = data['clientName'] as String? ?? 'Cliente';
    final serviceName = data['serviceName'] as String? ?? '';
    final servicePrice = (data['servicePrice'] as num?)?.toDouble() ?? 0.0;
    final serviceDuration = (data['serviceDuration'] as int?) ?? 0;
    final scheduledAt = (data['scheduledAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final isImmediate = data['isImmediate'] as bool? ?? false;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = Colors.greenAccent;
        statusLabel = 'Completada';
        statusIcon = Icons.check_circle;
        break;
      case 'confirmed':
        statusColor = Colors.orangeAccent;
        statusLabel = 'No completada';
        statusIcon = Icons.warning_amber_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = 'Desconocido';
        statusIcon = Icons.help_outline;
    }

    final dateStr = DateFormat("d 'de' MMMM, yyyy", 'es').format(scheduledAt);
    final timeStr = isImmediate ? 'Inmediata' : DateFormat('HH:mm', 'es').format(scheduledAt);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111217),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fecha y estado
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[400]),
              const SizedBox(width: 6),
              Text(
                _capitalizeFirst(dateStr),
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Cliente
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF2A2A30),
                child: Icon(Icons.person, size: 18, color: Colors.grey[300]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serviceName,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Detalles
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    timeStr,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    '$serviceDuration min',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_money, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    '\$${servicePrice.toStringAsFixed(0)}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _capitalizeFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

