import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

class BarberNotificationsScreen extends StatefulWidget {
  const BarberNotificationsScreen({super.key});

  @override
  State<BarberNotificationsScreen> createState() =>
      _BarberNotificationsScreenState();
}

class _BarberNotificationsScreenState extends State<BarberNotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  bool _loading = true;
  bool _allEnabled = true;
  bool _newAppointment = true;
  bool _clientCancellation = true;

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
          _newAppointment = prefs['newAppointment'] as bool? ?? true;
          _clientCancellation = prefs['clientCancellation'] as bool? ?? true;
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
          'newAppointment': _newAppointment,
          'clientCancellation': _clientCancellation,
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
        case 'newAppointment':
          _newAppointment = value;
        case 'clientCancellation':
          _clientCancellation = value;
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
                                icon: Icons.calendar_today_outlined,
                                title: 'Nueva solicitud de cita',
                                subtitle: 'Cuando un cliente reserva contigo',
                                value: _newAppointment,
                                onChanged: (v) => _toggle('newAppointment', v),
                                iconColor: AppColors.gold,
                              ),
                              const SizedBox(height: 4),
                              _NotifTile(
                                icon: Icons.event_busy_outlined,
                                title: 'Cita cancelada por el cliente',
                                subtitle:
                                    'Cuando un cliente cancela su reserva',
                                value: _clientCancellation,
                                onChanged: (v) =>
                                    _toggle('clientCancellation', v),
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
