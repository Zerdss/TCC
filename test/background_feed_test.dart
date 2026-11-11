import 'package:fatigue_guard/vision/vision_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Olho com 16 pontos: cantos em 0 e 8, abertura [h], largura 30.
List<double> eye(double x0, double y0, double h) {
  final pts = <double>[];
  for (var i = 0; i < 16; i++) {
    final upper = i <= 8;
    final k = upper ? i : 16 - i;
    final x = x0 + 30 * k / 8;
    final dy = (k == 0 || k == 8) ? 0.0 : (upper ? -h / 2 : h / 2);
    pts..add(x)..add(y0 + dy);
  }
  return pts;
}

List<double> line(int n, double x0, double y, double width) =>
    [for (var i = 0; i < n; i++) ...[x0 + width * i / (n - 1), y]];

Map<Object?, Object?> frame({double eyeH = 9}) => {
      'w': 480.0,
      'h': 640.0,
      'box': [140.0, 200.0, 340.0, 440.0],
      'le': eye(180, 280, eyeH),
      're': eye(260, 280, eyeH),
      'ult': line(11, 200, 380, 80),
      'ulb': line(9, 205, 385, 70),
      'llt': [for (var i = 0; i < 9; i++) ...[275.0 - 70 * i / 8, 395.0]],
      'llb': line(9, 205, 400, 70),
      'ex': 2.0,
      'ey': -1.0,
      'ez': 0.5,
      'lp': 0.9,
      'rp': 0.95,
      'sp': 0.1,
    };

void main() {
  test('quadro do serviço nativo vira FaceInput com contornos e ângulos', () {
    final f = FaceInput.fromMap(frame())!;
    expect(f.leftEye, hasLength(16));
    expect(f.upperLipTop, hasLength(11));
    expect(f.box.width, 200);
    expect(f.pitch, 2);
    expect(f.yaw, -1);
    expect(f.roll, 0.5);
    expect(f.leftEyeOpen, 0.9);
    expect(FaceInput.fromMap({'w': 480.0, 'h': 640.0}), isNull); // sem rosto
  });

  test('em segundo plano os quadros do serviço alimentam o monitoramento', () async {
    final v = VisionController();
    v.handleBackgroundFrame(frame()); // ignorado: ainda não está em segundo plano
    expect(v.metrics.ear, 0);
    await v.startBackgroundFeed();
    expect(v.isMonitoring, isTrue);
    v.handleBackgroundFrame(frame());
    expect(v.metrics.ear, closeTo(0.3, 0.01)); // 9 / 30
    expect(v.faceTracking, isTrue);
    v.handleBackgroundFrame({'w': 480.0, 'h': 640.0});
    expect(v.overlay, isNull);
    v.dispose();
  });
}
