import 'package:flutter/material.dart';

import '../vision/fatigue_engine.dart';
import '../vision/vision_controller.dart';

/// O que aparece na janela flutuante (pequena, por cima do GPS): só o essencial,
/// grande e colorido, para ler de relance.
class FloatingView extends StatefulWidget {
  const FloatingView({super.key, required this.vision});
  final VisionController vision;

  @override
  State<FloatingView> createState() => _FloatingViewState();
}

class _FloatingViewState extends State<FloatingView> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.vision, _blink]),
      builder: (context, _) {
        final v = widget.vision;
        final monitoring = v.isMonitoring;
        final status = v.status;
        final acked = v.alertAcknowledged();
        final (Color bg, String title, IconData icon) = !monitoring
            ? (const Color(0xFF55606A), 'PAUSADO', Icons.pause_circle_outline)
            : switch (status) {
                FatigueStatus.normal => (const Color(0xFF2E7D57), 'NORMAL', Icons.verified_user_outlined),
                FatigueStatus.attention => (const Color(0xFFB7791F), 'ATENÇÃO', Icons.visibility_outlined),
                FatigueStatus.alert => (
                    Color.lerp(const Color(0xFFB3261E), const Color(0xFF7A0F0A), acked ? 0 : _blink.value)!,
                    'ALERTA',
                    Icons.warning_amber_rounded
                  ),
              };
        final detail = !monitoring
            ? 'Abra o app para monitorar'
            : status == FatigueStatus.normal
                ? (v.overlay == null ? 'Rosto não visível' : 'Monitorando')
                : v.notice;
        return ColoredBox(
          key: const Key('floating-view'),
          color: bg,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: Colors.white, size: 34),
                    const SizedBox(width: 6),
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ]),
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(detail,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 2),
                  Text('Fatigue Guard • EAR ${v.metrics.ear.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
