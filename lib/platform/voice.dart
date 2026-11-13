import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Voz natural em português, usando a leitura em voz alta do próprio celular
/// (no Android, normalmente a voz do Google). Escolhe a voz pt-BR de melhor
/// qualidade instalada, que funcione sem internet.
class Voice {
  Voice._();
  static final instance = Voice._();

  FlutterTts? _tts;
  bool _ready = false;
  bool _failed = false;

  /// Velocidade de fala (Android: 0,5 é o ritmo normal de conversa).
  static const double rate = 0.48;

  Future<FlutterTts?> _engine() async {
    if (_failed || kIsWeb) return null;
    if (_ready) return _tts;
    try {
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion(true);
      await tts.setLanguage('pt-BR');
      await tts.setSpeechRate(defaultTargetPlatform == TargetPlatform.iOS ? 0.5 : rate);
      await tts.setPitch(1.0);
      await tts.setVolume(1.0);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Toca mesmo com a chave do silencioso e abaixa a música/GPS enquanto fala.
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ]);
      }
      await _pickBestVoice(tts);
      _tts = tts;
      _ready = true;
      return tts;
    } catch (_) {
      _failed = true; // sem voz (ex.: testes): o app segue só com o texto na tela
      return null;
    }
  }

  Future<void> _pickBestVoice(FlutterTts tts) async {
    try {
      final voices = await tts.getVoices;
      if (voices is! List) return;
      Map? best;
      var bestScore = -1;
      for (final v in voices) {
        if (v is! Map) continue;
        final locale = '${v['locale'] ?? ''}'.toLowerCase().replaceAll('_', '-');
        if (!locale.startsWith('pt-br') && locale != 'por-bra') continue;
        final name = '${v['name'] ?? ''}'.toLowerCase();
        final quality = '${v['quality'] ?? ''}'.toLowerCase();
        final network = '${v['network_required'] ?? ''}' == '1' || name.contains('network');
        var score = 0;
        if (!network) score += 10; // funciona sem internet
        if (quality.contains('very high')) {
          score += 5;
        } else if (quality.contains('high')) {
          score += 3;
        }
        if (name.contains('local')) score += 1;
        if (score > bestScore) {
          bestScore = score;
          best = v;
        }
      }
      if (best != null) {
        await tts.setVoice({'name': '${best['name']}', 'locale': '${best['locale']}'});
      }
    } catch (_) {}
  }

  /// Fala [text] e espera terminar.
  Future<void> say(String text) async {
    final tts = await _engine();
    if (tts == null) {
      // Sem voz: dá um tempo de leitura proporcional ao texto.
      await Future<void>.delayed(Duration(milliseconds: 300 + 45 * text.length));
      return;
    }
    try {
      await tts.stop();
      // Limite de segurança: se o celular não avisar o fim da fala, segue mesmo assim.
      await tts.speak(text).timeout(Duration(milliseconds: 3000 + 120 * text.length), onTimeout: () => null);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
