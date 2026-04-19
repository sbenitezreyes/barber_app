import 'dart:async';
import 'dart:math' show asin, cos, pi, sin, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shake/shake.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../client/widgets/sos_button.dart';
import '../../shared/theme/app_theme.dart';
import '../services/fcm_service.dart';
import '../services/gps_service.dart';
import 'barber_emergency_contacts_screen.dart';
import 'client_profile_sheet.dart';
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

class _BarberHomeScreenState extends State<BarberHomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 1; // Iniciar en Agenda
  bool _mapTabInitialized =
      false; // Maps se carga solo cuando el usuario visita la tab
  final _notificationRefreshController = StreamController<void>.broadcast();
  late final Stream<int> _notificationCountStream;
  late final Stream<int> _pendingCountStream;
  late final Stream<List<QueryDocumentSnapshot>> _activeRouteStream;
  late final String _uid;
  late String _firstName;
  StreamSubscription? _firestoreSubscription;
  StreamSubscription? _refreshSubscription;
  Timer? _badgeDebounce; // Evita múltiples emitCount() en ráfagas de cambios

  // ── Panel SOS activo (en_servicio) ──────────────────────────────────
  String? _enServicioClientName;
  String? _enServicioClientUid;
  String? _enServicioApptId;
  bool _barberSosEnabled = false;
  List<Map<String, dynamic>> _barberEmergencyContacts = [];
  StreamSubscription? _enServicioSub;
  ShakeDetector? _shakeDetector;

  // ── Panel de servicio completado ─────────────────────────────────────
  String? _completedClientName;
  String? _completedClientUid;

  static const _tabTitles = ['Agenda', 'Configuración', 'Perfil'];

  @override
  void initState() {
    super.initState();
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: (ShakeEvent event) {
        if (_enServicioApptId != null &&
            _barberSosEnabled &&
            _barberEmergencyContacts.isNotEmpty) {
          _activateBarberSos();
        }
      },
    );

    // Cachear UID y nombre una sola vez
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _firstName = (FirebaseAuth.instance.currentUser?.displayName ?? 'Barbero')
        .split(' ')
        .first;

    // Escuchar cambios en el ciclo de vida de la app
    WidgetsBinding.instance.addObserver(this);

    // UNA SOLA SUSCRIPCIÓN a todos los appointments del barbero
    // (consolidada desde 3 queries anteriores → 1 query)
    _initializeAppointmentStreams();

    // Init FCM (token saving, foreground notifications, tap routing)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmService.instance.init(context: context);
    });
    // Listen for notification taps → switch to Agenda tab (index 1)
    FcmService.instance.scheduleTabRequested.addListener(
      _onScheduleTabRequested,
    );
    // Listen for new notifications → refresh badge
    FcmService.instance.notificationReceived.addListener(
      _onNotificationReceived,
    );
    // Emitir evento inicial para que se calcule el contador al inicio
    Future.microtask(() => _notificationRefreshController.add(null));
    // Panel SOS + stream de cita en servicio
    _loadBarberSosState();
    _startEnServicioListener();
  }

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
        print(
          '✅ [BarberHomeScreen] Detectada notificación nueva, limpiando flag',
        );
        await prefs.setBool('hasNewNotification', false);
      }

      _notificationRefreshController.add(null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FcmService.instance.scheduleTabRequested.removeListener(
      _onScheduleTabRequested,
    );
    FcmService.instance.notificationReceived.removeListener(
      _onNotificationReceived,
    );
    _badgeDebounce?.cancel();
    _firestoreSubscription?.cancel();
    _refreshSubscription?.cancel();
    _enServicioSub?.cancel();
    _shakeDetector?.stopListening();
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

  /// Consolida 3 queries de appointments en 1 sola suscripción.
  /// Crea los 3 streams (_notificationCountStream, _pendingCountStream, _activeRouteStream)
  /// desde um único snapshot de Firestore.
  void _initializeAppointmentStreams() {
    final notificationController = StreamController<int>.broadcast();
    final pendingController = StreamController<int>.broadcast();
    final activeRouteController =
        StreamController<List<QueryDocumentSnapshot>>.broadcast();

    _notificationCountStream = notificationController.stream;
    _pendingCountStream = pendingController.stream;
    _activeRouteStream = activeRouteController.stream;

    // UNA SOLA SUSCRIPCIÓN a todos los appointments
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('appointments')
        .where('barberUid', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
          // Procesar snapshot una sola vez para todos los streams
          // Debounce pequeño (100ms) para evitar ráfagas, NO para añadir latencia
          _badgeDebounce?.cancel();
          _badgeDebounce = Timer(const Duration(milliseconds: 100), () async {
            // 1. Notificaciones (pending + cancelled recientes, no vistas)
            final prefs = await SharedPreferences.getInstance();
            final viewedIds = (prefs.getStringList('viewedNotifications') ?? [])
                .toSet();
            final oneDayAgo = Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 1)),
            );

            final notificationCount = snap.docs.where((d) {
              if (viewedIds.contains(d.id)) return false;
              final data = d.data();
              final status = data['status'] as String?;
              final createdAt = data['createdAt'] as Timestamp?;
              return status == 'pending' ||
                  (status == 'cancelled' &&
                      createdAt != null &&
                      createdAt.compareTo(oneDayAgo) >= 0);
            }).length;

            if (!notificationController.isClosed) {
              notificationController.add(notificationCount);
            }

            // 2. Conteo de pending
            final pendingCount = snap.docs
                .where((d) => d.data()['status'] == 'pending')
                .length;
            if (!pendingController.isClosed) {
              pendingController.add(pendingCount);
            }

            // 3. Rutas activas (confirmed + inmediata o departing)
            final activeDocs = snap.docs.where((d) {
              final data = d.data();
              if (data['status'] != 'confirmed') return false;
              return data['isImmediate'] == true ||
                  data['barberDeparting'] == true;
            }).toList();
            if (!activeRouteController.isClosed) {
              activeRouteController.add(activeDocs);
            }
          });
        });

    // Refresh manual tras marcar como vistas → el badge pasa a 0
    _refreshSubscription = _notificationRefreshController.stream.listen((_) {
      if (!notificationController.isClosed) notificationController.add(0);
    });
  }

  void _openNotificationsPanel(BuildContext context) async {
    // Abrir el panel inmediatamente, sin esperar la red
    _markNotificationsAsViewed().then((_) {
      if (mounted) _notificationRefreshController.add(null);
    });
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotificationsPanel(
        uid: _uid,
        onOpenEmergencyContacts: () {
          final nav = Navigator.of(context);
          nav.pop(); // cerrar panel
          setState(() => _currentIndex = 2); // ir a Configuración
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              BarberEmergencyContacts.openFromSettings(context);
            }
          });
        },
      ),
    ).then((_) {
      if (mounted) _loadBarberSosState();
    });
  }

  void _openPendingPanel(BuildContext context) {
    if (_uid.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PendingRequestsPanel(uid: _uid),
    );
  }

  Future<void> _markNotificationsAsViewed() async {
    final uid = _uid;
    if (uid.isEmpty) return;

    try {
      // Usar caché primero (ya hay un snapshots() escuchando esta colección)
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('appointments')
            .where('barberUid', isEqualTo: uid)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        snap = await FirebaseFirestore.instance
            .collection('appointments')
            .where('barberUid', isEqualTo: uid)
            .get();
      }

      final oneDayAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 1)),
      );

      final notificationIds = snap.docs
          .where((d) {
            final data = d.data();
            final status = data['status'] as String?;
            final createdAt = data['createdAt'] as Timestamp?;

            return status == 'pending' ||
                (status == 'cancelled' &&
                    createdAt != null &&
                    createdAt.compareTo(oneDayAgo) >= 0);
          })
          .map((d) => d.id)
          .toList();

      final prefs = await SharedPreferences.getInstance();
      // ✅ AGREGAR a la lista existente, no reemplazar
      final existing = prefs.getStringList('viewedNotifications') ?? [];
      existing.addAll(notificationIds);
      await prefs.setStringList('viewedNotifications', existing);
      // Refrescar conteo del badge
      _notificationRefreshController.add(null);
    } catch (_) {}
  }

  // BarberHomeTab excluida aquí — se añade dinámicamente en build()
  // para evitar inicializar Google Maps hasta que el usuario visita la tab.
  static const _staticTabs = [
    BarberScheduleTab(),
    BarberSettingsTab(),
    BarberProfileTab(),
  ];

  // ── SOS del barbero ──────────────────────────────────────────────────

  Future<void> _loadBarberSosState() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('barber_sos_enabled') ?? false;
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
    }
    final contacts = ((doc.data()?['emergencyContacts'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (mounted) {
      setState(() {
        _barberSosEnabled = enabled;
        _barberEmergencyContacts = contacts;
      });
    }
  }

  void _startEnServicioListener() {
    _enServicioSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('barberUid', isEqualTo: _uid)
        .where('status', isEqualTo: 'en_servicio')
        .snapshots()
        .listen((snap) async {
          if (!mounted) return;
          if (snap.docs.isEmpty) {
            // Si había un servicio activo, verificar si pasó a completado
            if (_enServicioApptId != null) {
              final prevId = _enServicioApptId!;
              final prevClientName = _enServicioClientName;
              final prevClientUid = _enServicioClientUid;
              setState(() {
                _enServicioApptId = null;
                _enServicioClientName = null;
                _enServicioClientUid = null;
              });
              try {
                final doc = await FirebaseFirestore.instance
                    .collection('appointments')
                    .doc(prevId)
                    .get();
                if (doc.exists &&
                    doc.data()?['status'] == 'completed' &&
                    mounted) {
                  setState(() {
                    _completedClientName = prevClientName;
                    _completedClientUid = prevClientUid;
                  });
                }
              } catch (_) {}
            } else {
              setState(() {
                _enServicioApptId = null;
                _enServicioClientName = null;
                _enServicioClientUid = null;
              });
            }
            return;
          }
          final doc = snap.docs.first;
          final data = doc.data();
          setState(() {
            _enServicioApptId = doc.id;
            _enServicioClientName = data['clientName'] as String? ?? 'Cliente';
            _enServicioClientUid = data['clientUid'] as String?;
            // Limpiar estado completado si inicia un nuevo servicio
            _completedClientName = null;
            _completedClientUid = null;
          });
        });
  }

  Future<void> _activateBarberSos() async {
    HapticFeedback.heavyImpact();
    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.red.withValues(alpha: 0.25),
      builder: (_) => _BarberSosActionDialog(
        clientName: _enServicioClientName ?? 'Cliente',
        contacts: _barberEmergencyContacts,
        latitude: lat,
        longitude: lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: _currentIndex == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Hola, ',
                          style: AppTextStyles.ui(
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: _firstName,
                          style: AppTextStyles.display(size: 20),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: FcmService.instance.isAvailable,
                    builder: (_, available, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: available
                                ? AppColors.success
                                : AppColors.textTertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          available ? 'Disponible' : 'No disponible',
                          style: AppTextStyles.ui(
                            size: 11,
                            color: available
                                ? AppColors.success
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Text(
                _tabTitles[_currentIndex - 1],
                style: AppTextStyles.ui(size: 18, weight: FontWeight.w600),
              ),
        centerTitle: _currentIndex != 0,
        actions: [
          // Botón de solicitudes pendientes — solo visible en la pestaña Agenda
          if (_currentIndex == 1)
            StreamBuilder<int>(
              stream: _pendingCountStream,
              builder: (context, snap) {
                final count = snap.data ?? 0;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.pending_actions_outlined,
                        size: 22,
                      ),
                      color: count > 0
                          ? AppColors.gold
                          : AppColors.textSecondary,
                      onPressed: () => _openPendingPanel(context),
                      tooltip: 'Solicitudes',
                    ),
                    if (count > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.background,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
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
                        const SnackBar(
                          content: Text(
                            'El cliente no compartió su ubicación GPS',
                          ),
                        ),
                      )
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ClientRouteScreen(
                            appointmentId: doc.id,
                            clientName: clientName,
                            clientLat: clientLat,
                            clientLng: clientLng,
                          ),
                        ),
                      ),
                onCancel: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: AppColors.surfaceElevated,
                      title: Text('Cancelar cita', style: AppTextStyles.title),
                      content: Text(
                        '¿Cancelar la cita con $clientName?',
                        style: AppTextStyles.body,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('No'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(
                            'Sí, cancelar',
                            style: AppTextStyles.button.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await FirebaseFirestore.instance
                      .collection('appointments')
                      .doc(doc.id)
                      .update({'status': 'cancelled', 'cancelledBy': _uid});
                },
              );
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                // Maps se inicializa solo cuando el usuario visita la tab por primera vez
                _mapTabInitialized
                    ? const BarberHomeTab()
                    : const SizedBox.shrink(),
                ..._staticTabs,
              ],
            ),
          ),
          // ── Panel SOS: ocupa espacio real → las citas quedan visibles ──
          if (_enServicioApptId != null)
            _BarberServicePanel(
              clientName: _enServicioClientName!,
              showSos: _barberSosEnabled && _barberEmergencyContacts.isNotEmpty,
              onSosActivated: _activateBarberSos,
            ),
          // ── Panel de servicio completado ──────────────────────────────
          if (_completedClientName != null)
            _BarberCompletedPanel(
              clientName: _completedClientName!,
              onReview: () {
                final uid = _completedClientUid;
                final name = _completedClientName!;
                setState(() {
                  _completedClientName = null;
                  _completedClientUid = null;
                });
                if (uid != null) {
                  showClientProfileSheet(
                    context,
                    clientUid: uid,
                    clientName: name,
                  );
                }
              },
              onDismiss: () => setState(() {
                _completedClientName = null;
                _completedClientUid = null;
              }),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() {
            _currentIndex = i;
            if (i == 0) _mapTabInitialized = true;
          }),
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
  final VoidCallback onOpenEmergencyContacts;
  const _NotificationsPanel({
    required this.uid,
    required this.onOpenEmergencyContacts,
  });

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  Set<String> _dismissedIds = {};
  bool _sosEnabled = false;
  bool _hasContacts = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
    _loadSosState();
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('dismissed_notif_ids_barber') ?? [];
    if (mounted) setState(() => _dismissedIds = saved.toSet());
  }

  Future<void> _loadSosState() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('barber_sos_enabled') ?? false;
    final hasContacts = await BarberEmergencyContacts.hasContacts();
    if (mounted) {
      setState(() {
        _sosEnabled = enabled;
        _hasContacts = hasContacts;
      });
    }
  }

  Future<void> _toggleSos(bool value) async {
    if (value && !_hasContacts) {
      // Sin contactos: mostrar aviso
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.shield_outlined, color: AppColors.error, size: 22),
              const SizedBox(width: 10),
              Text(
                'Sin contactos de emergencia',
                style: AppTextStyles.ui(size: 15, weight: FontWeight.w700),
              ),
            ],
          ),
          content: Text(
            'Debes añadir al menos un contacto de emergencia para poder activar el botón SOS.',
            style: AppTextStyles.ui(size: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenEmergencyContacts();
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.gold),
              child: Text(
                'Añadir contactos',
                style: AppTextStyles.ui(size: 13, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('barber_sos_enabled', value);
    if (mounted) setState(() => _sosEnabled = value);
  }

  Future<void> _dismissOne(String id) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds.add(id);
    await prefs.setStringList(
      'dismissed_notif_ids_barber',
      _dismissedIds.toList(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _clearAll(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds.addAll(ids);
    await prefs.setStringList(
      'dismissed_notif_ids_barber',
      _dismissedIds.toList(),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sevenDaysAgo = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 7)),
    );

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
            final recent =
                allDocs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final status = data['status'] as String? ?? '';
                  final ts = data['createdAt'] as Timestamp?;
                  if (ts == null) return false;
                  return (status == 'pending' ||
                          status == 'confirmed' ||
                          status == 'rejected' ||
                          status == 'completed' ||
                          status == 'cancelled') &&
                      ts.compareTo(sevenDaysAgo) >= 0 &&
                      !_dismissedIds.contains(d.id);
                }).toList()..sort((a, b) {
                  final ta =
                      ((a.data() as Map)['createdAt'] as Timestamp?)?.seconds ??
                      0;
                  final tb =
                      ((b.data() as Map)['createdAt'] as Timestamp?)?.seconds ??
                      0;
                  return tb.compareTo(ta); // mÃ¡s recientes primero
                });

            final totalCount = recent.length;

            return Column(
              children: [
                // â”€â”€ Handle + header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.goldDark,
                          AppColors.gold,
                          AppColors.goldDark,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.goldSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderAccent),
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.gold,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificaciones',
                              style: AppTextStyles.display(size: 20),
                            ),
                            Text(
                              'Solicitudes y actividad reciente',
                              style: AppTextStyles.ui(
                                size: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (totalCount > 0)
                        TextButton.icon(
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 15,
                          ),
                          label: Text(
                            'Limpiar',
                            style: AppTextStyles.ui(size: 12),
                          ),
                          onPressed: () =>
                              _clearAll(recent.map((d) => d.id).toList()),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textTertiary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.borderAccent,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // ── Toggle SOS ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _sosEnabled
                            ? Colors.red.withValues(alpha: 0.4)
                            : AppColors.borderSubtle,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.sos_rounded,
                            color: _sosEnabled ? Colors.red : Colors.white38,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Botón SOS',
                                style: AppTextStyles.ui(
                                  size: 13,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _hasContacts
                                    ? 'Actívalo para tener acceso rápido durante servicios'
                                    : 'Añade contactos de emergencia para activarlo',
                                style: AppTextStyles.ui(
                                  size: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _sosEnabled,
                          onChanged: _toggleSos,
                          activeThumbColor: Colors.red.shade400,
                          activeTrackColor: Colors.red.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  ),
                ),

                // â”€â”€ Contenido â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                Expanded(
                  child: !snap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : totalCount == 0
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.goldSubtle,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.borderAccent,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.notifications_none,
                                  size: 32,
                                  color: AppColors.gold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Sin notificaciones',
                                style: AppTextStyles.display(size: 18),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Todo tranquilo por ahora',
                                style: AppTextStyles.ui(
                                  size: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          children: [
                            // â”€â”€ SecciÃ³n: Actividad reciente
                            if (recent.isNotEmpty) ...[
                              _SectionLabel(
                                icon: Icons.history_rounded,
                                label: 'Actividad reciente',
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              ...recent.map((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                final clientName = d['clientName'] ?? 'Cliente';
                                final serviceName = d['serviceName'] ?? '';
                                final status = d['status'] as String? ?? '';
                                final cancelledBy = d['cancelledBy'] as String?;
                                final ts = d['createdAt'] as Timestamp?;
                                final dt = ts?.toDate() ?? DateTime.now();
                                final timeAgo = _timeAgo(dt);

                                Color statusColor;
                                IconData statusIcon;
                                String statusLabel;
                                String displayText;

                                switch (status) {
                                  case 'pending':
                                    statusColor = AppColors.gold;
                                    statusIcon = Icons.pending_actions_outlined;
                                    statusLabel = 'Nueva solicitud';
                                    displayText = '$statusLabel · $clientName';
                                    break;
                                  case 'confirmed':
                                    statusColor = AppColors.success;
                                    statusIcon = Icons.check_circle_outline;
                                    statusLabel = 'Confirmada';
                                    displayText = '$statusLabel · $clientName';
                                    break;
                                  case 'rejected':
                                    statusColor = AppColors.error;
                                    statusIcon = Icons.cancel_outlined;
                                    statusLabel = 'Rechazada';
                                    displayText = '$statusLabel · $clientName';
                                    break;
                                  case 'cancelled':
                                    statusColor = AppColors.warning;
                                    statusIcon = Icons.event_busy;
                                    if (cancelledBy == widget.uid) {
                                      statusLabel = 'Cancelada';
                                      displayText =
                                          'Cancelaste la cita de $clientName';
                                    } else {
                                      statusLabel = 'Cancelada';
                                      displayText =
                                          '$clientName canceló la cita';
                                    }
                                    break;
                                  default:
                                    statusColor = AppColors.gold;
                                    statusIcon = Icons.task_alt_rounded;
                                    statusLabel = 'Completada';
                                    displayText = '$statusLabel · $clientName';
                                }

                                return Dismissible(
                                  key: ValueKey(doc.id),
                                  direction: DismissDirection.startToEnd,
                                  onDismissed: (_) => _dismissOne(doc.id),
                                  background: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.error.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                      size: 20,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border(
                                          left: BorderSide(
                                            color: statusColor,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 34,
                                              height: 34,
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                statusIcon,
                                                color: statusColor,
                                                size: 18,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    displayText,
                                                    style: AppTextStyles.ui(
                                                      size: 13,
                                                      weight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    serviceName,
                                                    style: AppTextStyles.ui(
                                                      size: 12,
                                                      color: AppColors
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              timeAgo,
                                              style: AppTextStyles.ui(
                                                size: 11,
                                                color: AppColors.textTertiary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
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
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: AppTextStyles.ui(
              size: 10,
              weight: FontWeight.w700,
              color: color,
            ).copyWith(letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

// Chip reutilizable de distancia/tiempo (panel barbero)
class _DistanceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DistanceChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tealSubtle,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppColors.teal),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTextStyles.ui(
              size: 10,
              weight: FontWeight.w500,
              color: AppColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Banner retomar ruta activa ────────────────────────────────────
class _ActiveRouteBanner extends StatelessWidget {
  final String clientName;
  final VoidCallback onTap;
  final Future<void> Function()? onCancel;
  const _ActiveRouteBanner({
    required this.clientName,
    required this.onTap,
    this.onCancel,
  });

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
                      fontSize: 13,
                    ),
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

// ── Panel de solicitudes pendientes ───────────────────────────────
class _PendingRequestsPanel extends StatefulWidget {
  final String uid;
  const _PendingRequestsPanel({required this.uid});

  @override
  State<_PendingRequestsPanel> createState() => _PendingRequestsPanelState();
}

class _PendingRequestsPanelState extends State<_PendingRequestsPanel> {
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
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Rechazar cita', style: AppTextStyles.title),
          content: Text(
            '¿Rechazar la cita de $clientName?',
            style: AppTextStyles.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Rechazar',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await FirebaseFirestore.instance.collection('appointments').doc(id).update({
      'status': status,
    });
    if (status == 'confirmed' &&
        isImmediate &&
        clientLat != null &&
        clientLng != null &&
        mounted) {
      Navigator.of(context).pop(); // cerrar panel
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ClientRouteScreen(
            appointmentId: id,
            clientName: clientName,
            clientLat: clientLat,
            clientLng: clientLng,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('appointments')
              .where('barberUid', isEqualTo: widget.uid)
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (ctx, snap) {
            final docs = snap.data?.docs ?? [];

            return Column(
              children: [
                // Handle
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.goldDark,
                          AppColors.gold,
                          AppColors.goldDark,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.goldSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderAccent),
                        ),
                        child: const Icon(
                          Icons.pending_actions_outlined,
                          color: AppColors.gold,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Solicitudes',
                              style: AppTextStyles.display(size: 20),
                            ),
                            Text(
                              docs.isEmpty
                                  ? 'Sin solicitudes pendientes'
                                  : '${docs.length} solicitud${docs.length != 1 ? 'es' : ''} esperando respuesta',
                              style: AppTextStyles.ui(
                                size: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.borderAccent,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                // Contenido
                Expanded(
                  child: !snap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : docs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.goldSubtle,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.borderAccent,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.pending_actions_outlined,
                                  size: 32,
                                  color: AppColors.gold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Sin solicitudes',
                                style: AppTextStyles.display(size: 18),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Cuando alguien pida una cita\naparecerá aquí',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.ui(
                                  size: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final d = docs[i].data() as Map<String, dynamic>;
                            final id = docs[i].id;
                            final clientName =
                                d['clientName'] as String? ?? 'Cliente';
                            final clientUid = d['clientUid'] as String? ?? '';
                            final serviceName =
                                d['serviceName'] as String? ?? '';
                            final price =
                                (d['servicePrice'] as num?)?.toDouble() ?? 0;
                            final duration =
                                (d['serviceDuration'] as num?)?.toInt() ?? 0;
                            final isImmediate =
                                d['isImmediate'] as bool? ?? false;
                            final ts = d['scheduledAt'] as Timestamp?;
                            final dt = ts?.toDate() ?? DateTime.now();
                            final timeLabel = isImmediate
                                ? 'Ahora mismo'
                                : DateFormat(
                                    'EEE d MMM, HH:mm',
                                    'es',
                                  ).format(dt);
                            final cLat = (d['clientLat'] as num?)?.toDouble();
                            final cLng = (d['clientLng'] as num?)?.toDouble();

                            return Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.borderAccent,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gold.withValues(
                                      alpha: 0.07,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
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
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(16),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      12,
                                      14,
                                      14,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            GestureDetector(
                                              onTap: () =>
                                                  showClientProfileSheet(
                                                    ctx,
                                                    clientUid: clientUid,
                                                    clientName: clientName,
                                                  ),
                                              child: Container(
                                                width: 40,
                                                height: 40,
                                                decoration: const BoxDecoration(
                                                  color: AppColors.goldSubtle,
                                                  shape: BoxShape.circle,
                                                  border: Border.fromBorderSide(
                                                    BorderSide(
                                                      color: AppColors
                                                          .borderAccent,
                                                    ),
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons.person_outline,
                                                  size: 20,
                                                  color: AppColors.gold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    clientName,
                                                    style:
                                                        AppTextStyles.display(
                                                          size: 15,
                                                        ),
                                                  ),
                                                  GestureDetector(
                                                    onTap: () =>
                                                        showClientProfileSheet(
                                                          ctx,
                                                          clientUid: clientUid,
                                                          clientName:
                                                              clientName,
                                                        ),
                                                    child: Text(
                                                      'Ver perfil →',
                                                      style: AppTextStyles.ui(
                                                        size: 11,
                                                        color: AppColors.gold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.goldSubtle,
                                                borderRadius:
                                                    BorderRadius.circular(100),
                                                border: Border.all(
                                                  color: AppColors.borderAccent,
                                                ),
                                              ),
                                              child: Text(
                                                timeLabel,
                                                style: AppTextStyles.ui(
                                                  size: 11,
                                                  weight: FontWeight.w600,
                                                  color: AppColors.gold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          serviceName,
                                          style: AppTextStyles.ui(
                                            size: 13,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.goldSubtle,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '\$$price',
                                                style: AppTextStyles.ui(
                                                  size: 12,
                                                  weight: FontWeight.w700,
                                                  color: AppColors.gold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.timer_outlined,
                                              size: 13,
                                              color: AppColors.textTertiary,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$duration min',
                                              style: AppTextStyles.ui(
                                                size: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (cLat != null &&
                                            cLng != null &&
                                            _barberLat != null &&
                                            _barberLng != null)
                                          Builder(
                                            builder: (_) {
                                              final m = _haversineMeters(
                                                _barberLat!,
                                                _barberLng!,
                                                cLat,
                                                cLng,
                                              );
                                              final km = m / 1000;
                                              final dist = km < 1
                                                  ? '${(km * 1000).round()} m'
                                                  : '${km.toStringAsFixed(1)} km';
                                              final walk = (m / 83).round();
                                              final moto = (m / 667).round();
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    _DistanceChip(
                                                      icon: Icons
                                                          .location_on_outlined,
                                                      label: dist,
                                                    ),
                                                    _DistanceChip(
                                                      icon:
                                                          Icons.directions_walk,
                                                      label: walk < 1
                                                          ? '<1 min'
                                                          : '~$walk min',
                                                    ),
                                                    _DistanceChip(
                                                      icon: Icons.two_wheeler,
                                                      label: moto < 1
                                                          ? '<1 min'
                                                          : '~$moto min',
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 14,
                                                ),
                                                label: const Text('Rechazar'),
                                                onPressed: () => _setStatus(
                                                  ctx,
                                                  id,
                                                  'rejected',
                                                  clientName,
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.error,
                                                  side: BorderSide(
                                                    color: AppColors.error
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                      ),
                                                  minimumSize: Size.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          100,
                                                        ),
                                                  ),
                                                  textStyle: AppTextStyles.ui(
                                                    size: 13,
                                                    weight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                icon: const Icon(
                                                  Icons.check,
                                                  size: 14,
                                                ),
                                                label: const Text('Aceptar'),
                                                onPressed: () => _setStatus(
                                                  ctx,
                                                  id,
                                                  'confirmed',
                                                  clientName,
                                                  isImmediate: isImmediate,
                                                  clientLat: cLat,
                                                  clientLng: cLng,
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.gold,
                                                  foregroundColor:
                                                      AppColors.background,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                      ),
                                                  minimumSize: Size.zero,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          100,
                                                        ),
                                                  ),
                                                  textStyle: AppTextStyles.ui(
                                                    size: 13,
                                                    weight: FontWeight.w700,
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
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Panel SOS del barbero durante el servicio ─────────────────────────
class _BarberServicePanel extends StatelessWidget {
  final String clientName;
  final bool showSos;
  final VoidCallback onSosActivated;

  const _BarberServicePanel({
    required this.clientName,
    required this.showSos,
    required this.onSosActivated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.goldSubtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.content_cut_rounded,
              color: AppColors.gold,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Estás en servicio con:', style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(clientName, style: AppTextStyles.title),
              ],
            ),
          ),
          if (showSos) ...[
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SosButton(onActivated: onSosActivated),
                const SizedBox(height: 4),
                const Text(
                  'Mantén 5s',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Panel de servicio completado del barbero ─────────────────────────
class _BarberCompletedPanel extends StatelessWidget {
  final String clientName;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  const _BarberCompletedPanel({
    required this.clientName,
    required this.onReview,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Colors.greenAccent,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '¡Tu servicio ha terminado!',
            style: AppTextStyles.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'No olvides dejar tu reseña a $clientName',
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Tal vez luego',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade700,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Dejar reseña',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Diálogo SOS del barbero ───────────────────────────────────────────
class _BarberSosActionDialog extends StatefulWidget {
  final String clientName;
  final List<Map<String, dynamic>> contacts;
  final double? latitude;
  final double? longitude;

  const _BarberSosActionDialog({
    required this.clientName,
    required this.contacts,
    this.latitude,
    this.longitude,
  });

  @override
  State<_BarberSosActionDialog> createState() => _BarberSosActionDialogState();
}

class _BarberSosActionDialogState extends State<_BarberSosActionDialog> {
  final _sent = <int>{};

  String _buildMessage() {
    final loc = (widget.latitude != null && widget.longitude != null)
        ? 'https://maps.google.com/?q=${widget.latitude},${widget.longitude}'
        : 'No disponible';
    return '🚨 EMERGENCIA - NECESITO AYUDA 🚨\n\n'
        'Soy barbero a domicilio y puede que esté en peligro o no pueda responder.\n\n'
        '📍 Mi ubicación ahora: $loc\n\n'
        '👤 Estoy en casa de: ${widget.clientName}\n\n'
        '⚠️ Mensaje enviado automáticamente desde YaCut. '
        'Por favor, busca ayuda o llama a emergencias (123 / 911).';
  }

  Future<void> _sendWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final encoded = Uri.encodeComponent(_buildMessage());
    final uri = Uri.parse('https://wa.me/$clean?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendSms(String phone) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': _buildMessage()},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A0505),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade800, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.35),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sos_rounded,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¡ALERTA SOS!',
                          style: AppTextStyles.ui(
                            size: 18,
                            weight: FontWeight.w800,
                            color: Colors.red.shade300,
                          ),
                        ),
                        Text(
                          'Envía tu ubicación a tus contactos',
                          style: AppTextStyles.ui(
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...widget.contacts.asMap().entries.map((entry) {
                final i = entry.key;
                final c = entry.value;
                final name = c['name'] as String? ?? 'Contacto ${i + 1}';
                final phone = c['phone'] as String? ?? '';
                final sent = _sent.contains(i);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: sent
                        ? Colors.green.withValues(alpha: 0.08)
                        : Colors.red.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sent
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            sent
                                ? Icons.check_circle_rounded
                                : Icons.person_outline_rounded,
                            color: sent ? Colors.green : Colors.white54,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: AppTextStyles.ui(
                              size: 14,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            phone,
                            style: AppTextStyles.ui(
                              size: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      if (!sent) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await _sendWhatsApp(phone);
                                  setState(() => _sent.add(i));
                                },
                                icon: const Icon(Icons.chat_rounded, size: 15),
                                label: const Text('WhatsApp'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.greenAccent,
                                  side: BorderSide(
                                    color: Colors.greenAccent.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  textStyle: AppTextStyles.ui(
                                    size: 12,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await _sendSms(phone);
                                  setState(() => _sent.add(i));
                                },
                                icon: const Icon(Icons.sms_rounded, size: 15),
                                label: const Text('SMS'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.lightBlueAccent,
                                  side: BorderSide(
                                    color: Colors.lightBlueAccent.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  textStyle: AppTextStyles.ui(
                                    size: 12,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textTertiary,
                  ),
                  child: Text(
                    'Cerrar',
                    style: AppTextStyles.ui(
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
