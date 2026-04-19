import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../shared/app_config.dart';
import '../shared/splash_screen.dart';
import '../shared/theme/app_theme.dart';

class BarberApp extends StatelessWidget {
  const BarberApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YaCut - Barbero',
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
      theme: buildAppTheme(),
      builder: (context, child) {
        return AppConfig(appType: AppType.barber, child: child!);
      },
      home: const SplashScreen(),
    );
  }
}
