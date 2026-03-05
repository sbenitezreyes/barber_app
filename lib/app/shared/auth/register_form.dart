import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app_config.dart';
import 'google_auth_service.dart';
import 'navigate_to_home.dart';
import 'terms_screen.dart';

class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _acceptTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveUserProfile(User user, AppType appType) async {
    final role = appType == AppType.client ? 'client' : 'barber';

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': [role],
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final credential = await GoogleAuthService.signInWithGoogle();
      if (credential == null) return; // usuario canceló
      if (!context.mounted) return;
      navigateToHome(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error con Google: $e')),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar los términos y condiciones')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final appConfig = AppConfig.of(context);

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await credential.user?.updateDisplayName(_nameController.text.trim());

      final user = credential.user;
      if (user != null) {
        await _saveUserProfile(user, appConfig.appType);
      }

      try {
        await credential.user?.sendEmailVerification();
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cuenta creada con éxito. Revisa tu correo para verificarla.',
          ),
        ),
      );

      navigateToHome(context);
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'email-already-in-use') {
        message = 'Este correo ya está registrado';
      } else if (e.code == 'invalid-email') {
        message = 'Correo inválido';
      } else if (e.code == 'weak-password') {
        message = 'La contraseña es demasiado débil';
      } else {
        message = 'Error: ${e.message}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) { 
                if (value == null || value.isEmpty) {
                  return 'Ingresa tu nombre';
                }
                if (value.length < 3) {
                  return 'Nombre muy corto';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingresa tu correo';
                }
                if (!value.contains('@')) {
                  return 'Correo no válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Crea una contraseña';
                }
                if (value.length < 6) {
                  return 'Mínimo 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'Confirmar contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Confirma tu contraseña';
                }
                if (value != _passwordController.text) {
                  return 'Las contraseñas no coinciden';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _acceptTerms,
                  onChanged: (value) {
                    setState(() => _acceptTerms = value ?? false);
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {},
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(text: 'Acepto los '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ),
                              child: const Text(
                                'términos y condiciones',
                                style: TextStyle(
                                  color: Color(0xFFE94560),
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFFE94560),
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(
                            text: ' y la política de privacidad de YaCut.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear cuenta'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _signInWithGoogle(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.grey[700]!),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
              label: const Text('Registrarme con Google'),
            ),
          ],
        ),
      ),
    );
  }
}
