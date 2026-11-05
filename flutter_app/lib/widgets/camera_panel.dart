import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/metrics.dart';
import '../vision/vision_controller.dart';

/// Pré‑visualização da câmera frontal com malha facial, contornos de olhos e
/// boca, caixa do rosto, elipse‑guia e selo de orientação de enquadramento.
class CameraPanel extends StatelessWidget {
  const CameraPanel({super.key, required this.vision});

  final VisionController vision;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vision,
      builder: (context, _) {
        final controller = vision.camera;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.panel,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null && controller.value.isInitialized)
                    _CoverPreview(controller: controller)
                  else
                    _Placeholder(vision: vision),
                  CustomPaint(painter: _OverlayPainter(vision.overlay, mirror: vision.isFrontCamera)),
                  if (vision.state == EngineState.running)
                    Positioned(top: 10, left: 10, right: 10, child: _GuideBadge(guide: vision.guide)),
                  const Positioned(left: 12, bottom: 12, child: _LocalLabel()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    // previewSize vem em orientação paisagem; o app roda travado em retrato.
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: size.height, height: size.width, child: CameraPreview(controller)),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.vision});
  final VisionController vision;

  @override
  Widget build(BuildContext context) {
    final isError = vision.state == EngineState.error;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isError)
            const Icon(Icons.videocam_off_outlined, color: AppColors.red, size: 40)
          else
            const SizedBox(
                width: 32, height: 32, child: CircularProgressIndicator(color: AppColors.amber, strokeWidth: 3)),
          const SizedBox(height: 14),
          Text(
            isError ? vision.error : 'Inicializando câmera e detector facial...',
            textAlign: TextAlign.center,
            style: TextStyle(color: isError ? const Color(0xFFFCA5A5) : AppColors.muted, fontSize: 13),
          ),
          if (isError) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: vision.start,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuideBadge extends StatelessWidget {
  const _GuideBadge({required this.guide});
  final FramingGuide guide;

  @override
  Widget build(BuildContext context) {
    final color = guide.good ? AppColors.green : AppColors.amber;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6090D14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(guide.text,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalLabel extends StatelessWidget {
  const _LocalLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xCC090D14), borderRadius: BorderRadius.circular(6)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.radio_button_checked, size: 13, color: AppColors.red),
          SizedBox(width: 5),
          Text('PROCESSAMENTO LOCAL',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8)),
        ],
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.data, {required this.mirror});

  final FaceOverlayData? data;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    // Elipse‑guia de enquadramento.
    final guide = Paint()
      ..color = const Color(0x8C94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final oval = Rect.fromCenter(
        center: size.center(Offset.zero), width: size.width * 0.62, height: size.height * 0.62);
    _dashedOval(canvas, oval, guide);

    final d = data;
    if (d == null) return;
    final scale = math.max(size.width / d.imageSize.width, size.height / d.imageSize.height);
    final dx = (size.width - d.imageSize.width * scale) / 2;
    final dy = (size.height - d.imageSize.height * scale) / 2;
    Offset map(double x, double y) {
      final px = dx + x * scale;
      return Offset(mirror ? size.width - px : px, dy + y * scale);
    }

    final dots = Paint()..color = const Color(0xB3F59E0B);
    for (final p in d.allPoints) {
      canvas.drawCircle(map(p.x, p.y), 1.4, dots);
    }

    final ring = Paint()
      ..color = AppColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final points in d.rings) {
      if (points.length < 3) continue;
      final path = Path()..moveTo(map(points[0].x, points[0].y).dx, map(points[0].x, points[0].y).dy);
      for (final Pt p in points.skip(1)) {
        final o = map(p.x, p.y);
        path.lineTo(o.dx, o.dy);
      }
      path.close();
      canvas.drawPath(path, ring);
    }

    final a = map(d.box.left, d.box.top);
    final b = map(d.box.right, d.box.bottom);
    canvas.drawRect(
      Rect.fromPoints(a, b),
      Paint()
        ..color = const Color(0xE610B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _dashedOval(Canvas canvas, Rect rect, Paint paint) {
    final metric = (Path()..addOval(rect)).computeMetrics().first;
    for (var t = 0.0; t < metric.length; t += 14) {
      canvas.drawPath(metric.extractPath(t, math.min(t + 7, metric.length)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => old.data != data || old.mirror != mirror;
}
