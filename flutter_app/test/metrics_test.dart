import 'package:fatigue_guard/vision/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gera um contorno de olho no formato do ML Kit (16 pontos, cantos em 0 e 8).
List<Pt> eye({double width = 40, double height = 12}) {
  return List.generate(16, (i) {
    final t = i <= 8 ? i / 8 : (16 - i) / 8;
    final x = t * width;
    final lid = height / 2 * (1 - (2 * t - 1) * (2 * t - 1)); // parábola
    return Pt(x, i <= 8 ? -lid : lid);
  });
}

void main() {
  test('EAR diminui quando o olho fecha', () {
    final open = eyeAspectRatio(eye(height: 14))!;
    final closed = eyeAspectRatio(eye(height: 2))!;
    expect(open, greaterThan(0.25));
    expect(closed, lessThan(0.06));
  });

  test('EAR retorna null com pontos insuficientes', () {
    expect(eyeAspectRatio(const [Pt(0, 0)]), isNull);
  });

  test('MAR cresce com a abertura da boca', () {
    List<Pt> line(double y, int n, {bool reverse = false}) {
      final pts = List.generate(n, (i) => Pt(10 + i * 40 / (n - 1), y));
      return reverse ? pts.reversed.toList() : pts;
    }

    double mar(double gap) => mouthAspectRatio(
          upperLipTop: line(-5, 11),
          upperLipBottom: line(0, 9),
          lowerLipTop: line(gap, 9, reverse: true),
        )!;

    expect(mar(1), closeTo(1 / 40, 1e-9));
    expect(mar(30), closeTo(30 / 40, 1e-9));
  });

  test('MovingAverage usa apenas os últimos N valores', () {
    final avg = MovingAverage(3);
    avg.push(1);
    avg.push(2);
    avg.push(3);
    expect(avg.push(10), closeTo(5, 1e-9));
  });

  test('PERCLOS calcula a fração de tempo fechado na janela', () {
    final w = PerclosWindow(60000);
    w.add(0, true);
    w.add(1000, false);
    expect(w.add(4000, false), closeTo(0.25, 1e-9));
  });
}
