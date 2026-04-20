import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/app_theme.dart';

class HelpScreen extends StatefulWidget {
  final List<({String q, String a})> faqs;

  const HelpScreen({super.key, required this.faqs});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _openEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'yacut2026@gmail.com',
      queryParameters: {
        'subject': 'Soporte YaCut',
        'body': 'Hola, necesito ayuda con...',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el correo'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Ayuda y soporte', style: AppTextStyles.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // ── FAQ ───────────────────────────────────────────
            _SectionLabel('PREGUNTAS FRECUENTES'),
            const SizedBox(height: 8),
            Container(
              decoration: AppDecorations.surface(),
              clipBehavior: Clip.hardEdge,
              child: Column(
                children: List.generate(widget.faqs.length, (i) {
                  final faq = widget.faqs[i];
                  return Column(
                    children: [
                      _FaqTile(question: faq.q, answer: faq.a),
                      if (i < widget.faqs.length - 1)
                        const Divider(height: 1, color: AppColors.borderSubtle),
                    ],
                  );
                }),
              ),
            ),

            // ── Contacto ──────────────────────────────────────
            const SizedBox(height: 28),
            _SectionLabel('CONTACTO'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppDecorations.surface(),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.goldSubtle,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.mail_outline_rounded,
                      color: AppColors.gold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Correo de soporte',
                          style: AppTextStyles.subtitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'yacut2026@gmail.com',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openEmail,
                    child: const Text('Escribir'),
                  ),
                ],
              ),
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

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                widget.answer,
                style: AppTextStyles.caption.copyWith(height: 1.6),
              ),
            ),
        ],
      ),
    );
  }
}
