import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_config.dart';
import '../theme/app_theme.dart';
import 'login_form.dart';
import 'register_form.dart';

class AuthScreen extends StatefulWidget {
  final bool returnAfterAuth;

  const AuthScreen({super.key, this.returnAfterAuth = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.of(context);
    final isClient = config.isClient;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Halo de luz atmosférico
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // ── Header ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icono pequeño + nombre marca
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surface,
                              border: Border.all(
                                color: isClient ? AppColors.gold : AppColors.teal,
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              isClient ? Icons.content_cut_rounded : Icons.work_outline_rounded,
                              size: 18,
                              color: isClient ? AppColors.gold : AppColors.teal,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'YaCut',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (!isClient) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.tealSubtle,
                                border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                'BARBERO',
                                style: GoogleFonts.figtree(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: AppColors.teal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Título editorial
                      Text(
                        isClient
                            ? 'Tu barbero,\na un toque.'
                            : 'Bienvenido\nde vuelta.',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isClient
                            ? 'Accede para reservar con tus barberos favoritos.'
                            : 'Gestiona tus citas y haz crecer tu negocio.',
                        style: GoogleFonts.figtree(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Tab Selector ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      labelColor: AppColors.background,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: GoogleFonts.figtree(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: GoogleFonts.figtree(fontSize: 13),
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: const [
                        Tab(text: 'Iniciar sesión'),
                        Tab(text: 'Registrarse'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Forms ───────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      LoginForm(returnAfterAuth: widget.returnAfterAuth),
                      RegisterForm(returnAfterAuth: widget.returnAfterAuth),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
