import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';

// ── Modelo ───────────────────────────────────────────────────────────
class EmergencyContact {
  final String name;
  final String phone;
  const EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}

// ── API pública ──────────────────────────────────────────────────────
class EmergencyContactsDialog {
  /// Devuelve `true` si el usuario ya tiene contactos guardados en Firestore.
  static Future<bool> hasContacts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final contacts = doc.data()?['emergencyContacts'] as List?;
    return contacts != null && contacts.isNotEmpty;
  }

  /// Abre el formulario directamente desde el perfil.
  /// Pre-llena los campos si el usuario ya tiene contactos guardados.
  static Future<void> openFromProfile(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    List<Map<String, dynamic>> existing = [];
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final contacts = doc.data()?['emergencyContacts'] as List?;
    if (contacts != null) {
      existing = contacts
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    if (!context.mounted) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => _EmergencyContactsSheet(existing: existing),
    );
  }

  /// Verifica si el usuario ya tiene contactos de emergencia guardados.
  /// Si no los tiene, muestra el bottom sheet explicativo.
  /// Retorna `true` si se puede continuar (ya los tenía, los guardó,
  /// o eligió "Tal vez luego"). Retorna `false` solo si cerró sin elegir.
  static Future<bool> checkAndPrompt(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true; // usuario no autenticado: no bloquear

    // Verificar en Firestore si ya tiene contactos
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data() ?? {};
    final contacts = data['emergencyContacts'] as List?;
    if (contacts != null && contacts.isNotEmpty) return true;

    // No tiene contactos → mostrar el sheet
    if (!context.mounted) return true;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _EmergencyContactsSheet(),
    );
    // null = cerró sin tocar nada (no debería ocurrir con isDismissible: false)
    return result ?? false;
  }
}

// ── Sheet ─────────────────────────────────────────────────────────────
class _EmergencyContactsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> existing;
  const _EmergencyContactsSheet({this.existing = const []});

  @override
  State<_EmergencyContactsSheet> createState() =>
      _EmergencyContactsSheetState();
}

class _EmergencyContactsSheetState extends State<_EmergencyContactsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name1 = TextEditingController();
  final _phone1 = TextEditingController();
  final _name2 = TextEditingController();
  final _phone2 = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing.isNotEmpty) {
      _name1.text = widget.existing[0]['name'] as String? ?? '';
      _phone1.text = widget.existing[0]['phone'] as String? ?? '';
      if (widget.existing.length > 1) {
        _name2.text = widget.existing[1]['name'] as String? ?? '';
        _phone2.text = widget.existing[1]['phone'] as String? ?? '';
      }
    }
  }

  @override
  void dispose() {
    _name1.dispose();
    _phone1.dispose();
    _name2.dispose();
    _phone2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final contacts = [
        EmergencyContact(name: _name1.text.trim(), phone: _phone1.text.trim()),
        EmergencyContact(name: _name2.text.trim(), phone: _phone2.text.trim()),
      ];
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'emergencyContacts': contacts.map((c) => c.toMap()).toList(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al guardar. Intenta de nuevo.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.92,
      maxChildSize: 0.98,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: EdgeInsets.fromLTRB(24, 0, 24, bottomInset + 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Handle ──
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.borderAccent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Ícono principal ──
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.error,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Título ──
                Center(
                  child: Text(
                    'Contactos de emergencia',
                    style: AppTextStyles.display(size: 22),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Tu seguridad es nuestra prioridad',
                    style: AppTextStyles.ui(
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Explicación ──
                _InfoCard(
                  icon: Icons.help_outline_rounded,
                  title: '¿Por qué te pedimos esto?',
                  body:
                      'YaCut conecta barberos profesionales con clientes en casa. '
                      'Para brindarte la mayor tranquilidad posible, te pedimos '
                      'dos personas de confianza a quienes puedas acudir si algo '
                      'no sale como esperabas.',
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.notifications_active_outlined,
                  title: '¿Qué haremos con ellos?',
                  body:
                      '• Cuando el barbero llegue a tu puerta, podrás enviarle '
                      'al instante el nombre, foto y verificación del barbero a '
                      'estos contactos con un solo toque.\n\n'
                      '• Si activas el botón SOS dentro de la app, tu teléfono '
                      'abrirá WhatsApp o SMS con un mensaje pre-llenado dirigido '
                      'a tus contactos de emergencia.\n\n'
                      '• Nadie más verá esta información. No la compartimos con '
                      'el barbero ni con terceros.',
                ),
                const SizedBox(height: 28),

                // ── Formulario contacto 1 ──
                _ContactSection(
                  number: 1,
                  nameCtrl: _name1,
                  phoneCtrl: _phone1,
                ),
                const SizedBox(height: 20),

                // ── Formulario contacto 2 ──
                _ContactSection(
                  number: 2,
                  nameCtrl: _name2,
                  phoneCtrl: _phone2,
                ),
                const SizedBox(height: 32),

                // ── Botón guardar ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black87,
                            ),
                          )
                        : const Icon(Icons.shield_rounded, size: 18),
                    label: Text(
                      _saving ? 'Guardando...' : 'Guardar y continuar',
                      style: AppTextStyles.ui(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Tal vez luego ──
                Center(
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tal vez luego',
                          style: AppTextStyles.ui(
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Puedes agregarlos después en tu perfil',
                          style: AppTextStyles.ui(
                            size: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tarjeta informativa ───────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.goldSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Icon(icon, color: AppColors.gold, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.ui(size: 13, weight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: AppTextStyles.ui(
                    size: 12,
                    color: AppColors.textSecondary,
                  ).copyWith(height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sección de un contacto ────────────────────────────────────────────
class _ContactSection extends StatelessWidget {
  final int number;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;

  const _ContactSection({
    required this.number,
    required this.nameCtrl,
    required this.phoneCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Encabezado
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.goldSubtle,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderAccent),
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: AppTextStyles.ui(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Contacto $number',
              style: AppTextStyles.ui(size: 14, weight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Nombre
        _Field(
          controller: nameCtrl,
          hint: 'Nombre completo (ej. Mamá, Juan Pérez)',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.name,
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Ingresa el nombre del contacto $number';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),

        // Teléfono
        _Field(
          controller: phoneCtrl,
          hint: 'Número de WhatsApp o celular',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
          ],
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Ingresa el número del contacto $number';
            }
            final digits = v.replaceAll(RegExp(r'\D'), '');
            if (digits.length < 7) return 'Número demasiado corto';
            return null;
          },
        ),
      ],
    );
  }
}

// ── Campo de texto ────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: AppTextStyles.ui(size: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.ui(size: 13, color: AppColors.textTertiary),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}
