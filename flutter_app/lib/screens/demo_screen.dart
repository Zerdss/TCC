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
  bool _recalibrating = false;

  VisionController get vision => widget.vision;

  @override
  void initState() {
    super.initState();
    // Aberto direto da tela inicial (calibração salva): liga a câmera aqui.
    if (vision.calibrationStep != null) vision.beginMonitoring();
    if (vision.state == EngineState.idle || vision.state == EngineState.error) vision.start();
  }

  @override
  void dispose() {
    if (!_recalibrating) vision.stop();
    super.dispose();
  }

  void _recalibrate() {
    _recalibrating = true;
    vision.resetCalibration();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      children: [
        ListenableBuilder(
          listenable: vision,
          builder: (context, _) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 12,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ETAPA 03 / 04 • AO VIVO', style: AppText.kicker),
                  SizedBox(height: 8),
                  Text('Painel de monitoramento', style: AppText.h2),
                ],
              ),
              _StatusPill(status: vision.status),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CameraPanel(vision: vision),
        ListenableBuilder(listenable: vision, builder: (context, _) => _Telemetry(vision: vision)),
        const SizedBox(height: 20),
        const Divider(color: AppColors.line),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _recalibrate,
                icon: const Icon(Icons.tune),
                label: const Text('Recalibrar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const Key('button-como-funciona'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ExplanationScreen())),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Como funciona'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final FatigueStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      key: const Key('status-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusDot(color: color),
        const SizedBox(width: 6),
        Text(status.label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (vision.notice.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AlertBar(text: vision.notice, critical: vision.status == FatigueStatus.alert),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricCard(
                  label: 'EAR', value: m.ear.toStringAsFixed(2), unit: 'ratio',
                  color: AppColors.amber, series: vision.earHistory, scale: 0.4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                  label: 'MAR', value: m.mar.toStringAsFixed(2), unit: 'ratio',
                  color: AppColors.blue, series: vision.marHistory, scale: 1.0),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                  label: 'PERCLOS', value: '${(m.perclos * 100).round()}%', unit: 'janela de 60s',
                  color: AppColors.green, series: vision.perclosHistory, scale: 1.0),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(icon: Icons.visibility_outlined, color: AppColors.blue, text: '${m.blinkRate} piscadas/min'),
            _Chip(
              icon: m.expression ? Icons.sentiment_very_satisfied : Icons.sentiment_neutral,
              color: m.expression ? AppColors.yellow : AppColors.muted,
              text: m.expression ? 'Expressão facial detectada' : 'Expressão neutra',
            ),
            _Chip(
              icon: Icons.timer_outlined,
              color: AppColors.amber,
              text: 'Olhos fechados: ${(m.closedMs / 1000).toStringAsFixed(1)} s',
            ),
            _Chip(icon: Icons.speed, color: AppColors.muted, text: '${vision.fps.toStringAsFixed(1)} FPS'),
          ],
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(children: [
            SwitchListTile(
              dense: true,
              value: vision.soundEnabled,
              onChanged: vision.setSoundEnabled,
              secondary: const Icon(Icons.volume_up_outlined, color: AppColors.amber),
              title: const Text('Alerta sonoro'),
            ),
            SwitchListTile(
              dense: true,
              value: vision.vibrationEnabled,
              onChanged: vision.setVibrationEnabled,
              secondary: const Icon(Icons.vibration, color: AppColors.amber),
              title: const Text('Vibração'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(
          'Os valores são calculados no aparelho a partir dos contornos faciais.\n'
          'Limiares ativos: EAR ${t.ear.toStringAsFixed(3)} • MAR ${t.mar.toStringAsFixed(3)} • '
          'faixa neutra de MAR até ${t.marNeutral.toStringAsFixed(3)}.\n'
          'Alerta: olhos fechados por 1,2 s contínuo (piscadas de 0,08 a 0,4 s ignoradas) ou bocejo '
          'sustentado por 1,8 s. Suavização por média móvel de $smoothWindow quadros e histerese de 1,0 s '
          'para voltar ao normal.',
          style: AppText.body,
        ),
      ],
    );
  }
}

class _AlertBar extends StatefulWidget {
  const _AlertBar({required this.text, required this.critical});
  final String text;
  final bool critical;

  @override
  State<_AlertBar> createState() => _AlertBarState();
}

class _AlertBarState extends State<_AlertBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500), lowerBound: .72)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      key: const Key('fatigue-alert'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: widget.critical ? AppColors.red : AppColors.yellow,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: AppColors.bg),
        const SizedBox(width: 9),
        Expanded(
          child: Text(widget.text,
              style: const TextStyle(color: AppColors.bg, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ]),
    );
    return widget.critical ? FadeTransition(opacity: _pulse, child: bar) : bar;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.series,
    required this.scale,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final List<double> series;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final bars = series.length > 12 ? series.sublist(series.length - 12) : series;
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          Text(unit, style: const TextStyle(color: AppColors.muted, fontSize: 10), maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: FractionallySizedBox(
                        heightFactor: (0.15 + (bars[i] / scale).clamp(0.0, 1.0) * 0.85),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: i == bars.length - 1 ? 1 : .35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
        Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
