import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/splash_screen.dart';
import '../../../shared/guest_auth_prompt.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/auth/terms_screen.dart';
import '../../../shared/help_screen.dart';
import '../addresses_screen.dart';
import '../edit_profile_screen.dart';
import '../emergency_contacts_dialog.dart';
import '../notifications_screen.dart';
import '../welcome_dialog.dart';

const _clientFaqs = <({String q, String a})>[
  (
    q: '¿Cómo reservo una cita?',
    a: 'En la pestaña Inicio, busca un barbero disponible cerca de ti y toca su tarjeta. Desde su perfil podrás ver sus servicios, horarios y reservar al instante o programar una cita.',
  ),
  (
    q: '¿Puedo cancelar mi cita?',
    a: 'Sí. Ve a la pestaña Mis citas, selecciona la cita activa y toca "Cancelar cita". Puedes cancelar mientras la cita esté en estado pendiente o confirmada.',
  ),
  (
    q: '¿Qué pasa si el barbero rechaza mi solicitud?',
    a: 'Recibirás una notificación informándote del rechazo. Puedes buscar otro barbero disponible y hacer una nueva reserva sin problema.',
  ),
  (
    q: '¿Cómo sé cuándo el barbero está en camino?',
    a: 'Una vez confirmada tu cita, podrás ver la ubicación en tiempo real del barbero desde la pantalla de seguimiento. Recibirás también una notificación cuando empiece a moverse.',
  ),
  (
    q: '¿Cómo valoro al barbero?',
    a: 'Después de que tu cita sea marcada como completada, aparecerá la opción de dejar una valoración en la pestaña Mis citas. Tu opinión ayuda a la comunidad.',
  ),
  (
    q: '¿Mis datos están seguros?',
    a: 'Sí. YaCut usa Firebase con cifrado en tránsito y en reposo. Tu información personal solo es accesible por ti y por el barbero con quien reservas.',
  ),
  (
    q: '¿Cómo guardo un barbero en favoritos?',
    a: 'Entra al perfil del barbero y toca el ícono de estrella. Lo encontrarás guardado en la pestaña Favoritos para reservar más rápido la próxima vez.',
  ),
  (
    q: '¿Por qué no veo barberos cerca?',
    a: 'Puede que no haya barberos activos en tu zona en este momento, o que la app no tenga permiso de ubicación. Verifica que el GPS esté activado e inténtalo más tarde.',
  ),
  (
    q: '¿Cómo cambio mi foto o datos personales?',
    a: 'Ve a Perfil → Editar perfil. Desde ahí puedes actualizar tu nombre y foto de perfil.',
  ),
  (
    q: '¿Qué tipos de servicios ofrecen los barberos?',
    a: 'Cada barbero define sus propios servicios: corte, arreglo de barba, degradado, entre otros. Puedes verlos en el perfil del barbero antes de reservar.',
  ),
  (
    q: '¿El barbero viene a mi ubicación?',
    a: 'Sí. YaCut es un servicio a domicilio, el barbero se desplaza hasta donde estés.',
  ),
  (
    q: '¿Qué pasa si el barbero no llega a la cita?',
    a: 'Puedes cancelar la cita desde Mis citas. Además te recomendamos dejar una valoración con pocas estrellas para que la comunidad tenga información real sobre ese barbero.',
  ),
];

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // Refresca el widget para releer FirebaseAuth.instance.currentUser
  void _refresh() => setState(() {});

  void _openEditProfile() {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (_, animation, __) => const ClientEditProfileScreen(),
            transitionsBuilder: (_, animation, __, child) {
              final offset =
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  );
              return SlideTransition(position: offset, child: child);
            },
          ),
        )
        .then((updated) async {
          if (updated == true && mounted) {
            await FirebaseAuth.instance.currentUser?.reload();
            if (mounted) _refresh();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    if (isGuest) {
      return const _GuestDemoProfile();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // ── Avatar ──
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.surfaceElevated,
            child: user.photoURL != null
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: user.photoURL!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(
                    Icons.person,
                    size: 50,
                    color: AppColors.textTertiary,
                  ),
          ),
          const SizedBox(height: 14),
          Text(user.displayName ?? 'Cliente', style: AppTextStyles.title),
          const SizedBox(height: 4),
          Text(user.email ?? '', style: AppTextStyles.caption),
          const SizedBox(height: 24),

          // ── Opciones ──
          _ProfileTile(
            icon: Icons.person_outline,
            label: 'Editar perfil',
            onTap: _openEditProfile,
          ),
          _ProfileTile(
            icon: Icons.location_on_outlined,
            label: 'Mis direcciones',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => const AddressesScreen(),
                transitionsBuilder: (_, animation, __, child) {
                  final offset =
                      Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                  return SlideTransition(position: offset, child: child);
                },
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.shield_outlined,
            label: 'Contactos de emergencia',
            onTap: () => EmergencyContactsDialog.openFromProfile(context),
          ),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            label: 'Notificaciones',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => const NotificationsScreen(),
                transitionsBuilder: (_, animation, __, child) {
                  final offset =
                      Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                  return SlideTransition(position: offset, child: child);
                },
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            label: 'Ayuda y soporte',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) =>
                    const HelpScreen(faqs: _clientFaqs),
                transitionsBuilder: (_, animation, __, child) {
                  final offset =
                      Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                  return SlideTransition(position: offset, child: child);
                },
              ),
            ),
          ),
          _ProfileTile(
            icon: Icons.description_outlined,
            label: 'Términos y condiciones',
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, animation, __) => const TermsScreen(),
                transitionsBuilder: (_, animation, __, child) {
                  final offset =
                      Tween<Offset>(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      );
                  return SlideTransition(position: offset, child: child);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.borderSubtle),
          const SizedBox(height: 8),

          // ── Cerrar sesión ──
          _ProfileTile(
            icon: Icons.logout,
            label: 'Cerrar sesión',
            iconColor: AppColors.error,
            labelColor: AppColors.error,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              await WelcomeDialog.reset();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashScreen()),
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 24),
          Text('YaCut v1.0.0', style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

// ── Perfil demo para invitados ───────────────────────────────────
class _GuestDemoProfile extends StatelessWidget {
  const _GuestDemoProfile();

  @override
  Widget build(BuildContext context) {
    const demoOptions = [
      (Icons.person_outline, 'Editar perfil'),
      (Icons.location_on_outlined, 'Mis direcciones'),
      (Icons.notifications_outlined, 'Notificaciones'),
      (Icons.help_outline, 'Ayuda y soporte'),
      (Icons.description_outlined, 'Términos y condiciones'),
    ];

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // Avatar genérico
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceElevated,
                    border: Border.all(color: AppColors.borderAccent, width: 2),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    size: 52,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 14),

                Text('Explorador', style: AppTextStyles.title),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.goldSubtle,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppColors.borderAccent),
                  ),
                  child: Text(
                    'Modo invitado',
                    style: AppTextStyles.ui(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.gold,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Opciones deshabilitadas (aspecto real, pero no interactivas)
                ...demoOptions.map(
                  (opt) => Opacity(
                    opacity: 0.4,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: Icon(opt.$1, color: AppColors.textSecondary),
                        title: Text(opt.$2, style: AppTextStyles.body),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(color: AppColors.borderSubtle),
                const SizedBox(height: 8),

                Opacity(
                  opacity: 0.4,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: AppColors.error),
                      title: Text(
                        'Cerrar sesión',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Text('YaCut v1.0.0', style: AppTextStyles.caption),
              ],
            ),
          ),
        ),
        const GuestCtaBanner(
          message: 'Crea una cuenta para personalizar tu perfil',
        ),
      ],
    );
  }
}

// ── Tile genérico ────────────────────────────────────────────────
class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  const _ProfileTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: iconColor ?? AppColors.textSecondary),
        title: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: labelColor ?? AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textTertiary,
          size: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
