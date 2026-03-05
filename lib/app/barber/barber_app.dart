import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../shared/app_config.dart';
import '../shared/splash_screen.dart';

class BarberApp extends StatelessWidget {
  const BarberApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YaCut - Barbero',
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF0CBCCC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0CBCCC),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF050814),
        fontFamily: 'Roboto',
      ),
      builder: (context, child) {
        return AppConfig(
          appType: AppType.barber,
          child: child!,
        );
      },
      home: const SplashScreen(),
    );
  }
}
