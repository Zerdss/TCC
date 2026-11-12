import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Modo noite: com pouca luz, a câmera frontal quase não enxerga o rosto. O app
// usa a própria tela como luz de apoio: a cada [NightLight.periodMs] (padrão
// 20 s) o brilho SOBE DEVAGAR, fica alto alguns segundos e DESCE DEVAGAR —
// sem clarão. Se durante a luz aparecer suspeita de sono, a luz continua acesa
// até normalizar. Entre as rampas, a decisão fica com a cabeça (modo inclinação).
// ---------------------------------------------------------------------------

/// Brilho médio da imagem (0 a 255) abaixo do qual conta como escuro, e acima
/// do qual volta a contar como claro (histerese, para não ficar trocando).
const double darkLuma = 45;
const double brightLuma = 65;

/// Tempo seguido escuro (ou claro) para trocar de modo.
const int lightSwitchMs = 3000;

/// Rampa de subida/descida do brilho e tempo com a luz no máximo.
const int nightRampMs = 1500;
const int nightHoldMs = 3000;

/// Com suspeita de sono, a luz fica acesa por mais este tempo (até [nightMaxLitMs]).
const int nightExtendMs = 3000;
const int nightMaxLitMs = 15000;

/// Intervalo mínimo com a luz apagada entre duas rampas.
const int nightMinGapMs = 2000;

/// Detecta pouca luz pelo brilho médio da imagem, com histerese.
class DarkDetector {
  bool dark = false;
  double? luma;
  int _since = 0;

  void reset() {
    dark = false;
    luma = null;
    _since = 0;
  }

  /// [luma] = brilho médio da imagem (0 a 255).
  void update(double luma, int now) {
    this.luma = luma;
    final wantsChange = dark ? luma >= brightLuma : luma < darkLuma;
    if (!wantsChange) {
      _since = 0;
      return;
    }
    if (_since == 0) _since = now;
    if (now - _since >= lightSwitchMs) {
      dark = !dark;
      _since = 0;
    }
  }
}

enum _Phase { off, up, full, down }

/// Quanto a luz de apoio deve estar acesa agora (0 = apagada, 1 = máximo).
class NightLight {
  NightLight({this.periodMs = 20000});

  /// Intervalo entre o início de uma rampa e o da próxima.
  int periodMs;

  _Phase _phase = _Phase.off;
  int _since = 0, _litSince = 0, _fullUntil = 0, _nextCycle = 0;
  double _from = 0;
  double level = 0;

  /// A luz está acesa (subindo, no máximo ou descendo).
  bool get lit => _phase != _Phase.off;

  void reset() {
    _phase = _Phase.off;
    _since = _litSince = _fullUntil = _nextCycle = 0;
    _from = level = 0;
  }

  /// [dark] = está escuro; [suspicious] = há sinal de sono (mantém a luz acesa).
  double update(int now, {required bool dark, bool suspicious = false}) {
    if (!dark) {
      if (_phase == _Phase.up || _phase == _Phase.full) _startDown(now);
      _nextCycle = 0;
    } else if (_phase == _Phase.off) {
      if (_nextCycle == 0) _nextCycle = now; // escureceu: já acende a primeira vez
      if (now >= _nextCycle) {
        _phase = _Phase.up;
        _since = now;
        _litSince = now;
        _from = level;
      }
    }
    switch (_phase) {
      case _Phase.up:
        level = math.min(1, _from + (now - _since) / nightRampMs);
        if (level >= 1) {
          _phase = _Phase.full;
          _since = now;
          _fullUntil = now + nightHoldMs;
        }
      case _Phase.full:
        level = 1;
        if (suspicious) {
          // Fica acesa enquanto houver suspeita, mas no total no máximo 15 s (com a descida).
          _fullUntil = math.min(math.max(_fullUntil, now + nightExtendMs), _litSince + nightMaxLitMs - nightRampMs);
        }
        if (now >= _fullUntil || !dark) _startDown(now);
      case _Phase.down:
        level = math.max(0, _from - (now - _since) / nightRampMs);
        if (level <= 0) {
          level = 0;
          _phase = _Phase.off;
          if (dark) _nextCycle = math.max(_litSince + periodMs, now + nightMinGapMs);
        }
      case _Phase.off:
        level = 0;
    }
    return level;
  }

  void _startDown(int now) {
    _phase = _Phase.down;
    _since = now;
    _from = level;
  }
}

/// Brilho médio (0 a 255) de uma imagem em tons de cinza/luminância, lendo só
/// alguns pontos (rápido o bastante para todo quadro).
/// [length] limita a leitura (ex.: só o plano Y de uma imagem NV21).
double sampleLuma(List<int> bytes, {int step = 97, int offset = 0, int stride = 1, int? length}) {
  var sum = 0, n = 0;
  final end = math.min(length ?? bytes.length, bytes.length);
  for (var i = offset; i < end; i += step * stride) {
    sum += bytes[i];
    n++;
  }
  return n == 0 ? 0 : sum / n;
}
