import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';

// ── API pública ──────────────────────────────────────────────────────
class BarberEmergencyContacts {
  /// Verifica si el barbero ya tiene contactos.
  /// Si no tiene → muestra el diálogo de explicación primero, luego el form.
  /// Si ya tiene → abre el form directamente (edición).
  static Future<void> openFromSettings(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    // SharedPreferences es instantáneo (disco local, sin red).
    // Lo usamos para saber si el diálogo explicativo ya se mostró antes,
    // evitando así bloquear la UI con una lectura Firestore antes de mostrar
    // cualquier pantalla.
    final prefs = await SharedPreferences.getInstance();
    final hasSeenExplanation = prefs.getBool('_sos_explained_$uid') ?? false;
    if (!context.mounted) return;

    if (!hasSeenExplanation) {
      // Mostrar la explicación de inmediato — sin leer Firestore primero
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ExplanationDialog(),
      );
      if (proceed != true || !context.mounted) return;
      // Guardar en background (no bloquea)
      prefs.setBool('_sos_explained_$uid', true);
    }

    // Para aquí la caché ya está caliente gracias al listener en
    // BarberSettingsTab._userDocSub, por lo que este get() es instantáneo.
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await ref.get();
    }
    final existing = ((doc.data()?['emergencyContacts'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _BarberContactsSheet(existing: existing),
    );
  }

  /// Abre el formulario directamente (desde la campanita al no tener contactos).
  static Future<void> openDirect(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await ref.get();
    }

    final existing = ((doc.data()?['emergencyContacts'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _BarberContactsSheet(existing: existing),
    );
  }

  /// Devuelve `true` si el barbero tiene al menos un contacto guardado.
  static Future<bool> hasContacts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await ref.get();
    }
    final list = doc.data()?['emergencyContacts'] as List?;
    return list != null && list.isNotEmpty;
  }
}

// ── Diálogo explicativo (primera vez) ────────────────────────────────
class _ExplanationDialog extends StatelessWidget {
  const _ExplanationDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
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
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Contactos de emergencia',
              style: AppTextStyles.display(size: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tu seguridad también es nuestra prioridad',
              style: AppTextStyles.ui(size: 13, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            _InfoRow(
              icon: Icons.help_outline_rounded,
              title: '¿Por qué te pedimos esto?',
              body:
                  'Como barbero, visitas casas de clientes que quizás no '
                  'conoces. Dos contactos de confianza pueden marcar la '
                  'diferencia si algo inesperado ocurre durante un servicio.',
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.notifications_active_outlined,
              title: '¿Para qué sirven?',
              body:
                  'Si activas el botón SOS desde la app, tu teléfono enviará '
                  'automáticamente tu ubicación GPS y los datos del cliente a '
                  'esas personas por WhatsApp o SMS. Nadie más verá esta '
                  'información.',
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Entendido, añadir contactos',
                  style: AppTextStyles.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _InfoRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.goldSubtle,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Icon(icon, color: AppColors.gold, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.ui(size: 12, weight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTextStyles.ui(
                    size: 11,
                    color: AppColors.textSecondary,
                  ).copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formulario de contactos ───────────────────────────────────────────
class _BarberContactsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> existing;
  const _BarberContactsSheet({required this.existing});

  @override
  State<_BarberContactsSheet> createState() => _BarberContactsSheetState();
}

class _BarberContactsSheetState extends State<_BarberContactsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name1;
  late final TextEditingController _phone1;
  late final TextEditingController _name2;
  late final TextEditingController _phone2;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c1 = widget.existing.isNotEmpty ? widget.existing[0] : null;
    final c2 = widget.existing.length > 1 ? widget.existing[1] : null;
    _name1 = TextEditingController(text: c1?['name'] as String? ?? '');
    _phone1 = TextEditingController(text: c1?['phone'] as String? ?? '');
    _name2 = TextEditingController(text: c2?['name'] as String? ?? '');
    _phone2 = TextEditingController(text: c2?['phone'] as String? ?? '');
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
        {'name': _name1.text.trim(), 'phone': _phone1.text.trim()},
        {'name': _name2.text.trim(), 'phone': _phone2.text.trim()},
      ];
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'emergencyContacts': contacts,
      }, SetOptions(merge: true));
      if (mounted) Navigator.of(context).pop();
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
    final isEditing = widget.existing.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.88,
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
                // Handle
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
                const SizedBox(height: 24),

                Center(
                  child: Container(
                    width: 64,
                    height: 64,
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
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Center(
                  child: Text(
                    isEditing
                        ? 'Editar contactos de emergencia'
                        : 'Añadir contactos de emergencia',
                    style: AppTextStyles.display(size: 20),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Dos personas de confianza que recibirán tu ubicación en caso de emergencia',
                    style: AppTextStyles.ui(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),

                _ContactSection(
                  number: 1,
                  nameCtrl: _name1,
                  phoneCtrl: _phone1,
                ),
                const SizedBox(height: 20),
                _ContactSection(
                  number: 2,
                  nameCtrl: _name2,
                  phoneCtrl: _phone2,
                ),
                const SizedBox(height: 32),

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
                      _saving ? 'Guardando...' : 'Guardar contactos',
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
                const SizedBox(height: 14),
                Center(
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                    ),
                    child: Text(
                      'Cancelar',
                      style: AppTextStyles.ui(
                        size: 13,
                        color: AppColors.textTertiary,
                      ),
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
        _Field(
          controller: nameCtrl,
          hint: 'Nombre completo (ej. Mamá, Juan Pérez)',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.name,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Ingresa el nombre del contacto $number'
              : null,
        ),
        const SizedBox(height: 10),
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
            if (v.replaceAll(RegExp(r'\D'), '').length < 7) {
              return 'Número demasiado corto';
            }
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
