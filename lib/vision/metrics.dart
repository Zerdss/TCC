import 'dart:math' as math;

/// Ponto 2D em coordenadas da imagem (pixels).
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;
}

double _dist(Pt a, Pt b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// EAR (Eye Aspect Ratio) a partir do contorno do olho do ML Kit.
///
/// O ML Kit devolve 16 pontos por olho: o índice 0 e o índice 8 são os cantos;
/// 1..7 percorrem a pálpebra superior e 9..15 a inferior (sentido horário).
/// Assim, o ponto `i` da pálpebra superior fica "em frente" ao ponto `16 - i`.
///
/// Equivale à fórmula clássica de Soukupová & Čech
/// `EAR = (|p2-p6| + |p3-p5|) / (2·|p1-p4|)`, mas usando três pares verticais
/// (média das alturas ÷ largura), o que reduz o ruído do contorno.
double? eyeAspectRatio(List<Pt> eye) {
  if (eye.length < 16) return null;
  final width = _dist(eye[0], eye[8]);
  if (width < 1e-6) return null;
  const pairs = [3, 4, 5];
  var heights = 0.0;
  for (final i in pairs) {
    heights += _dist(eye[i], eye[16 - i]);
  }
  return (heights / pairs.length) / width;
}

/// MAR (Mouth Aspect Ratio): abertura interna da boca ÷ largura da boca.
///
/// * `upperLipBottom` (9 pontos) e `lowerLipTop` (9 pontos) formam a abertura
///   interna; usamos os três pontos centrais de cada um.
/// * `upperLipTop` (11 pontos) tem os cantos da boca no primeiro e no último índice.
double? mouthAspectRatio({
  required List<Pt> upperLipTop,
  required List<Pt> upperLipBottom,
  required List<Pt> lowerLipTop,
}) {
  if (upperLipTop.length < 2 || upperLipBottom.length < 9 || lowerLipTop.length < 9) return null;
  final width = _dist(upperLipTop.first, upperLipTop.last);
  if (width < 1e-6) return null;
  // upperLipBottom percorre da esquerda p/ direita; lowerLipTop da direita p/ esquerda.
  var gap = 0.0;
  for (var i = 3; i <= 5; i++) {
    gap += _dist(upperLipBottom[i], lowerLipTop[8 - i]);
  }
  return (gap / 3) / width;
}

/// Média móvel simples usada para suavizar EAR e MAR.
class MovingAverage {
  MovingAverage([this.size = 5]);
  final int size;
  final List<double> _values = [];

  double push(double value) {
    _values.add(value);
    if (_values.length > size) _values.removeAt(0);
    return average;
  }

  double get average => _values.isEmpty ? 0 : _values.reduce((a, b) => a + b) / _values.length;

  void reset() => _values.clear();
}

/// PERCLOS: fração do tempo com olhos fechados numa janela deslizante (padrão 60 s).
class PerclosWindow {
  PerclosWindow([this.windowMs = 60000]);
  final int windowMs;
  final List<({int time, bool closed})> _samples = [];

  double add(int time, bool closed) {
    _samples.add((time: time, closed: closed));
    final cutoff = time - windowMs;
    while (_samples.isNotEmpty && _samples.first.time < cutoff) {
      _samples.removeAt(0);
    }
    if (_samples.length < 2) return 0;
    var closedMs = 0;
    for (var i = 0; i < _samples.length - 1; i++) {
      if (_samples[i].closed) closedMs += _samples[i + 1].time - _samples[i].time;
    }
    return closedMs / math.max(time - _samples.first.time, 1);
  }

  void reset() => _samples.clear();
}

double clampD(double v, double min, double max) => math.min(math.max(v, min), max);

double median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}
