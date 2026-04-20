import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Botón SOS de retención: el usuario debe mantenerlo presionado [holdDuration]
/// para activarlo. Mientras lo sostiene, se llena un arco circular rojo.
class SosButton extends StatefulWidget {
  final VoidCallback onActivated;
  final Duration holdDuration;

  const SosButton({
    super.key,
    required this.onActivated,
    this.holdDuration = const Duration(seconds: 5),
  });

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _pressing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.holdDuration);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        HapticFeedback.heavyImpact();
        widget.onActivated();
        _reset();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_pressing) return;
    setState(() => _pressing = true);
    HapticFeedback.mediumImpact();
    _ctrl.forward();
  }

  void _reset() {
    _ctrl.reset();
    if (mounted) setState(() => _pressing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _reset(),
      onPointerCancel: (_) => _reset(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final secsLeft = (widget.holdDuration.inSeconds * (1 - _ctrl.value))
              .ceil();
          return SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Resplandor exterior
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(
                      alpha: _pressing ? 0.18 : 0.08,
                    ),
                  ),
                ),
                // Arco de progreso
                SizedBox(
                  width: 84,
                  height: 84,
                  child: CircularProgressIndicator(
                    value: _ctrl.value,
                    strokeWidth: 5.5,
                    color: Colors.red.shade300,
                    backgroundColor: Colors.red.withValues(alpha: 0.22),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                // Núcleo del botón
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _pressing
                        ? Colors.red.shade600
                        : Colors.red.shade800,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(
                          alpha: _pressing ? 0.65 : 0.4,
                        ),
                        blurRadius: _pressing ? 22 : 12,
                        spreadRadius: _pressing ? 4 : 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.sos_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      if (_pressing)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${secsLeft}s',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
