import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_config.dart';
import '../theme/app_theme.dart';
import 'google_auth_service.dart';
import 'navigate_to_home.dart';

class LoginForm extends StatefulWidget {
  final bool returnAfterAuth;

  const LoginForm({super.key, this.returnAfterAuth = false});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final credential = await GoogleAuthService.signInWithGoogle();
      if (credential == null) return;
      if (!context.mounted) return;
      navigateToHome(context, returnAfterAuth: widget.returnAfterAuth);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error con Google: $e')));
    }
  }

  Future<void> _ensureRoleExists(User user) async {
    final appConfig = AppConfig.of(context);
    final role = appConfig.isClient ? 'client' : 'barber';
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();
    if (doc.exists) {
      final roles = List<String>.from(doc.data()?['role'] ?? []);
      if (!roles.contains(role)) {
        await docRef.update({
          'role': FieldValue.arrayUnion([role]),
        });
      }
    } else {
      await docRef.set({
        'email': user.email,
        'name': user.displayName ?? '',
        'role': [role],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // Si es barbero nuevo, crear horario por defecto en subcollección
    if (role == 'barber' && !doc.exists) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('schedule')
          .doc('config')
          .set({
            'monday': {
              'enabled': true,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
            'tuesday': {
              'enabled': true,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
            'wednesday': {
              'enabled': true,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
            'thursday': {
              'enabled': true,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
            'friday': {
              'enabled': true,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
            'saturday': {
              'enabled': false,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
            'sunday': {
              'enabled': false,
              'intervals': [{'open': '08:00', 'close': '18:00'}]
            },
          });
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa tu correo primero')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Correo de recuperación enviado a $email')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = e.code == 'user-not-found'
          ? 'No existe una cuenta con ese correo'
          : 'Error: ${e.message}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (credential.user != null) {
        await _ensureRoleExists(credential.user!);
        // Hacer reload para asegurar que todos los datos estén sincronizados
        await FirebaseAuth.instance.currentUser?.reload();
      }
      if (!mounted) return;
      navigateToHome(context, returnAfterAuth: widget.returnAfterAuth);
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = 'Usuario no encontrado';
      } else if (e.code == 'wrong-password') {
        message = 'Contraseña incorrecta';
      } else {
        message = 'Error: ${e.message}';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: AppTextStyles.ui(size: 14),
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresa tu correo';
                if (!v.contains('@')) return 'Correo no válido';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Contraseña
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: AppTextStyles.ui(size: 14),
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
                if (v.length < 6) return 'Mínimo 6 caracteres';
                return null;
              },
            ),

            // Olvidé contraseña
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 0,
                  ),
                ),
                child: Text(
                  '¿Olvidaste tu contraseña?',
                  style: AppTextStyles.ui(
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Botón principal
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : Text('Iniciar sesión', style: AppTextStyles.button),
              ),
            ),

            const SizedBox(height: 24),

            // Divisor
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.borderMedium)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text('o', style: AppTextStyles.caption),
                ),
                const Expanded(child: Divider(color: AppColors.borderMedium)),
              ],
            ),

            const SizedBox(height: 20),

            // Google
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => _signInWithGoogle(context),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoogleIcon(),
                    const SizedBox(width: 10),
                    Text(
                      'Continuar con Google',
                      style: AppTextStyles.button.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Mini ícono de Google en SVG simplificado (texto)
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF4285F4),
      ),
    );
  }
}
