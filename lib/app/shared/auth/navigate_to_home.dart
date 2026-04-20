import 'package:flutter/material.dart';

import '../app_config.dart';
import '../../client/screens/client_home_screen.dart';
import '../../barber/screens/barber_home_screen.dart';

/// Navega a la pantalla Home correcta según el tipo de app.
/// Si [returnAfterAuth] es true, regresa al flujo anterior en lugar de ir al home.
void navigateToHome(BuildContext context, {bool returnAfterAuth = false}) {
  if (returnAfterAuth) {
    // Regresar al flujo anterior indicando que el login fue exitoso
    Navigator.of(context).pop(true);
    return;
  }

  final config = AppConfig.of(context);
  final Widget home = config.isClient
      ? const ClientHomeScreen()
      : const BarberHomeScreen();

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => home),
    (route) => false,
  );
}
