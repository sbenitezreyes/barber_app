import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Background message handler (top-level, required by FCM) ────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized by the app entry point.
  // Nothing extra needed here; FCM shows the notification automatically
  // when the app is in background/terminated.
  print('📲 [Barbero BACKGROUND] Mensaje recibido: ${message.notification?.title}');
  print('📲 [Barbero BACKGROUND] Datos: ${message.data}');
  
  // Señalizar que hay una nueva notificación para que el badge se actualice
  // cuando la app vuelva a foreground
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasNewNotification', true);
    print('✅ [Barbero BACKGROUND] Marcada nueva notificación');
  } catch (e) {
    print('❌ [Barbero BACKGROUND] Error guardando flag: $e');
  }
}

// ── Android notification channel ────────────────────────────────
const _androidChannel = AndroidNotificationChannel(
  'appointments_channel',
  'Nuevas citas',
  description: 'Notificaciones de solicitudes de cita',
  importance: Importance.max,
  playSound: true,
);

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;

  /// Call once from barber BarberHomeScreen.initState()
  Future<void> init({required BuildContext context}) async {
    // Si ya hay una inicialización completada o en curso, retornar
    if (_initFuture != null) return _initFuture;
    
    // Comenzar inicialización y manejar errores
    _initFuture = _doInit(context).catchError((e) {
      // En caso de error, resetear para permitir reintentos
      _initFuture = null;
      throw e;
    });
    
    return _initFuture;
  }
  
  Future<void> _doInit(BuildContext context) async {
    // 1. Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (iOS / Android 13+)
    try {
      print('🔔 [Barbero] Solicitando permisos de notificación...');
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('✅ [Barbero] Permisos otorgados: ${settings.authorizationStatus}');
    } catch (e) {
      // Ignorar si ya hay una solicitud en curso (ocurre en hot restart)
      if (!e.toString().contains('already running')) {
        print('❌ [Barbero] Error solicitando permisos: $e');
        rethrow;
      }
    }

    // 3. Create Android channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // 4. Initialise local notifications plugin
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);

    // 5. Save / refresh FCM token in Firestore
    await _saveToken();
    _messaging.onTokenRefresh.listen((newToken) {
      print('🔄 [Barbero] Token FCM renovado: ${newToken.substring(0, 20)}...');
      _saveToken();
    });

    // 6. Handle foreground messages (show local notification)
    print('👂 [Barbero] Configurando listener para mensajes en foreground...');
    FirebaseMessaging.onMessage.listen((msg) {
      print('📲 [Barbero FOREGROUND] Mensaje recibido!');
      print('📲 [Barbero] Título: ${msg.notification?.title}');
      print('📲 [Barbero] Cuerpo: ${msg.notification?.body}');
      print('📲 [Barbero] Datos: ${msg.data}');
      _showForegroundNotification(msg);
    });

    // 7. Handle tap on notification when app was in background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (context.mounted) _navigateToSchedule(context, msg);
    });

    // 8. App opened from a terminated state via notification tap
    final initial = await _messaging.getInitialMessage();
    if (initial != null && context.mounted) {
      _navigateToSchedule(context, initial);
    }
  }

  // ── Save FCM token ─────────────────────────────────────────
  Future<void> _saveToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('❌ [Barbero] No se puede guardar token FCM: usuario no autenticado');
      return;
    }
    final token = await _messaging.getToken();
    if (token == null) {
      print('❌ [Barbero] No se puede guardar token FCM: token es null');
      return;
    }
    print('✅ [Barbero] Token FCM actual en dispositivo: ${token.substring(0, 20)}...');
    
    // Verificar token guardado en Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    
    final savedToken = userDoc.data()?['fcmToken'] as String?;
    if (savedToken != null) {
      print('📋 [Barbero] Token guardado en Firestore: ${savedToken.substring(0, 20)}...');
      if (savedToken == token) {
        print('✅ [Barbero] Tokens coinciden - OK');
      } else {
        print('⚠️ [Barbero] Tokens NO coinciden - actualizando...');
      }
    } else {
      print('⚠️ [Barbero] No hay token guardado en Firestore - guardando por primera vez...');
    }
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
    print('✅ [Barbero] Token FCM guardado exitosamente en Firestore');
  }

  // ── Show local notification while app is foreground ────────
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    print('📲 [Barbero] Notificación recibida en foreground: ${notification.title}');

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
    
    // Limpiar cualquier flag de background
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasNewNotification', false);
    } catch (_) {}
    
    // Notificar al BarberHomeScreen para que actualice el badge
    print('🔔 [Barbero] Disparando evento para refrescar badge');
    notificationReceived.value = !notificationReceived.value;
  }

  // ── Navigate to Agenda tab when notification tapped ────────
  void _navigateToSchedule(BuildContext context, RemoteMessage message) {
    // We raise a global event via a ValueNotifier so BarberHomeScreen can switch tabs.
    scheduleTabRequested.value = !scheduleTabRequested.value;
  }
}

/// Listened to by BarberHomeScreen to switch to the Agenda tab.
final ValueNotifier<bool> scheduleTabRequested = ValueNotifier(false);

/// Listened to by BarberHomeScreen to refresh the notification badge.
final ValueNotifier<bool> notificationReceived = ValueNotifier(false);
