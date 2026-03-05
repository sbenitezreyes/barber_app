import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_config.dart';
import 'auth/auth_screen.dart';
import '../client/screens/client_home_screen.dart';
import '../barber/screens/barber_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _goToAuth();
  }

  Future<void> _goToAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Sesión activa: ir directo al home
      final config = AppConfig.of(context);
      final Widget home = config.isClient
          ? const ClientHomeScreen()
          : const BarberHomeScreen();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => home),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = AppConfig.of(context);
    final isClient = config.isClient;

    final subtitle = isClient
        ? 'Pide tu barbero a domicilio en minutos.'
        : 'Gestiona tus citas y haz crecer tu negocio.';
    final icon = isClient ? Icons.content_cut : Icons.work_outline;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isClient
                ? [const Color(0xFF15297C), const Color(0xFF0CBCCC)]
                : [const Color(0xFF1A1A2E), const Color(0xFF16213E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                  gradient: const LinearGradient(
                    colors: [Color(0xFF212226), Color(0xFF111217)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Bienvenido a YaCut',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              if (!isClient)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'MODO BARBERO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Colors.white70,
                    ),
                  ),
                ),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[400],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
