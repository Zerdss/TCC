import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/fatigue_engine.dart';
import '../vision/vision_controller.dart';

/// Alerta em tela cheia: fundo vermelho piscando, mensagem grande e o botão
/// "Estou acordado" (silencia por 10 s). No alerta intensificado, pisca mais rápido.
class FullScreenAlert extends StatelessWidget {
  const FullScreenAlert({super.key, required this.vision});

  final VisionController vision;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vision,
      builder: (context, _) {
        final show = vision.showFullScreenAlert;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: show
              ? _AlertBody(
                  key: const ValueKey('alert'),
                  notice: vision.notice,
                  reason: vision.metrics.alertReason,
                  intense: vision.alertLevel >= 2,
                  onAcknowledge: vision.acknowledgeAlert,
                )
              : const SizedBox.shrink(key: ValueKey('none')),
        );
      },
    );
  }
}

class _AlertBody extends StatefulWidget {
  const _AlertBody({
    super.key,
    required this.notice,
    required this.reason,
    required this.intense,
    required this.onAcknowledge,
  });

  final String notice;
  final AlertReason reason;
  final bool intense;
  final VoidCallback onAcknowledge;

  @override
  State<_AlertBody> createState() => _AlertBodyState();
}

class _AlertBodyState extends State<_AlertBody> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);

  @override
  void didUpdateWidget(covariant _AlertBody old) {
    super.didUpdateWidget(old);
    final d = Duration(milliseconds: widget.intense ? 220 : 500);
    if (_blink.duration != d) {
      _blink
        ..duration = d
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (widget.reason) {
      AlertReason.yawn => Icons.record_voice_over_rounded,
      AlertReason.head => Icons.airline_seat_flat_angled_rounded,
      AlertReason.faceLost => Icons.no_accounts_rounded,
      _ => Icons.visibility_off_rounded,
    };
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) => Material(
        color: Color.lerp(const Color(0xFF7F1D1D), AppColors.red, _blink.value),
        child: child,
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                key: const Key('fullscreen-alert'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 96),
                  const SizedBox(height: 16),
                  Text(
                    widget.intense ? 'ACORDE!' : 'ALERTA DE\nSONOLÊNCIA',
                    textAlign: TextAlign.center,
                    style: AppText.h1.copyWith(color: Colors.white, fontSize: 56),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.notice.replaceFirst('ALERTA: ', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Pare em um local seguro e descanse.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFFEE2E2), fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                      key: const Key('button-estou-acordado'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF7F1D1D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontFamily: textFont, fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      onPressed: widget.onAcknowledge,
                      icon: const Icon(Icons.check_circle_rounded, size: 28),
                      label: const Text('Estou acordado'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Silencia o alerta por 10 segundos.',
                    style: TextStyle(color: Color(0xFFFECACA), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
