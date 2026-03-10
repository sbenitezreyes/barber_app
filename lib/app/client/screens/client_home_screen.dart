import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'barber_tracking_screen.dart';
import 'tabs/home_tab.dart';
import 'tabs/favorites_tab.dart';
import 'tabs/appointments_tab.dart';
import 'tabs/profile_tab.dart';
import 'welcome_dialog.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  int _currentIndex = 0;
  Stream<QuerySnapshot>? _notifStream;
  Stream<QuerySnapshot>? _trackingStream;
  Set<String> _seenIds = {};
  final _flnPlugin = FlutterLocalNotificationsPlugin();

  static const _tabs = [
    HomeTab(),
    FavoritesTab(),
    AppointmentsTab(),
    ProfileTab(),
  ];

  static const _titles = ['Favoritos', 'Mis citas', 'Perfil'];

  @override
  void initState() {
    super.initState();
    _initFcm();
    _initBadgeStream();
    
    // Mostrar diálogo de bienvenida si es la primera vez
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WelcomeDialog.showIfFirstTime(context);
    });
  }

  void _initBadgeStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Load previously seen IDs from local storage
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getStringList('client_seen_notif_ids') ?? [];
      if (mounted) setState(() => _seenIds = saved.toSet());
    });
    _notifStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: uid)
        .where('status', whereIn: ['confirmed', 'rejected', 'cancelled'])
        .snapshots();
    // Solo 2 filtros para evitar índice compuesto en Firestore.
    // El filtro isImmediate se aplica en el builder.
    _trackingStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: uid)
        .where('status', isEqualTo: 'confirmed')
        .snapshots();
    setState(() {});
  }

  Future<void> _markAllAsSeen(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    _seenIds.addAll(ids);
    await prefs.setStringList('client_seen_notif_ids', _seenIds.toList());
    if (mounted) setState(() {});
  }

  void _openNotificationsPanel() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ClientNotificationsPanel(
        clientUid: uid,
        onSeen: _markAllAsSeen,
      ),
    );
  }

  Future<void> _initFcm() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Initialize local notifications plugin
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _flnPlugin.initialize(initSettings);

    // Navigate to appointments tab when notification is tapped
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (mounted && msg.data['type'] == 'appointment_status') {
        setState(() => _currentIndex = 2); // Mis citas tab
      }
    });

    // App launched from terminated state via notification tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && mounted && initial.data['type'] == 'appointment_status') {
      setState(() => _currentIndex = 2);
    }

    // ── Show notification when app is in FOREGROUND ──
    FirebaseMessaging.onMessage.listen((msg) {
      final notification = msg.notification;
      if (notification == null) return;
      
      const androidDetails = AndroidNotificationDetails(
        'appointments_channel',
        'Notificaciones de citas',
        channelDescription: 'Actualizaciones sobre tus citas',
        importance: Importance.high,
        priority: Priority.high,
      );
      _flnPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(android: androidDetails),
      );
      
      // Forzar actualización del badge al recibir notificación
      if (mounted) setState(() {});
    });

    await _saveToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => _saveToken());
  }

  Future<void> _saveToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('❌ No se puede guardar token FCM: usuario no autenticado');
      return;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      print('❌ No se puede guardar token FCM: token es null');
      return;
    }
    print('✅ Guardando token FCM para cliente $uid: ${token.substring(0, 20)}...');
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
    print('✅ Token FCM guardado exitosamente');
  }

  String _appBarTitle(BuildContext context) {
    if (_currentIndex == 0) {
      final fullName = FirebaseAuth.instance.currentUser?.displayName ?? 'Cliente';
      final firstName = fullName.split(' ').first;
      return 'Hola, $firstName';
    }
    return _titles[_currentIndex - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_appBarTitle(context)),
        centerTitle: _currentIndex != 0,
        actions: [
          if (_currentIndex == 0)
            StreamBuilder<QuerySnapshot>(
              stream: _notifStream,
              builder: (context, snap) {
                final count = snap.data?.docs
                    .where((d) => !_seenIds.contains(d.id))
                    .length ?? 0;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: _openNotificationsPanel,
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                            textAlign: TextAlign.center,
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
          // Banner en vivo: tu barbero está en camino
          StreamBuilder<QuerySnapshot>(
            stream: _trackingStream,
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              // Buscar cita inmediata confirmada (status confirmed + isImmediate)
              // No esperamos barberCurrentLat - aparece inmediatamente cuando el barbero acepta
              final activeDocs = snap.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return data['isImmediate'] == true;
              }).toList();
              if (activeDocs.isEmpty) return const SizedBox.shrink();
              final doc = activeDocs.first;
              final data = doc.data() as Map<String, dynamic>;
              final barberName = data['barberName'] ?? 'Tu barbero';
              return _LiveTrackingBanner(
                barberName: barberName,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BarberTrackingScreen(
                    appointmentId: doc.id,
                    barberName: barberName,
                  ),
                )),
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
            activeIcon: Icon(Icons.home_filled),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            activeIcon: Icon(Icons.star),
            label: 'Favoritos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Citas',
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

// ── Banner en vivo: "Tu barbero está en camino" ───────────────────────
class _LiveTrackingBanner extends StatelessWidget {
  final String barberName;
  final VoidCallback onTap;
  const _LiveTrackingBanner({required this.barberName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.two_wheeler, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$barberName está en camino',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                  const Text(
                    'Toca para ver su ubicación en tiempo real',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Clases movidas a tabs/ ──
// _QuickAction → home_tab.dart
// _BarberCard  → home_tab.dart

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Panel de notificaciones del cliente
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ClientNotificationsPanel extends StatefulWidget {
  final String clientUid;
  final Future<void> Function(List<String> ids) onSeen;

  const _ClientNotificationsPanel({
    required this.clientUid,
    required this.onSeen,
  });

  @override
  State<_ClientNotificationsPanel> createState() =>
      _ClientNotificationsPanelState();
}

class _ClientNotificationsPanelState extends State<_ClientNotificationsPanel> {
  @override
  void initState() {
    super.initState();
    _markCurrentAsSeen();
  }

  Future<void> _markCurrentAsSeen() async {
    final snap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: widget.clientUid)
        .where('status', whereIn: ['confirmed', 'rejected', 'cancelled'])
        .get();
    final ids = snap.docs.map((d) => d.id).toList();
    await widget.onSeen(ids);
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} dÃ­as';
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
              .where('clientUid', isEqualTo: widget.clientUid)
              .snapshots(),
          builder: (context, snap) {
            final allDocs = snap.data?.docs ?? [];

            // Pending = esperando respuesta del barbero
            final pending = allDocs
                .where((d) => (d.data() as Map)['status'] == 'pending')
                .toList();

            // Actividad reciente = confirmadas/rechazadas/canceladas últimos 7 días
            final recent = allDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              final status = data['status'] as String? ?? '';
              final ts = (data['createdAt'] ?? data['scheduledAt']) as Timestamp?;
              if (ts == null) return false;
              return (status == 'confirmed' || status == 'rejected' || status == 'cancelled') &&
                  ts.compareTo(sevenDaysAgo) >= 0;
            }).toList()
              ..sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final ta =
                    ((dataA['createdAt'] ?? dataA['scheduledAt']) as Timestamp?)
                            ?.seconds ??
                        0;
                final tb =
                    ((dataB['createdAt'] ?? dataB['scheduledAt']) as Timestamp?)
                            ?.seconds ??
                        0;
                return tb.compareTo(ta);
              });

            final totalCount = pending.length + recent.length;

            return Column(
              children: [
                // â”€â”€ Handle + header â”€â”€
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

                // â”€â”€ Contenido â”€â”€
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
                                // â”€â”€ SecciÃ³n: Solicitudes enviadas â”€â”€
                                if (pending.isNotEmpty) ...[
                                  _ClientSectionLabel(
                                    icon: Icons.schedule_rounded,
                                    label:
                                        'Solicitudes enviadas  â€¢  ${pending.length}',
                                    color: Colors.orangeAccent,
                                  ),
                                  const SizedBox(height: 8),
                                  ...pending.map((doc) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    final barberName =
                                        d['barberName'] ?? 'Barbero';
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
                                        : '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

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
                                                child: Icon(Icons.content_cut,
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
                                                    Text(barberName,
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
                                              '\$$price Â· $duration min  â€¢  Esperando respuesta...',
                                              style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }),
                                ],

                                // â”€â”€ SecciÃ³n: Actividad reciente â”€â”€
                                if (recent.isNotEmpty) ...[
                                  if (pending.isNotEmpty)
                                    const SizedBox(height: 6),
                                  _ClientSectionLabel(
                                    icon: Icons.history_rounded,
                                    label: 'Actividad reciente',
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(height: 8),
                                  ...recent.map((doc) {
                                    final d =
                                        doc.data() as Map<String, dynamic>;
                                    final barberName =
                                        d['barberName'] ?? 'Barbero';
                                    final serviceName =
                                        d['serviceName'] ?? '';
                                    final status =
                                        d['status'] as String? ?? '';
                                    final cancelledBy = d['cancelledBy'] as String?;
                                    final ts =
                                        (d['createdAt'] ?? d['scheduledAt'])
                                            as Timestamp?;
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
                                        statusColor = Colors.orangeAccent;
                                        statusIcon = Icons.event_busy;
                                        // Verificar quién canceló la cita
                                        if (cancelledBy == widget.clientUid) {
                                          statusLabel = 'Haz cancelado la cita';
                                        } else {
                                          statusLabel = '$barberName canceló la cita';
                                        }
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
                                                  status == 'cancelled' 
                                                    ? statusLabel 
                                                    : '$statusLabel Â· $barberName',
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
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ClientSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ClientSectionLabel(
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
