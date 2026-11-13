import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/fatigue_engine.dart';
import '../vision/vision_controller.dart';

/// "A caminho do alerta": uma barra por regra, enchendo em tempo real até o
/// tempo que dispara o ALERTA. Mostra na prática como o sistema decide.
class AlertProgressPanel extends StatelessWidget {
  const AlertProgressPanel({super.key, required this.vision});
  final VisionController vision;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vision,
      builder: (context, _) {
        final m = vision.metrics;
        final s = vision.settings;
        final e = vision.engine;
        final rows = <Widget>[];
        final eyesLimit = e.eyesAlertLimitMs;
        rows.add(eyesLimit == null
            ? const _InfoRow(icon: Icons.visibility_outlined, label: 'Olhos', text: 'no modo inclinação, só confirmam')
            : _BarRow(
                key: const Key('bar-olhos'),
                icon: Icons.visibility_off_outlined,
                label: 'Olhos fechados',
                valueMs: m.closedMs,
                warnMs: s.eyesWarnMs,
                limitMs: eyesLimit,
              ));
        rows.add(_BarRow(
          key: const Key('bar-bocejo'),
          icon: Icons.record_voice_over_outlined,
          label: 'Boca aberta (bocejo)',
          valueMs: m.mouthOpenMs,
          warnMs: s.mouthWarnMs,
          limitMs: s.yawnAlertMs,
        ));
        if (s.headEnabled) {
          rows.add(_BarRow(
            key: const Key('bar-cabeca'),
            icon: Icons.airline_seat_flat_angled_outlined,
            label: e.tiltMode ? 'Cabeça caída' : 'Cabeça caída (com olhos fechados)',
            valueMs: m.headDownMs,
            // mesmo cálculo do aviso de ATENÇÃO em FatigueMetrics.classify
            warnMs: e.reinforced ? (s.headWarnMs * reinforcedHeadTimeFactor).round() : s.headWarnMs,
            limitMs: e.headAlertLimitMs,
          ));
        }
        if (e.tiltMode) {
          rows.add(_CountRow(label: 'Cabeceios no último minuto', value: m.nods, warn: nodWarnCount, limit: nodAlertCount));
        }
        if (s.faceLostEnabled && !m.lowLight) {
          rows.add(_BarRow(
            key: const Key('bar-rosto'),
            icon: Icons.no_accounts_outlined,
            label: 'Rosto fora da câmera',
            valueMs: m.faceMissingMs,
            warnMs: s.faceLostWarnMs,
            limitMs: s.faceLostAlertMs,
          ));
        }
        return Container(
          key: const Key('alert-progress'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.timer_outlined, size: 16, color: AppColors.accentDark),
              const SizedBox(width: 6),
              const Text('A CAMINHO DO ALERTA',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1, color: AppColors.accentDark)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(m.alert ? 'alerta disparado' : 'barra cheia = ALERTA',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: m.alert ? AppColors.red : AppColors.muted, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 8),
            ...rows,
          ]),
        );
      },
    );
  }
}

Color _colorFor(double frac, double warnFrac) => frac >= 1
    ? AppColors.red
    : frac >= warnFrac
        ? AppColors.yellow
        : AppColors.green;

String _s(int ms) => formatSeconds(ms);

class _BarRow extends StatelessWidget {
  const _BarRow({
    super.key,
    required this.icon,
    required this.label,
    required this.valueMs,
    required this.warnMs,
    required this.limitMs,
  });

  final IconData icon;
  final String label;
  final int valueMs, warnMs, limitMs;

  @override
  Widget build(BuildContext context) {
    final frac = limitMs <= 0 ? 0.0 : (valueMs / limitMs).clamp(0.0, 1.0);
    final warnFrac = limitMs <= 0 ? 1.0 : warnMs / limitMs;
    final color = _colorFor(frac, warnFrac);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: valueMs > 0 ? color : AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          Text('${_s(valueMs > limitMs ? limitMs : valueMs)} / ${_s(limitMs)} s',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: valueMs > 0 ? color : AppColors.muted)),
        ]),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (context, c) {
          return Stack(children: [
            Container(height: 8, decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(4))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 8,
              width: c.maxWidth * frac,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
            // marca do ATENÇÃO
            if (warnFrac > 0 && warnFrac < 1)
              Positioned(
                left: c.maxWidth * warnFrac - 1,
                child: Container(width: 2, height: 8, color: AppColors.yellow.withValues(alpha: 0.9)),
              ),
          ]);
        }),
      ]),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value, required this.warn, required this.limit});
  final String label;
  final int value, warn, limit;

  @override
  Widget build(BuildContext context) {
    final color = value >= limit
        ? AppColors.red
        : value >= warn
            ? AppColors.yellow
            : AppColors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Icon(Icons.south_outlined, size: 15, color: value > 0 ? color : AppColors.muted),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        for (var i = 0; i < limit; i++)
          Container(
            margin: const EdgeInsets.only(left: 4),
            width: 18,
            height: 8,
            decoration: BoxDecoration(
              color: i < value ? color : AppColors.panel2,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        const SizedBox(width: 8),
        Text('$value / $limit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: value > 0 ? color : AppColors.muted)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.text});
  final IconData icon;
  final String label, text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
      ]),
    );
  }
}
