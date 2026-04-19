import 'package:flutter/material.dart';

enum AppType { client, barber }

/// InheritedWidget que permite a cualquier widget del árbol
/// saber si la app se está ejecutando como cliente o como barbero.
class AppConfig extends InheritedWidget {
  final AppType appType;

  const AppConfig({super.key, required this.appType, required super.child});

  static AppConfig of(BuildContext context) {
    final config = context.dependOnInheritedWidgetOfExactType<AppConfig>();
    assert(config != null, 'AppConfig no encontrado en el árbol de widgets');
    return config!;
  }

  bool get isClient => appType == AppType.client;
  bool get isBarber => appType == AppType.barber;

  @override
  bool updateShouldNotify(AppConfig oldWidget) => appType != oldWidget.appType;
}
