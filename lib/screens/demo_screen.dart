import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/fatigue_engine.dart';
import '../vision/vision_controller.dart';
import '../widgets/camera_panel.dart';
import '../widgets/common.dart';
import 'calibration_screen.dart';
import 'explanation_screen.dart';

Color statusColor(FatigueStatus s) => switch (s) {
      FatigueStatus.normal => AppColors.green,
      FatigueStatus.attention => AppColors.yellow,
      FatigueStatus.alert => AppColors.red,
    };

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, required this.vision});

  final VisionController vision;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  VisionController get vision => widget.vision;

  @override
  void initState() {
    super.initState();
    // Aberto direto da tela inicial (calibração salva): entra em monitoramento.
    if (vision.calibrationStep != null) vision.beginMonitoring();
    vision.acquireCamera();
  }

  @override
  void dispose() {
    vision.releaseCamera();
    super.dispose();
  }

  void _recalibrate() {
    vision.resetCalibration();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      children: [
        const PageTitle(kicker: 'ETAPA 03 / 04 • AO VIVO', title: 'Painel de monitoramento'),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: vision,
          builder: (context, _) => _StatusCard(vision: vision),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: vision,
          builder: (context, child) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: vision.status == FatigueStatus.normal
                  ? Colors.transparent
                  : statusColor(vision.status).withValues(alpha: 0.85),
            ),
            child: child,
          ),
          child: CameraPanel(vision: vision),
        ),
        ListenableBuilder(listenable: vision, builder: (context, _) => _Telemetry(vision: vision)),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _recalibrate,
                icon: const Icon(Icons.restart_alt, color: AppColors.amber, size: 18),
                label: const FittedBox(child: Text('Recalibrar', maxLines: 1)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const Key('button-como-funciona'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ExplanationScreen())),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const FittedBox(child: Text('Como funciona', maxLines: 1)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Cartão grande com o estado atual (NORMAL / ATENÇÃO / ALERTA).
class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.vision});
  final VisionController vision;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vision;
    final status = v.status;
    final color = statusColor(status);
    final (icon, title, text) = switch (status) {
      FatigueStatus.normal => (
          Icons.verified_user_outlined,
          'NORMAL',
          v.state == EngineState.running ? 'Motorista atento. Monitorando olhos e boca.' : 'Iniciando a câmera...'
        ),
      FatigueStatus.attention => (Icons.visibility_outlined, 'ATENÇÃO', v.notice),
      FatigueStatus.alert => (Icons.warning_amber_rounded, 'ALERTA DE SONOLÊNCIA', v.notice),
    };
    final card = AnimatedContainer(
      key: const Key('status-badge'),
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status == FatigueStatus.alert ? AppColors.red : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: status == FatigueStatus.alert ? 1 : 0.6)),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status == FatigueStatus.alert ? AppColors.bg.withValues(alpha: 0.18) : color.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: status == FatigueStatus.alert ? AppColors.bg : color, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(title,
                  maxLines: 1,
                  style: AppText.h3.copyWith(
                      color: status == FatigueStatus.alert ? AppColors.bg : color, fontSize: 22, letterSpacing: 1)),
            ),
            const SizedBox(height: 2),
            Text(
              text,
              key: status == FatigueStatus.normal ? null : const Key('fatigue-alert'),
              style: TextStyle(
                color: status == FatigueStatus.alert ? AppColors.bg : AppColors.textSoft,
                fontSize: 13,
                fontWeight: status == FatigueStatus.alert ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ]),
        ),
        _QuickToggle(
          icon: v.soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          active: v.soundEnabled,
          onTap: () => v.setSoundEnabled(!v.soundEnabled),
          tooltip: 'Som',
          onAlert: status == FatigueStatus.alert,
        ),
        const SizedBox(width: 6),
        _QuickToggle(
          icon: v.vibrationEnabled ? Icons.vibration_rounded : Icons.mobile_off_rounded,
          active: v.vibrationEnabled,
          onTap: () => v.setVibrationEnabled(!v.vibrationEnabled),
          tooltip: 'Vibração',
          onAlert: status == FatigueStatus.alert,
        ),
      ]),
    );
    if (status != FatigueStatus.alert) return card;
    return FadeTransition(opacity: Tween(begin: 0.72, end: 1.0).animate(_pulse), child: card);
  }
}

class _QuickToggle extends StatelessWidget {
  const _QuickToggle({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
    required this.onAlert,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;
  final bool onAlert;

  @override
  Widget build(BuildContext context) {
    final fg = onAlert ? AppColors.bg : (active ? AppColors.amber : AppColors.muted);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: fg.withValues(alpha: 0.5)),
          ),
          child: Icon(icon, size: 19, color: fg),
        ),
      ),
    );
  }
}

class _Telemetry extends StatelessWidget {
  const _Telemetry({required this.vision});
  final VisionController vision;

