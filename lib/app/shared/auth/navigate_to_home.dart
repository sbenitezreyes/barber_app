import 'package:flutter/material.dart';

import '../app_config.dart';
import '../../client/screens/client_home_screen.dart';
import '../../barber/screens/barber_home_screen.dart';

/// Navega a la pantalla Home correcta según el tipo de app.
void navigateToHome(BuildContext context) {
  final config = AppConfig.of(context);
  final Widget home = config.isClient
      ? const ClientHomeScreen()
      : const BarberHomeScreen();

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => home),
    (route) => false,
  );
}
