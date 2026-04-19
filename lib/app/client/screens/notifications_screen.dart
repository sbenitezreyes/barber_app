import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool _loading = true;

  bool _allEnabled = true;
  bool _confirmed = true;
  bool _rejected = true;
  bool _completed = true;
  bool _cancelledByBarber = true;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadPrefs();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    try {
      final snap = await _userDoc.get();
      final prefs = snap.data()?['notifPrefs'] as Map<String, dynamic>?;
      if (prefs != null && mounted) {
        setState(() {
          _allEnabled = prefs['allEnabled'] as bool? ?? true;
          _confirmed = prefs['confirmed'] as bool? ?? true;
          _rejected = prefs['rejected'] as bool? ?? true;
          _completed = prefs['completed'] as bool? ?? true;
          _cancelledByBarber = prefs['cancelledByBarber'] as bool? ?? true;
        });
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
      _fadeCtrl.forward();
    }
  }

  Future<void> _save() async {
    try {
      await _userDoc.set({
        'notifPrefs': {
          'allEnabled': _allEnabled,
          'confirmed': _confirmed,
          'rejected': _rejected,
          'completed': _completed,
          'cancelledByBarber': _cancelledByBarber,
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _toggleAll(bool value) {
    setState(() => _allEnabled = value);
    _save();
  }

  void _toggle(String key, bool value) {
    setState(() {
      switch (key) {
        case 'confirmed':
          _confirmed = value;
        case 'rejected':
          _rejected = value;
        case 'completed':
          _completed = value;
        case 'cancelledByBarber':
          _cancelledByBarber = value;
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Notificaciones', style: AppTextStyles.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : FadeTransition(
              opacity: _fadeAnim,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── General ──────────────────────────────────
                  _SectionLabel('GENERAL'),
                  const SizedBox(height: 8),
                  _NotifTile(
                    icon: Icons.notifications_rounded,
                    title: 'Todas las notificaciones',
                    subtitle: _allEnabled ? 'Activadas' : 'Desactivadas',
                    value: _allEnabled,
                    onChanged: _toggleAll,
                    iconColor: AppColors.gold,
                  ),

                  // ── Individuales (animadas) ───────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _allEnabled
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              _SectionLabel('CITAS'),
                              const SizedBox(height: 8),
                              _NotifTile(
                                icon: Icons.check_circle_outline_rounded,
                                title: 'Cita confirmada',
                                subtitle:
                                    'Cuando el barbero acepta tu solicitud',
                                value: _confirmed,
                                onChanged: (v) => _toggle('confirmed', v),
                                iconColor: AppColors.success,
                              ),
                              const SizedBox(height: 4),
                              _NotifTile(
                                icon: Icons.do_not_disturb_on_outlined,
                                title: 'Cita rechazada',
                                subtitle: 'Cuando el barbero no puede aceptar',
                                value: _rejected,
                                onChanged: (v) => _toggle('rejected', v),
                                iconColor: AppColors.warning,
                              ),
                              const SizedBox(height: 4),
                              _NotifTile(
                                icon: Icons.celebration_outlined,
                                title: 'Cita completada',
                                subtitle: 'Al finalizar tu sesión',
                                value: _completed,
                                onChanged: (v) => _toggle('completed', v),
                                iconColor: AppColors.teal,
                              ),
                              const SizedBox(height: 4),
                              _NotifTile(
                                icon: Icons.event_busy_outlined,
                                title: 'Cita cancelada por el barbero',
                                subtitle: 'Cuando el barbero cancela tu cita',
                                value: _cancelledByBarber,
                                onChanged: (v) =>
                                    _toggle('cancelledByBarber', v),
                                iconColor: AppColors.error,
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
    );
  }
}

// ── Widgets privados ───────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(text, style: AppTextStyles.label),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? iconColor;

  const _NotifTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.surface(),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: (iconColor ?? AppColors.textSecondary).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: iconColor ?? AppColors.textSecondary,
          ),
        ),
        title: Text(title, style: AppTextStyles.body),
        subtitle: Text(
          subtitle,
          style: AppTextStyles.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        activeThumbColor: AppColors.gold,
        inactiveThumbColor: AppColors.textTertiary,
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
