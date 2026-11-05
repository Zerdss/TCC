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
    vision.resetCalibration();
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
      (Icons.remove_red_eye_outlined, 'EAR', 'Razão de abertura dos olhos', AppColors.amber),
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
                icon: const Icon(Icons.history, color: AppColors.amber),
                label: const Text('Histórico'),
              ),
            ),
          if (vision.database != null) const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExplanationScreen())),
              icon: const Icon(Icons.menu_book_outlined, color: AppColors.amber),
              label: const Text('Como funciona'),
            ),
          ),
        ]),
        const SizedBox(height: 28),
        const Panel(
          color: Color(0xFF0E211C),
          border: Color(0xFF19513F),
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
                      Icon(flow[i].$1, color: AppColors.amber, size: 20),
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
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 10),
        const Row(children: [
          Icon(Icons.science_outlined, color: AppColors.muted, size: 16),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'Demonstração conceitual • O protótipo embarcado roda separadamente em Raspberry Pi.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        ]),
      ],
    );
  }
}

/// Ilustração do topo: velocímetro/HUD com um olho no centro, levemente animado.
class _HeroGauge extends StatefulWidget {
  const _HeroGauge();

  @override
  State<_HeroGauge> createState() => _HeroGaugeState();
}

class _HeroGaugeState extends State<_HeroGauge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

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
          colors: [Color(0xFF111A28), Color(0xFF0B111B)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              CustomPaint(painter: _GaugePainter(Curves.easeInOut.transform(_c.value)), size: Size.infinite),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Grade de fundo (linhas de "estrada" em perspectiva).
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    final vanish = Offset(size.width / 2, size.height * 0.30);
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(vanish, Offset(size.width / 2 + i * size.width / 5, size.height), grid);
    }

    final center = Offset(size.width / 2, size.height * 0.58);
    final r = math.min(size.width * 0.40, size.height * 0.46);
    const start = math.pi * 0.85;
    const sweep = math.pi * 1.3;

    // Arco base e marcações.
    final base = Paint()
      ..color = AppColors.panel2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), start, sweep, false, base);
    for (var i = 0; i <= 20; i++) {
      final a = start + sweep * i / 20;
      final inner = r - (i % 5 == 0 ? 22 : 16);
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * inner,
        center + Offset(math.cos(a), math.sin(a)) * (r - 10),
        Paint()
          ..color = i % 5 == 0 ? AppColors.muted : AppColors.lineStrong
          ..strokeWidth = i % 5 == 0 ? 2 : 1,
      );
    }

    // Arco de valor (verde → âmbar → vermelho).
    final value = 0.35 + 0.35 * t;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.drawArc(
      rect,
      start,
      sweep * value,
      false,
      Paint()
        ..shader = const SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [AppColors.green, AppColors.amber, AppColors.red],
          stops: [0.0, 0.6, 1.0],
          tileMode: TileMode.clamp,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round,
    );

    // Olho no centro.
    final eyeW = r * 0.95;
    final open = 0.55 + 0.45 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
    final eyeH = eyeW * 0.42 * open;
    final eye = Path()
      ..moveTo(center.dx - eyeW / 2, center.dy)
      ..quadraticBezierTo(center.dx, center.dy - eyeH, center.dx + eyeW / 2, center.dy)
      ..quadraticBezierTo(center.dx, center.dy + eyeH, center.dx - eyeW / 2, center.dy)
      ..close();
    canvas.drawPath(eye, Paint()..color = AppColors.bg);
    canvas.drawPath(
      eye,
      Paint()
        ..color = AppColors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.save();
    canvas.clipPath(eye);
    canvas.drawCircle(center, eyeW * 0.17, Paint()..color = AppColors.amber);
    canvas.drawCircle(center, eyeW * 0.08, Paint()..color = AppColors.bg);
    canvas.drawCircle(center + Offset(eyeW * 0.05, -eyeW * 0.05), eyeW * 0.03, Paint()..color = AppColors.text);
    canvas.restore();

    // Pontos de landmark ao redor do olho.
    final dots = Paint()..color = AppColors.cyan;
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2;
      canvas.drawCircle(
          center + Offset(math.cos(a) * eyeW * 0.5, math.sin(a) * (eyeH + 4) * 0.95), 1.8, dots);
    }

    // Legenda EAR.
    final tp = TextPainter(
      text: TextSpan(
        text: 'EAR ${(0.18 + 0.12 * open).toStringAsFixed(2)}',
        style: const TextStyle(
            fontFamily: displayFont, color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + eyeW * 0.30));
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.t != t;
}
