import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/calibration_store.dart';
import '../theme.dart';
import '../vision/vision_controller.dart';
import '../widgets/common.dart';
import 'calibration_screen.dart';
import 'demo_screen.dart';
import 'explanation_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.vision});

  final VisionController vision;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SavedCalibration? _saved;

  VisionController get vision => widget.vision;

  @override
  void initState() {
    super.initState();
    vision.addListener(_refreshSaved);
    _refreshSaved();
  }

  @override
  void dispose() {
    vision.removeListener(_refreshSaved);
    super.dispose();
  }

  Future<void> _refreshSaved() async {
    final saved = await vision.calibrationStore?.load();
    if (mounted && saved?.savedAt != _saved?.savedAt) setState(() => _saved = saved);
  }

  Future<void> _start(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)));
    _refreshSaved();
  }

  Future<void> _useSaved(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (!await vision.loadSavedCalibration()) return;
    vision.beginMonitoring();
    await navigator.push(MaterialPageRoute(builder: (_) => DemoScreen(vision: vision)));
    _refreshSaved();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const metricsInfo = [
      (Icons.remove_red_eye_outlined, 'EAR', 'Razão de abertura dos olhos', AppColors.orange),
      (Icons.show_chart, 'PERCLOS', 'Percentual de tempo com olhos fechados nos últimos 60 segundos', AppColors.green),
      (Icons.sentiment_satisfied_alt_outlined, 'MAR', 'Razão de abertura da boca — detecta bocejos', AppColors.blue),
    ];
    const flow = [
      (Icons.center_focus_strong_outlined, 'Calibre', 'Olhos, bocejo e sorriso'),
      (Icons.speed_outlined, 'Monitore', 'Alertas em tempo real'),
      (Icons.insights_outlined, 'Analise', 'Histórico e CSV'),
    ];
    return AppPage(
      children: [
        const Row(children: [
          StatusDot(),
          SizedBox(width: 8),
          Text('PROTÓTIPO ACADÊMICO • TCC', style: AppText.section),
        ]),
        const SizedBox(height: 16),
        const _HeroGauge(),
        const SizedBox(height: 18),
        const Text('Detecção de\nSonolência ao Volante', style: AppText.h1),
        const SizedBox(height: 14),
        const Text(
          'Uma demonstração interativa de como a visão computacional pode reconhecer sinais de fadiga '
          'em tempo real — antes que o risco vire acidente.',
          style: AppText.lead,
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          key: const Key('button-iniciar'),
          label: 'Iniciar Demonstração',
          icon: Icons.photo_camera_outlined,
          onPressed: () => _start(context),
        ),
        if (_saved != null) ...[
          const SizedBox(height: 10),
          PrimaryButton(
            key: const Key('button-calibracao-salva'),
            label: 'Usar calibração salva (${_fmt(_saved!.savedAt)})',
            icon: Icons.bookmark_added_outlined,
            secondary: true,
            onPressed: () => _useSaved(context),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          if (vision.database != null)
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('button-historico'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => HistoryScreen(database: vision.database!))),
                icon: const Icon(Icons.history, color: AppColors.accent),
                label: const Text('Histórico'),
              ),
            ),
          if (vision.database != null) const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExplanationScreen())),
              icon: const Icon(Icons.menu_book_outlined, color: AppColors.accent),
              label: const Text('Como funciona'),
            ),
          ),
        ]),
        const SizedBox(height: 28),
        const Panel(
          color: AppColors.accentSoft,
          border: Color(0xFFA8D5B9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: AppColors.green, size: 24),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Processamento 100% local', style: AppText.cardTitle),
                    SizedBox(height: 5),
                    Text(
                      'A câmera é usada apenas no próprio aparelho. Nenhuma imagem é armazenada ou enviada.',
                      style: AppText.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text('COMO USAR', style: AppText.section),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < flow.length; i++) ...[
              Expanded(
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('0${i + 1}', style: AppText.kicker),
                      const Spacer(),
                      Icon(flow[i].$1, color: AppColors.accent, size: 20),
                    ]),
                    const SizedBox(height: 10),
                    Text(flow[i].$2, style: AppText.h3.copyWith(fontSize: 20)),
                    const SizedBox(height: 2),
                    Text(flow[i].$3, style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.35)),
                  ]),
                ),
              ),
              if (i < flow.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 28),
        const Text('MÉTRICAS MONITORADAS', style: AppText.section),
        const SizedBox(height: 12),
        for (final (icon, title, desc, color) in metricsInfo) ...[
          Panel(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.number.copyWith(fontSize: 20, letterSpacing: 1)),
                      Text(desc, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Ilustração do topo: olho minimalista só em contorno (pálpebras e íris). Pisca rapidamente a cada poucos segundos e o olhar se move de leve.
class _HeroGauge extends StatefulWidget {
  const _HeroGauge();

  @override
  State<_HeroGauge> createState() => _HeroGaugeState();
}

class _HeroGaugeState extends State<_HeroGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFE6F3EA)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _EyePainter(_c.value), size: Size.infinite),
        ),
      ),
    );
  }
}

class _EyePainter extends CustomPainter {
  _EyePainter(this.t);

  /// Fase da animação (0 a 1, repete a cada 5 s).
  final double t;

  /// Abertura da pálpebra: 1 = aberta. Uma piscada rápida (~0,5 s) por ciclo.
  double get _openness {
    const closeStart = 0.70, closed = 0.735, reopened = 0.80;
    if (t >= closeStart && t < closed) return 1 - (t - closeStart) / (closed - closeStart);
    if (t >= closed && t < reopened) return Curves.easeOut.transform((t - closed) / (reopened - closed));
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = math.min(size.width * 0.50, size.height * 1.15);
    final c = Offset(size.width / 2, size.height / 2);
    final open = _openness;
    final h = w * 0.27 * open; // meia-altura do olho (0 quando fechado)

    // Contorno: duas curvas simétricas que se encontram nos cantos.
    final left = Offset(c.dx - w / 2, c.dy);
    final right = Offset(c.dx + w / 2, c.dy);
    final eye = Path()
      ..moveTo(left.dx, left.dy)
      ..cubicTo(c.dx - w * 0.22, c.dy - h * 1.33, c.dx + w * 0.22, c.dy - h * 1.33, right.dx, right.dy)
      ..cubicTo(c.dx + w * 0.22, c.dy + h * 1.33, c.dx - w * 0.22, c.dy + h * 1.33, left.dx, left.dy)
      ..close();

    // Íris em contorno, recortada pelo olho (some na piscada).
    final line = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.save();
    canvas.clipPath(eye);
    final gaze = Offset(math.sin(t * math.pi * 2) * w * 0.05, 0);
    canvas.drawCircle(c + gaze, w * 0.15, line);
    canvas.restore();

    canvas.drawPath(
      eye,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EyePainter old) => old.t != t;
}
