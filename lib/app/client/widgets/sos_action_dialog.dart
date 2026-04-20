import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dialog SOS activado: muestra tarjetas por contacto con botones WhatsApp / SMS.
/// Acepta latitud/longitud como doubles para evitar dependencia de google_maps_flutter.
class SosActionDialog extends StatefulWidget {
  final String barberName;
  final String? barberPhone;
  final List<Map<String, dynamic>> contacts;
  final double? latitude;
  final double? longitude;

  const SosActionDialog({
    super.key,
    required this.barberName,
    required this.barberPhone,
    required this.contacts,
    this.latitude,
    this.longitude,
  });

  @override
  State<SosActionDialog> createState() => _SosActionDialogState();
}

class _SosActionDialogState extends State<SosActionDialog> {
  final _sent = <int>{};

  String _buildMessage() {
    final loc = (widget.latitude != null && widget.longitude != null)
        ? 'https://maps.google.com/?q=${widget.latitude},${widget.longitude}'
        : 'No disponible';

    return '🚨 EMERGENCIA - NECESITO AYUDA 🚨\n\n'
        'Puede que esté en peligro y no pueda responder.\n\n'
        '📍 Mi ubicación ahora: $loc\n\n'
        '✂️ Barbero en mi casa: ${widget.barberName}'
        '${widget.barberPhone != null ? '\n📞 Teléfono del barbero: ${widget.barberPhone}' : ''}'
        '\n\n⚠️ Mensaje enviado automáticamente desde YaCut. '
        'Por favor, busca ayuda o llama a emergencias (123 / 911).';
  }

  Future<void> _sendWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final encoded = Uri.encodeComponent(_buildMessage());
    final uri = Uri.parse('https://wa.me/$clean?text=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _sendSms(String phone) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': _buildMessage()},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A0505),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícono
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.sos_rounded,
                  color: Colors.red,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SOS ACTIVADO',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Envía tu ubicación y datos del barbero\na tus contactos de emergencia',
                style: TextStyle(
                  color: Colors.red.withValues(alpha: 0.75),
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Tarjetas de contacto
              ...List.generate(widget.contacts.length, (i) {
                final c = widget.contacts[i];
                final name = c['name'] as String? ?? 'Contacto ${i + 1}';
                final phone = c['phone'] as String? ?? '';
                final alreadySent = _sent.contains(i);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: alreadySent
                            ? Colors.green.withValues(alpha: 0.5)
                            : Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.withValues(alpha: 0.15),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      phone,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.55,
                                        ),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (alreadySent)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.green,
                                  size: 20,
                                ),
                            ],
                          ),
                          if (!alreadySent) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: SosContactBtn(
                                    icon: Icons.chat_rounded,
                                    label: 'WhatsApp',
                                    color: const Color(0xFF25D366),
                                    onTap: () async {
                                      await _sendWhatsApp(phone);
                                      if (mounted) {
                                        setState(() => _sent.add(i));
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SosContactBtn(
                                    icon: Icons.sms_rounded,
                                    label: 'SMS',
                                    color: Colors.blue.shade400,
                                    onTap: () async {
                                      await _sendSms(phone);
                                      if (mounted) {
                                        setState(() => _sent.add(i));
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),
              // Botón cerrar
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cerrar', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de acción dentro del dialog SOS (WhatsApp / SMS).
class SosContactBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const SosContactBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
