import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/barber/barber_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('es_ES', null);

  // Pre-inicializar el renderer de Google Maps para evitar el freeze en la
  // primera visita a la tab Mapa. Se ejecuta antes de runApp para que el SDK
  // tenga tiempo de inicializarse mientras el usuario está en la pantalla de
  // splash / autenticación.
  final mapsImpl = GoogleMapsFlutterPlatform.instance;
  if (mapsImpl is GoogleMapsFlutterAndroid) {
    try {
      await mapsImpl.initializeWithRenderer(AndroidMapRenderer.latest);
    } catch (_) {
      // El renderer ya fue inicializado (hot restart) — se puede ignorar
    }
  }

  runApp(const BarberApp());
}
