import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shake/shake.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/app_theme.dart';
import '../widgets/sos_button.dart';
import '../widgets/sos_action_dialog.dart';

import 'barber_profile_sheet.dart';
import 'barber_tracking_screen.dart';
import 'emergency_contacts_dialog.dart';
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
  StreamSubscription<QuerySnapshot>? _firestoreNotifSub; // controla el listener de Firestore
  String _firstName = '';
  Set<String> _seenIds = {};
  List<String> _latestNotifIds = [];
  final _flnPlugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<User?>? _authSub;
  StreamSubscription? _fcmMessageSub;
  StreamSubscription? _fcmOpenedSub;
  StreamSubscription? _fcmTokenSub;
  StreamSubscription? _sosNotifSub;
  ShakeDetector? _shakeDetector;
  static const _kSosNotifId = 8888;

  // ── Estado SOS overlay ───────────────────────────────────────────────
  String? _enServicioApptId;
  String? _enServicioBarberName;
  String? _enServicioBarberPhone;
  String? _enServicioBarberUid;
  List<Map<String, dynamic>> _emergencyContacts = [];
  bool _sosEnabled = true;
  bool _sosSupportDataLoaded = false;
  // 'en_servicio' | 'completed'
  String _activeApptStatus = 'en_servicio';
  bool _completedDismissed = false;

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
    _shakeDetector = ShakeDetector.autoStart(
      onPhoneShake: (ShakeEvent event) {
        if (_showSos) _activateSos();
      },
    );
    // Reinicializar streams cuando cambia el usuario (login, registro, etc.)
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      _initBadgeStream();
    });

    // Mostrar diálogo de bienvenida si es la primera vez
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WelcomeDialog.showIfFirstTime(context);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _firestoreNotifSub?.cancel();
    _fcmMessageSub?.cancel();
    _fcmOpenedSub?.cancel();
    _fcmTokenSub?.cancel();
    _sosNotifSub?.cancel();
    _shakeDetector?.stopListening();
    super.dispose();
  }

  void _initBadgeStream() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;
    // Cargar nombre desde Firestore para tenerlo siempre actualizado
    // (displayName puede estar vacío justo después del registro)
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((doc) {
      if (!mounted) return;
      final name = doc.data()?['name'] as String?;
      if (name != null && name.isNotEmpty) {
        setState(() => _firstName = name.split(' ').first);
      } else {
        // Fallback a displayName mientras Firestore carga
        final dn = user?.displayName ?? '';
        if (dn.isNotEmpty) setState(() => _firstName = dn.split(' ').first);
      }
    });
    // Load previously seen IDs from local storage
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getStringList('client_seen_notif_ids') ?? [];
      if (mounted) setState(() => _seenIds = saved.toSet());
    });
    // Cancelar stream anterior antes de crear uno nuevo (evita PERMISSION_DENIED)
    _firestoreNotifSub?.cancel();
    _sosNotifSub?.cancel();

    // StreamController broadcast que controlamos explícitamente
    final controller = StreamController<QuerySnapshot>.broadcast();
    _notifStream = controller.stream;
    _firestoreNotifSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('clientUid', isEqualTo: uid)
        .where(
          'status',
          whereIn: [
            'confirmed',
            'en_servicio',
            'rejected',
            'cancelled',
            'completed',
          ],
        )
        .snapshots()
        .listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );

    // Notificación persistente SOS cuando la cita pasa a en_servicio
    _sosNotifSub = _notifStream!.listen(_onApptStreamForSos);

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
    // Marcar como vistos inmediatamente con los IDs que ya tenemos en caché
    _markAllAsSeen(_latestNotifIds);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ClientNotificationsPanel(
        clientUid: uid,
        onOpenEmergencyContacts: () {
          final nav = Navigator.of(context);
          nav.pop(); // cierra el panel
          setState(() => _currentIndex = 3); // tab Perfil
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) EmergencyContactsDialog.openFromProfile(context);
          });
        },
      ),
    ).then((_) => _reloadSosEnabled());
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

    // Crear canal Android (requerido en Android 8+ — sin esto las notificaciones se descartan)
    const androidChannel = AndroidNotificationChannel(
      'appointments_channel',
      'Notificaciones de citas',
      description: 'Actualizaciones sobre el estado de tus citas',
      importance: Importance.max,
      playSound: true,
    );
    await _flnPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    // Canal exclusivo para notificación SOS persistente en pantalla bloqueada
    const sosChannel = AndroidNotificationChannel(
      'sos_channel',
      'Seguridad SOS',
      description: 'Alerta de seguridad mientras el barbero está en tu casa',
      importance: Importance.max,
      playSound: false,
    );
    await _flnPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(sosChannel);

    // Navigate to appointments tab when notification is tapped
    _fcmOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (mounted && msg.data['type'] == 'appointment_status') {
        setState(() => _currentIndex = 2); // Mis citas tab
      }
    });

    // App launched from terminated state via notification tap
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null &&
        mounted &&
        initial.data['type'] == 'appointment_status') {
      setState(() => _currentIndex = 2);
    }

    // ── Show notification when app is in FOREGROUND ──
    _fcmMessageSub = FirebaseMessaging.onMessage.listen((msg) {
      final notification = msg.notification;
      if (notification == null) return;

      const androidDetails = AndroidNotificationDetails(
        'appointments_channel',
        'Notificaciones de citas',
        channelDescription: 'Actualizaciones sobre tus citas',
        importance: Importance.max,
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
    _fcmTokenSub = FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => _saveToken(),
    );
  }

  // Muestra/cancela la notificación persistente SOS y gestiona el overlay
  void _onApptStreamForSos(QuerySnapshot snap) {
    final enServicioDoc = snap.docs.cast<QueryDocumentSnapshot?>().firstWhere(
      (d) => (d!.data() as Map)['status'] == 'en_servicio',
      orElse: () => null,
    );

    if (enServicioDoc != null) {
      final data = enServicioDoc.data() as Map<String, dynamic>;
      final barberName = data['barberName'] as String? ?? 'Tu barbero';
      final barberUid = data['barberUid'] as String?;
      _showSosPersistentNotif(barberName);
      if (!_sosSupportDataLoaded && barberUid != null) {
        _sosSupportDataLoaded = true;
        _loadSosData(enServicioDoc.id, barberName, barberUid);
      }
      return;
    }

    // Sin en_servicio: verificar si la cita que estábamos trackeando pasó a completed
    _flnPlugin.cancel(_kSosNotifId);
    _sosPersistentShown = false;

    if (_enServicioApptId != null) {
      final completedDoc = snap.docs.cast<QueryDocumentSnapshot?>().firstWhere(
        (d) =>
            d!.id == _enServicioApptId &&
            (d.data() as Map)['status'] == 'completed',
        orElse: () => null,
      );
      if (completedDoc != null) {
        // Transición en_servicio → completed: mostrar panel de finalización
        if (mounted) {
          setState(() {
            _activeApptStatus = 'completed';
            _completedDismissed = false;
          });
        }
        return;
      }
    }

    // Nada activo
    _sosSupportDataLoaded = false;
    if (mounted) {
      setState(() {
        _enServicioApptId = null;
        _enServicioBarberName = null;
        _enServicioBarberPhone = null;
        _emergencyContacts = [];
        _activeApptStatus = 'en_servicio';
      });
    }
  }

  Future<void> _loadSosData(
    String apptId,
    String barberName,
    String barberUid,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('sos_button_enabled') ?? true;

    final clientUid = FirebaseAuth.instance.currentUser?.uid;
    List<Map<String, dynamic>> contacts = [];
    if (clientUid != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(clientUid)
          .get();
      contacts = ((doc.data()?['emergencyContacts'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    final barberDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(barberUid)
        .get();
    final barberPhone = barberDoc.data()?['phone'] as String?;

    if (mounted) {
      setState(() {
        _sosEnabled = enabled;
        _emergencyContacts = contacts;
        _enServicioApptId = apptId;
        _enServicioBarberName = barberName;
        _enServicioBarberPhone = barberPhone;
        _enServicioBarberUid = barberUid;
        _activeApptStatus = 'en_servicio';
        _completedDismissed = false;
      });
    }
  }

  void _dismissCompleted() {
    setState(() {
      _completedDismissed = true;
      _enServicioApptId = null;
      _enServicioBarberName = null;
      _enServicioBarberPhone = null;
      _enServicioBarberUid = null;
      _emergencyContacts = [];
      _sosSupportDataLoaded = false;
      _activeApptStatus = 'en_servicio';
    });
  }

  Future<void> _openBarberReview() async {
    final uid = _enServicioBarberUid;
    if (uid == null) return;
    _dismissCompleted();
    if (!mounted) return;
    await showBarberReviewDialog(context, uid);
  }

  bool get _showSos =>
      _enServicioApptId != null && _sosEnabled && _emergencyContacts.isNotEmpty;

  Future<void> _activateSos() async {
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
      builder: (_) => SosActionDialog(
        barberName: _enServicioBarberName ?? 'Tu barbero',
        barberPhone: _enServicioBarberPhone,
        contacts: _emergencyContacts,
        latitude: lat,
        longitude: lng,
      ),
    );
  }

  Future<void> _reloadSosEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('sos_button_enabled') ?? true;
    if (mounted) setState(() => _sosEnabled = enabled);
  }

  bool _sosPersistentShown = false;

  Future<void> _showSosPersistentNotif(String barberName) async {
    if (_sosPersistentShown) return;
    _sosPersistentShown = true;
    const androidDetails = AndroidNotificationDetails(
      'sos_channel',
      'Seguridad SOS',
      channelDescription:
          'Alerta de seguridad mientras el barbero está en tu casa',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      color: Colors.red,
      enableLights: true,
      ledColor: Colors.red,
      ledOnMs: 500,
      ledOffMs: 1000,
    );
    await _flnPlugin.show(
      _kSosNotifId,
      '🛡️ $barberName está en tu casa',
      'Mantén pulsado el botón SOS 5s si necesitas ayuda. Toca para abrir.',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _saveToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    // Siempre guardar token fresco — evita tokens vencidos en Firestore
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: _currentIndex == 0
            ? RichText(
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
              )
            : Text(
                _titles[_currentIndex - 1],
                style: AppTextStyles.ui(size: 18, weight: FontWeight.w600),
              ),
        centerTitle: _currentIndex != 0,
        actions: [
          if (_currentIndex == 0)
            StreamBuilder<QuerySnapshot>(
              stream: _notifStream,
              builder: (context, snap) {
                // Clave compuesta id_status para detectar cambios de estado como nuevos
                _latestNotifIds =
                    snap.data?.docs.map((d) {
                      final s =
                          (d.data() as Map<String, dynamic>)['status']
                              as String? ??
                          '';
                      return '${d.id}_$s';
                    }).toList() ??
                    [];
                final count =
                    snap.data?.docs.where((d) {
                      final s =
                          (d.data() as Map<String, dynamic>)['status']
                              as String? ??
                          '';
                      return !_seenIds.contains('${d.id}_$s');
                    }).length ??
                    0;
                return Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined, size: 22),
                      color: AppColors.textPrimary,
                      onPressed: _openNotificationsPanel,
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
      body: Stack(
        children: [
          Column(
            children: [
              // Banner en vivo — solo cuando el barbero está en camino (confirmed)
              StreamBuilder<QuerySnapshot>(
                stream: _notifStream,
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final activeDocs = snap.data!.docs.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    final status = data['status'] as String?;
                    if (status != 'confirmed') return false;
                    return data['isImmediate'] == true ||
                        data['barberDeparting'] == true;
                  }).toList();
                  if (activeDocs.isEmpty) return const SizedBox.shrink();
                  final doc = activeDocs.first;
                  final barberName =
                      (doc.data() as Map<String, dynamic>)['barberName'] ??
                      'Tu barbero';
                  return _LiveTrackingBanner(
                    barberName: barberName,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BarberTrackingScreen(
                          appointmentId: doc.id,
                          barberName: barberName,
                        ),
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: _tabs),
              ),
            ],
          ),

          // ── Panel de servicio activo (en_servicio) o completado ───────
          if (_enServicioApptId != null &&
              !(_activeApptStatus == 'completed' && _completedDismissed))
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ServiceActivePanel(
                barberName: _enServicioBarberName ?? 'Tu barbero',
                isCompleted: _activeApptStatus == 'completed',
                showSos: _showSos,
                onSosActivated: _activateSos,
                onDismiss: _dismissCompleted,
                onReview: _openBarberReview,
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
              icon: Icon(Icons.star_outline_rounded),
              selectedIcon: Icon(Icons.star_rounded),
              label: 'Favoritos',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Citas',
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

// ── Banner en vivo: "Tu barbero está en camino" ───────────────────────
class _LiveTrackingBanner extends StatelessWidget {
  final String barberName;
  final VoidCallback onTap;
  const _LiveTrackingBanner({required this.barberName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const gradientColors = [Color(0xFF1565C0), Color(0xFF1E88E5)];
    const icon = Icons.two_wheeler;
    final title = '$barberName está en camino';
    const subtitle = 'Toca para ver su ubicación en tiempo real';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradientColors),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
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

// ── Panel servicio activo (en_servicio) o completado ─────────────────
class _ServiceActivePanel extends StatelessWidget {
  final String barberName;
  final bool isCompleted;
  final bool showSos;
  final VoidCallback onSosActivated;
  final VoidCallback onDismiss;
  final VoidCallback onReview;

  const _ServiceActivePanel({
    required this.barberName,
    required this.isCompleted,
    required this.showSos,
    required this.onSosActivated,
    required this.onDismiss,
    required this.onReview,
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
      child: isCompleted ? _buildCompleted(context) : _buildInService(),
    );
  }

  Widget _buildInService() {
    return Row(
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
              Text(
                '¡$barberName está en tu puerta!',
                style: AppTextStyles.title,
              ),
              const SizedBox(height: 2),
              Text(
                'Tu servicio de barbería comienza ahora',
                style: AppTextStyles.caption,
              ),
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
    );
  }

  Widget _buildCompleted(BuildContext context) {
    return Column(
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
          '¡Tu cita ha terminado!',
          style: AppTextStyles.title,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'No olvides dejar tu reseña a $barberName',
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
  final VoidCallback onOpenEmergencyContacts;
  const _ClientNotificationsPanel({
    required this.clientUid,
    required this.onOpenEmergencyContacts,
  });

  @override
  State<_ClientNotificationsPanel> createState() =>
      _ClientNotificationsPanelState();
}

class _ClientNotificationsPanelState extends State<_ClientNotificationsPanel> {
  Set<String> _dismissedIds = {};
  bool _sosEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('dismissed_notif_ids_client') ?? [];
    final sos = prefs.getBool('sos_button_enabled') ?? true;
    if (mounted) {
      setState(() {
        _dismissedIds = saved.toSet();
        _sosEnabled = sos;
      });
    }
  }

  Future<void> _toggleSos(bool value) async {
    if (value) {
      final has = await EmergencyContactsDialog.hasContacts();
      if (!has) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Sin contactos de emergencia',
              style: AppTextStyles.display(size: 17),
            ),
            content: Text(
              'Para activar el botón SOS debes añadir al menos un contacto de emergencia.',
              style: AppTextStyles.ui(size: 13, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogCtx).pop(); // cierra diálogo
                  widget
                      .onOpenEmergencyContacts(); // cierra panel + navega a perfil
                },
                child: Text(
                  'Añadir contactos',
                  style: AppTextStyles.ui(
                    size: 13,
                    color: AppColors.gold,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sos_button_enabled', value);
    if (mounted) setState(() => _sosEnabled = value);
  }

  Future<void> _dismissOne(String id) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds.add(id);
    await prefs.setStringList(
      'dismissed_notif_ids_client',
      _dismissedIds.toList(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _clearAll(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds.addAll(ids);
    await prefs.setStringList(
      'dismissed_notif_ids_client',
      _dismissedIds.toList(),
    );
    if (mounted) setState(() {});
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} dÃ­as';
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
              .where('clientUid', isEqualTo: widget.clientUid)
              .snapshots(),
          builder: (context, snap) {
            final allDocs = snap.data?.docs ?? [];

            // Pending = esperando respuesta del barbero
            final pending = allDocs
                .where(
                  (d) =>
                      (d.data() as Map)['status'] == 'pending' &&
                      !_dismissedIds.contains('${d.id}_pending'),
                )
                .toList();

            // Actividad reciente = confirmadas/rechazadas/canceladas últimos 7 días
            final recent =
                allDocs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final status = data['status'] as String? ?? '';
                  final ts =
                      (data['createdAt'] ?? data['scheduledAt']) as Timestamp?;
                  if (ts == null) return false;
                  return (status == 'confirmed' ||
                          status == 'en_servicio' ||
                          status == 'rejected' ||
                          status == 'cancelled' ||
                          status == 'completed') &&
                      ts.compareTo(sevenDaysAgo) >= 0 &&
                      !_dismissedIds.contains('${d.id}_$status');
                }).toList()..sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  final ta =
                      ((dataA['createdAt'] ?? dataA['scheduledAt'])
                              as Timestamp?)
                          ?.seconds ??
                      0;
                  final tb =
                      ((dataB['createdAt'] ?? dataB['scheduledAt'])
                              as Timestamp?)
                          ?.seconds ??
                      0;
                  return tb.compareTo(ta);
                });

            final totalCount = pending.length + recent.length;

            return Column(
              children: [
                // â”€â”€ Handle + header â”€â”€
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
                              'Tus solicitudes y actividad',
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
                          onPressed: () => _clearAll([
                            ...pending.map((d) => '${d.id}_pending'),
                            ...recent.map((d) {
                              final s =
                                  (d.data() as Map<String, dynamic>)['status']
                                      as String? ??
                                  '';
                              return '${d.id}_$s';
                            }),
                          ]),
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

                // ── Toggle SOS ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _sosEnabled
                            ? Colors.red.withValues(alpha: 0.35)
                            : AppColors.borderSubtle,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(
                              alpha: _sosEnabled ? 0.15 : 0.07,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.sos_rounded,
                            color: _sosEnabled
                                ? Colors.red.shade400
                                : AppColors.textTertiary,
                            size: 18,
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
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _sosEnabled
                                    ? 'Visible durante el servicio'
                                    : 'Desactivado',
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
                          activeTrackColor: Colors.red.withValues(alpha: 0.25),
                          inactiveThumbColor: AppColors.textTertiary,
                          inactiveTrackColor: AppColors.borderSubtle,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // â”€â”€ Contenido â”€â”€
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
                            // â”€â”€ SecciÃ³n: Solicitudes enviadas â”€â”€
                            if (pending.isNotEmpty) ...[
                              _ClientSectionLabel(
                                icon: Icons.schedule_rounded,
                                label:
                                    'Solicitudes enviadas  •  ${pending.length}',
                                color: AppColors.gold,
                              ),
                              const SizedBox(height: 8),
                              ...pending.map((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                final barberName = d['barberName'] ?? 'Barbero';
                                final serviceName = d['serviceName'] ?? '';
                                final price = (d['servicePrice'] ?? 0)
                                    .toDouble();
                                final duration =
                                    (d['serviceDuration'] ?? 0) as int;
                                final isImmediate = d['isImmediate'] ?? false;
                                final ts = d['scheduledAt'] as Timestamp?;
                                final dt = ts?.toDate() ?? DateTime.now();
                                final timeLabel = isImmediate
                                    ? 'Ahora mismo'
                                    : '${dt.day}/${dt.month}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                                return Dismissible(
                                  key: ValueKey('${doc.id}_pending'),
                                  direction: DismissDirection.startToEnd,
                                  onDismissed: (_) =>
                                      _dismissOne('${doc.id}_pending'),
                                  background: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.error.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                      size: 22,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Container(
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                              borderRadius:
                                                  BorderRadius.vertical(
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
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: const BoxDecoration(
                                                        color: AppColors
                                                            .goldSubtle,
                                                        shape: BoxShape.circle,
                                                        border:
                                                            Border.fromBorderSide(
                                                              BorderSide(
                                                                color: AppColors
                                                                    .borderAccent,
                                                              ),
                                                            ),
                                                      ),
                                                      child: const Icon(
                                                        Icons.content_cut,
                                                        size: 18,
                                                        color: AppColors.gold,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            barberName,
                                                            style:
                                                                AppTextStyles.display(
                                                                  size: 15,
                                                                ),
                                                          ),
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
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors
                                                            .goldSubtle,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              100,
                                                            ),
                                                        border: Border.all(
                                                          color: AppColors
                                                              .borderAccent,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        timeLabel,
                                                        style: AppTextStyles.ui(
                                                          size: 11,
                                                          weight:
                                                              FontWeight.w600,
                                                          color: AppColors.gold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppColors
                                                            .goldSubtle,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '\$$price',
                                                        style: AppTextStyles.ui(
                                                          size: 12,
                                                          weight:
                                                              FontWeight.w700,
                                                          color: AppColors.gold,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Icon(
                                                      Icons.timer_outlined,
                                                      size: 13,
                                                      color: AppColors
                                                          .textTertiary,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '$duration min',
                                                      style: AppTextStyles.ui(
                                                        size: 12,
                                                        color: AppColors
                                                            .textSecondary,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    // Indicador pulsante “esperando”
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Container(
                                                          width: 6,
                                                          height: 6,
                                                          decoration:
                                                              BoxDecoration(
                                                                color: AppColors
                                                                    .warning,
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        Text(
                                                          'Esperando...',
                                                          style:
                                                              AppTextStyles.ui(
                                                                size: 11,
                                                                weight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: AppColors
                                                                    .warning,
                                                              ),
                                                        ),
                                                      ],
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
                              }),
                            ],

                            // ── Sección: Actividad reciente ──
                            if (recent.isNotEmpty) ...[
                              if (pending.isNotEmpty) const SizedBox(height: 6),
                              _ClientSectionLabel(
                                icon: Icons.history_rounded,
                                label: 'Actividad reciente',
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              ...recent.map((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                final barberName = d['barberName'] ?? 'Barbero';
                                final serviceName = d['serviceName'] ?? '';
                                final status = d['status'] as String? ?? '';
                                final cancelledBy = d['cancelledBy'] as String?;
                                final ts =
                                    (d['createdAt'] ?? d['scheduledAt'])
                                        as Timestamp?;
                                final dt = ts?.toDate() ?? DateTime.now();
                                final timeAgo = _timeAgo(dt);

                                Color statusColor;
                                IconData statusIcon;
                                String statusLabel;
                                switch (status) {
                                  case 'confirmed':
                                    statusColor = AppColors.success;
                                    statusIcon = Icons.check_circle_outline;
                                    statusLabel = 'Confirmada';
                                    break;
                                  case 'en_servicio':
                                    statusColor = AppColors.gold;
                                    statusIcon = Icons.where_to_vote_rounded;
                                    statusLabel = '¡Barbero en la puerta!';
                                    break;
                                  case 'rejected':
                                    statusColor = AppColors.error;
                                    statusIcon = Icons.cancel_outlined;
                                    statusLabel = 'Rechazada';
                                    break;
                                  case 'cancelled':
                                    statusColor = AppColors.warning;
                                    statusIcon = Icons.event_busy;
                                    if (cancelledBy == widget.clientUid) {
                                      statusLabel = 'Cancelaste la cita';
                                    } else {
                                      statusLabel = '$barberName canceló';
                                    }
                                    break;
                                  case 'completed':
                                    statusColor = AppColors.teal;
                                    statusIcon = Icons.task_alt_rounded;
                                    statusLabel = '¡Cita completada!';
                                    break;
                                  default:
                                    statusColor = AppColors.gold;
                                    statusIcon = Icons.task_alt_rounded;
                                    statusLabel = status;
                                }

                                final displayText = status == 'cancelled'
                                    ? statusLabel
                                    : '$statusLabel · $barberName';

                                return Dismissible(
                                  key: ValueKey('${doc.id}_$status'),
                                  direction: DismissDirection.startToEnd,
                                  onDismissed: (_) =>
                                      _dismissOne('${doc.id}_$status'),
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
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ClientSectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ClientSectionLabel({
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