  @override
  Widget build(BuildContext context) {
    final m = vision.metrics;
    final t = vision.thresholds;
    final s = vision.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricCard(
                label: 'EAR',
                hint: 'olhos',
                value: m.ear.toStringAsFixed(2),
                color: AppColors.amber,
                series: vision.earHistory,
                maxValue: 0.45,
                threshold: t.ear,
                alarm: m.ear > 0 && m.ear < t.ear,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'MAR',
                hint: 'boca',
                value: m.mar.toStringAsFixed(2),
                color: AppColors.blue,
                series: vision.marHistory,
                maxValue: 1.0,
                threshold: t.mar,
                alarm: m.mar >= t.mar,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                label: 'PERCLOS',
                hint: '60 s',
                value: '${(m.perclos * 100).round()}%',
                color: AppColors.green,
                series: vision.perclosHistory,
                maxValue: 0.3,
                alarm: m.perclos >= 0.15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(icon: Icons.remove_red_eye_outlined, color: AppColors.blue, text: '${m.blinkRate} piscadas/min'),
            _Chip(
              icon: m.expression ? Icons.sentiment_very_satisfied : Icons.sentiment_neutral,
              color: m.expression ? AppColors.yellow : AppColors.muted,
              text: !s.smileFilter
                  ? 'Filtro de sorriso desligado'
                  : m.expression
                      ? 'Sorriso/fala detectado'
                      : 'Expressão neutra',
            ),
            _Chip(
              icon: Icons.timer_outlined,
              color: m.closedMs > 0 ? AppColors.amber : AppColors.muted,
              text: 'Olhos fechados: ${(m.closedMs / 1000).toStringAsFixed(1)} s',
            ),
            if (m.mouthOpenMs > 0)
              _Chip(
                icon: Icons.record_voice_over_outlined,
                color: AppColors.blue,
                text: 'Boca aberta: ${(m.mouthOpenMs / 1000).toStringAsFixed(1)} s',
              ),
            _Chip(icon: Icons.speed, color: AppColors.muted, text: '${vision.fps.toStringAsFixed(1)} FPS'),
          ],
        ),
        const SizedBox(height: 14),
        Panel(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.tune, size: 16, color: AppColors.amber),
              const SizedBox(width: 8),
              const Expanded(child: Text('LIMIARES ATIVOS', style: AppText.section)),
              Text(t.calibrated ? 'calibrado' : 'padrão',
                  style: TextStyle(
                      color: t.calibrated ? AppColors.green : AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _ThresholdValue(label: 'EAR <', value: t.ear.toStringAsFixed(3)),
              _ThresholdValue(label: 'MAR ≥', value: t.mar.toStringAsFixed(3)),
              _ThresholdValue(label: 'Sorriso ≥', value: t.marNeutral.toStringAsFixed(3)),
            ]),
            const SizedBox(height: 10),
            Text(
              'Alerta: olhos fechados por ${formatSeconds(s.eyesAlertMs)} s contínuos (piscadas de 0,08 a 0,4 s '
              'ignoradas) ou bocejo sustentado por ${formatSeconds(s.yawnAlertMs)} s. Média móvel de '
              '$smoothWindow quadros e histerese de 1,0 s para voltar ao normal. '
              'Ajuste tudo em Configurações (ícone no topo).',
              style: AppText.body.copyWith(fontSize: 12),
            ),
          ]),
        ),
      ],
    );
  }
}

class _ThresholdValue extends StatelessWidget {
  const _ThresholdValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(value, style: AppText.number.copyWith(fontSize: 20)),
      ]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.hint,
    required this.value,
    required this.color,
    required this.series,
    required this.maxValue,
    required this.alarm,
    this.threshold,
  });

  final String label;
  final String hint;
  final String value;
  final Color color;
  final List<double> series;
  final double maxValue;
  final double? threshold;
  final bool alarm;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: alarm ? color : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, style: AppText.number.copyWith(fontSize: 16, letterSpacing: 1)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.number.copyWith(fontSize: 34, height: 1)),
          ),
          Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(series: series, color: color, maxValue: maxValue, threshold: threshold),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini‑gráfico de linha com área preenchida e linha tracejada do limiar.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.series, required this.color, required this.maxValue, this.threshold});

  final List<double> series;
  final Color color;
  final double maxValue;
  final double? threshold;

  double _y(double v, Size size) => size.height - (v / maxValue).clamp(0.0, 1.0) * (size.height - 2) - 1;

  @override
  void paint(Canvas canvas, Size size) {
    final th = threshold;
    if (th != null) {
      final y = _y(th, size);
      final p = Paint()
        ..color = AppColors.muted.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), p);
      }
    }
    if (series.length < 2) {
      canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1),
          Paint()..color = AppColors.line);
      return;
    }
    final dx = size.width / (series.length - 1);
    final line = Path();
    for (var i = 0; i < series.length; i++) {
      final o = Offset(i * dx, _y(series[i], size));
      i == 0 ? line.moveTo(o.dx, o.dy) : line.lineTo(o.dx, o.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(size.width, _y(series.last, size)), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => true;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: AppColors.textSoft, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
