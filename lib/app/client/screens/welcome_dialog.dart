import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../shared/auth/auth_screen.dart';

/// Diálogo de bienvenida que se muestra cuando el usuario es invitado
class WelcomeDialog extends StatelessWidget {
  const WelcomeDialog({super.key});

  static const String _prefsKey = 'has_seen_welcome_dialog_for_guest';

  /// Verifica si el usuario es invitado y muestra el diálogo si es necesario
  static Future<void> showIfFirstTime(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;

    // Solo mostrar si es invitado
    if (!isGuest) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeenDialog = prefs.getBool(_prefsKey) ?? false;

    if (!hasSeenDialog && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const WelcomeDialog(),
      );
      await prefs.setBool(_prefsKey, true);
    }
  }

  /// Reinicia el estado del diálogo (útil cuando el usuario cierra sesión)
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botón X para cerrar
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            // Icono principal
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.1),
              ),
              child: Icon(
                Icons.content_cut_rounded,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Título
            Text(
              '¡Bienvenido a YaCut!',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Descripción
            Text(
              'Encuentra barberos cerca de ti y agenda tu cita en minutos.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[400],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Características
            _FeatureItem(
              icon: Icons.map_outlined,
              title: 'Explora el mapa',
              description: 'Ve barberos disponibles cerca de tu ubicación',
            ),
            const SizedBox(height: 16),
            _FeatureItem(
              icon: Icons.person_outline,
              title: 'Revisa perfiles',
              description: 'Mira fotos, servicios y reseñas de cada barbero',
            ),
            const SizedBox(height: 16),
            _FeatureItem(
              icon: Icons.calendar_today_outlined,
              title: 'Agenda tu cita',
              description: 'Elige fecha y hora que más te convenga',
            ),
            const SizedBox(height: 28),

            // Nota
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Para confirmar citas y guardar favoritos, necesitarás crear una cuenta',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[300],
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Botón de comenzar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Comenzar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Botón de iniciar sesión
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Cerrar el diálogo
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Iniciar sesión',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withOpacity(0.15),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
