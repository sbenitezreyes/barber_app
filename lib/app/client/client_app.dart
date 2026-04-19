import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../shared/app_config.dart';
import '../shared/splash_screen.dart';
import '../shared/theme/app_theme.dart';

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YaCut - Cliente',
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
      theme: buildAppTheme(),
      builder: (context, child) {
        return AppConfig(appType: AppType.client, child: child!);
      },
      home: const SplashScreen(),
    );
  }
}
