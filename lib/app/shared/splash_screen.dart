import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'app_config.dart';
import 'auth/auth_screen.dart';
import 'theme/app_theme.dart';
import '../client/screens/client_home_screen.dart';
import '../barber/screens/barber_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _lineExpand;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
          ),
        );
    _lineExpand = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );

    _ctrl.forward();
    _goToAuth();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _goToAuth() async {
    // Esperar la animación y que Firebase restaure la sesión persistida
    final authFuture = FirebaseAuth.instance.authStateChanges().first;
    await Future.delayed(const Duration(milliseconds: 2400));
    final user = await authFuture.timeout(
      const Duration(seconds: 6),
      onTimeout: () => FirebaseAuth.instance.currentUser,
    );
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final config = AppConfig.of(context);

    // Pedir permiso de ubicación para la app cliente antes de cargar el mapa
    if (config.isClient) {
      await _requestLocationPermission();
    }
    if (!mounted) return;

    if (user != null && !user.isAnonymous) {
      if (!mounted) return;
      final destination = config.isClient
          ? const ClientHomeScreen()
          : const BarberHomeScreen();
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
    } else {
      if (config.isClient) {
        try {
          await FirebaseAuth.instance.signInAnonymously();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ClientHomeScreen()),
          );
        } catch (_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          );
        }
      } else {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.of(context);
    final isClient = config.isClient;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Fondo atmosférico — círculo de luz sutil
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isClient ? AppColors.gold : AppColors.teal).withValues(
                      alpha: 0.08,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Contenido central
          Center(
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icono — círculo con borde gold
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                          border: Border.all(
                            color: isClient ? AppColors.gold : AppColors.teal,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isClient ? AppColors.gold : AppColors.teal)
                                      .withValues(alpha: 0.20),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          isClient
                              ? Icons.content_cut_rounded
                              : Icons.work_outline_rounded,
                          size: 34,
                          color: isClient ? AppColors.gold : AppColors.teal,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Marca — serif display
                      Text(
                        'YaCut',
                        style: AppTextStyles.display(
                          size: 42,
                        ).copyWith(letterSpacing: 1, height: 1),
                      ),
                      const SizedBox(height: 10),

                      // Línea decorativa animada
                      AnimatedBuilder(
                        animation: _lineExpand,
                        builder: (_, __) => Container(
                          height: 1,
                          width: 80 * _lineExpand.value,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                isClient ? AppColors.gold : AppColors.teal,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Modo badge — solo para barbero
                      if (!isClient)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.teal.withValues(alpha: 0.4),
                            ),
                            borderRadius: BorderRadius.circular(100),
                            color: AppColors.tealSubtle,
                          ),
                          child: Text(
                            'MODO BARBERO',
                            style: AppTextStyles.ui(
                              size: 10,
                              weight: FontWeight.w700,
                              color: AppColors.teal,
                            ).copyWith(letterSpacing: 2),
                          ),
                        ),
                      if (!isClient) const SizedBox(height: 10),

                      // Tagline
                      Text(
                        isClient
                            ? 'Tu barbero, donde estés.'
                            : 'Gestiona tus citas con estilo.',
                        style: AppTextStyles.ui(
                          size: 14,
                          color: AppColors.textSecondary,
                        ).copyWith(letterSpacing: 0.3),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Indicador de carga — parte inferior
          Positioned(
            bottom: 52,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _lineExpand,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: (isClient ? AppColors.gold : AppColors.teal)
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
