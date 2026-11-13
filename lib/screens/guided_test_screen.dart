import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/voice.dart';
import '../theme.dart';
import '../vision/fatigue_engine.dart';
import '../vision/guided_test.dart';
import '../vision/vision_controller.dart';
import '../widgets/camera_panel.dart';
import '../widgets/common.dart';
import 'calibration_screen.dart';

enum _Stage { intro, running, done }

/// Teste guiado: executa o protocolo de validação (Tabela 3 do TCC) com voz,
/// observa o status do app e calcula a matriz de confusão no final.
class GuidedTestScreen extends StatefulWidget {
  const GuidedTestScreen({super.key, required this.vision, this.initialResults});
  final VisionController vision;

  /// Abre direto no resultado (para rever um teste ou nos testes automáticos).
  final List<GuidedTrialResult>? initialResults;

  @override
  State<GuidedTestScreen> createState() => _GuidedTestScreenState();
}

class _GuidedTestScreenState extends State<GuidedTestScreen> {
  VisionController get vision => widget.vision;

  _Stage _stage = _Stage.intro;
  GuidedSize _size = GuidedSize.quick;
  final _person = TextEditingController();
  List<GuidedBehavior> _plan = const [];
  final List<GuidedTrialResult> _results = [];
  int _index = 0;
  String _instruction = '';
  String _phase = '';
  GuidedTrial? _trial;
  /// Cada execução tem um número; parar ou sair invalida a execução em andamento.
  int _runId = 0;
  bool _alive(int id) => mounted && id == _runId;
  final _clock = Stopwatch()..start();

  int get _now => _clock.elapsedMilliseconds + 1;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialResults;
    if (initial != null && initial.isNotEmpty) {
      _results.addAll(initial);
      _stage = _Stage.done;
    }
    if (vision.calibrationStep != null) vision.beginMonitoring();
    vision.acquireCamera();
  }

  @override
  void dispose() {
    _runId++;
    Voice.instance.stop();
    vision.resetAcknowledge();
    vision.releaseCamera();
    _person.dispose();
    super.dispose();
  }

  /// Comportamentos que fazem sentido com os ajustes atuais.
  List<GuidedBehavior> _buildPlan() => guidedPlan(_size).where((b) {
        if (b.id == 'cabeca' && !vision.settings.headEnabled) return false;
        // No escuro (modo noite) o rosto sumir não gera alerta: não dá para testar.
        if (b.id == 'rosto' && (!vision.settings.faceLostEnabled || vision.nightActive)) return false;
        return true;
      }).toList();

  Future<void> _start() async {
    final id = ++_runId;
    setState(() {
      _plan = _buildPlan();
      _results.clear();
      _index = 0;
      _stage = _Stage.running;
      _phase = 'Preparando';
      _instruction = 'Olhe para a câmera.';
    });
    await Voice.instance.say('Vamos começar o teste guiado. Olhe para a câmera e siga as minhas instruções.');
    final reps = <String, int>{};
    for (var i = 0; i < _plan.length; i++) {
      if (!_alive(id)) return;
      final b = _plan[i];
      final rep = reps[b.id] = (reps[b.id] ?? 0) + 1;
      setState(() {
        _index = i;
        _instruction = b.instruction;
        _phase = 'Volte à posição normal';
      });
      if (!await _waitNormal(id, 6000) && _alive(id)) {
        // Ainda em alerta ou sem rosto: pede para voltar antes de começar.
        await Voice.instance.say('Volte para a posição normal, olhando para a câmera.');
        await _waitNormal(id, 12000);
      }
      if (!_alive(id)) return;
      setState(() => _phase = 'Ouça a instrução');
      await Voice.instance.say(b.instruction);
      if (!_alive(id)) return;
      vision.playCue('tick');
      final trial = _trial = GuidedTrial(b, rep, _now);
      setState(() => _phase = 'Observando');
      await _observe(id, trial);
      if (!_alive(id)) return;
      _results.add(trial.result);
      _trial = null;
      if (trial.gotAlert) vision.acknowledgeAlert(); // silencia para a voz ser ouvida
      setState(() => _phase = trial.result.correct ? 'Acertou' : 'Errou');
      vision.playCue('ok');
      await Voice.instance.say(b.expectAlert
          ? (trial.gotAlert ? b.backToNormal : 'O alerta não apareceu. ${b.backToNormal}')
          : (trial.gotAlert ? 'Houve um alarme. Vamos continuar.' : 'Certo.'));
      if (!_alive(id)) return;
      vision.resetAcknowledge();
    }
    if (!_alive(id)) return;
    setState(() => _stage = _Stage.done);
    final sum = GuidedSummary(_results);
    final correct = _results.where((r) => r.correct).length;
    await Voice.instance.say('Teste concluído. O aplicativo acertou $correct de ${sum.total} tentativas.');
  }

  /// Espera o status ficar NORMAL com o rosto visível por 1 s seguido.
  /// Retorna `false` se o tempo máximo acabou antes disso.
  Future<bool> _waitNormal(int id, int maxMs) async {
    final start = _now;
    var okSince = 0;
    while (_alive(id) && _now - start < maxMs) {
      final ok = vision.status == FatigueStatus.normal && vision.faceTracking;
      if (ok) {
        if (okSince == 0) okSince = _now;
        if (_now - okSince >= 1000) return true;
      } else {
        okSince = 0;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  Future<void> _observe(int id, GuidedTrial trial) async {
    while (_alive(id)) {
      if (trial.observe(_now, vision.status)) return;
      if (mounted) setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _stop() {
    _runId++;
    _trial = null;
    Voice.instance.stop();
    vision.resetAcknowledge();
    setState(() => _stage = _results.isEmpty ? _Stage.intro : _Stage.done);
  }

  Future<void> _export() async {
    final sum = GuidedSummary(_results);
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}h${two(now.minute)}';
    final file = File(p.join(dir.path, 'FatigueGuard_teste_guiado_$stamp.csv'));
    await file.writeAsString('﻿${sum.toCsv(at: now, person: _person.text.trim())}');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: 'Fatigue Guard — teste guiado',
      text: 'Resultado do teste guiado do Fatigue Guard (protocolo de validação do TCC).',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(children: [
      const PageTitle(
        kicker: 'PROTOCOLO DE VALIDAÇÃO',
        title: 'Teste guiado',
        subtitle: 'O app pede cada comportamento por voz, observa a resposta e calcula os acertos no final.',
      ),
      const SizedBox(height: 16),
      switch (_stage) {
        _Stage.intro => _intro(),
        _Stage.running => _running(),
        _Stage.done => _done(),
      },
    ]);
  }

  // ------------------------------------------------------------------ início
  Widget _intro() {
    final calibrated = vision.thresholds.calibrated;
    final plan = _buildPlan();
    final minutes = (plan.fold<int>(0, (a, b) => a + b.windowMs + 7000) / 60000).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Como funciona', style: AppText.h3),
          const SizedBox(height: 8),
          for (final t in [
            'Deixe o celular apoiado à frente, como no carro, e aumente o volume: a voz dá as instruções.',
            'Faça cada comportamento quando a voz pedir. O app anota sozinho se acertou e o tempo até o alerta.',
            'Comportamentos normais (piscar, falar, sorrir) não devem gerar alerta; sinais de sono devem.',
            'No final aparecem a matriz de confusão e as medidas, e dá para exportar em CSV.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 6), child: StatusDot()),
                const SizedBox(width: 10),
                Expanded(child: Text(t, style: AppText.body)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      if (!calibrated) ...[
        Container(
          key: const Key('guided-needs-calibration'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.yellow.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.yellow),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.yellow),
            const SizedBox(width: 10),
            const Expanded(child: Text('Faça a calibração antes, na mesma posição do celular.', style: AppText.body)),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => CalibrationScreen(vision: vision)))
                  .then((_) => setState(() {})),
              child: const Text('Calibrar'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      const Text('TAMANHO DO TESTE', style: AppText.section),
      const SizedBox(height: 8),
      SegmentedButton<GuidedSize>(
        key: const Key('guided-size'),
        showSelectedIcon: false,
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.panel),
          foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? AppColors.accentDark : AppColors.muted),
        ),
        segments: [
          for (final sz in GuidedSize.values)
            ButtonSegment(
              value: sz,
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${sz.label}\n${guidedPlan(sz).length} testes', textAlign: TextAlign.center),
              ),
            ),
        ],
        selected: {_size},
        onSelectionChanged: (v) => setState(() => _size = v.first),
      ),
      const SizedBox(height: 6),
      Text('${plan.length} tentativas, cerca de $minutes min.', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 14),
      TextField(
        controller: _person,
        decoration: const InputDecoration(labelText: 'Quem está testando (opcional)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      SizedBox(height: 230, child: Center(child: AspectRatio(aspectRatio: 3 / 4, child: CameraPanel(vision: vision)))),
      const SizedBox(height: 16),
      PrimaryButton(
        key: const Key('guided-start'),
        label: 'Começar o teste',
        icon: Icons.play_arrow_rounded,
        onPressed: vision.state == EngineState.running ? _start : null,
      ),
    ]);
  }

  // ------------------------------------------------------------------ em andamento
  Widget _running() {
    return ListenableBuilder(
      listenable: vision,
      builder: (context, _) {
        final trial = _trial;
        final b = _plan.isEmpty ? null : _plan[_index];
        final frac = trial == null ? 0.0 : ((_now - trial.startMs) / trial.behavior.windowMs).clamp(0.0, 1.0);
        final status = vision.status;
        final (Color sc, String st) = switch (status) {
          FatigueStatus.normal => (AppColors.green, 'NORMAL'),
          FatigueStatus.attention => (AppColors.yellow, 'ATENÇÃO'),
          FatigueStatus.alert => (AppColors.red, 'ALERTA'),
        };
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Tentativa ${_index + 1} de ${_plan.length}', style: AppText.kicker),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(20)),
              child: Text(st, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _plan.isEmpty ? 0 : (_index + (trial == null ? 0 : frac)) / _plan.length,
              minHeight: 6,
              backgroundColor: AppColors.panel2,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b?.label.toUpperCase() ?? '', style: AppText.kicker),
              const SizedBox(height: 6),
              Text(_instruction, key: const Key('guided-instruction'), style: AppText.h3.copyWith(fontSize: 22)),
              const SizedBox(height: 10),
              Row(children: [
                Icon(
                  _phase == 'Observando'
                      ? Icons.visibility_outlined
                      : _phase == 'Ouça a instrução'
                          ? Icons.record_voice_over_outlined
                          : _phase == 'Acertou'
                              ? Icons.check_circle
                              : _phase == 'Errou'
                                  ? Icons.cancel
                                  : Icons.hourglass_empty,
                  size: 18,
                  color: _phase == 'Errou'
                      ? AppColors.red
                      : _phase == 'Acertou'
                          ? AppColors.green
                          : AppColors.accentDark,
                ),
                const SizedBox(width: 6),
                Text(_phase, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (b != null)
                  Text(b.expectAlert ? 'Esperado: ALERTA' : 'Esperado: nenhum alerta',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
              if (trial != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value: frac, minHeight: 8, backgroundColor: AppColors.panel2, color: AppColors.blue),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(height: 260, child: Center(child: AspectRatio(aspectRatio: 3 / 4, child: CameraPanel(vision: vision)))),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in _results)
              Tooltip(
                message: '${r.behavior.label} ${r.repetition}: ${r.correct ? 'acertou' : 'errou'}',
                child: Icon(r.correct ? Icons.check_circle : Icons.cancel,
                    size: 20, color: r.correct ? AppColors.green : AppColors.red),
              ),
          ]),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('guided-stop'),
            onPressed: _stop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Parar o teste'),
          ),
        ]);
      },
    );
  }

  // ------------------------------------------------------------------ resultado
  Widget _done() {
    final sum = GuidedSummary(_results);
    String pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';
    final eyes = sum.rows.where((r) => r.behavior.id == 'olhos').toList();
    final eyesTime = eyes.isEmpty ? null : eyes.first.avgTimeMs;
    Widget metric(String v, String label, Color c) => Expanded(
          child: Container(
            height: 112,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(v, style: AppText.number.copyWith(fontSize: 26, color: c)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSoft)),
            ]),
          ),
        );
    Widget cell(String code, int v, Color c, String desc) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Text('$v', style: AppText.number.copyWith(fontSize: 24, color: c)),
              Text(code, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 12)),
              Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: AppColors.textSoft)),
            ]),
          ),
        );
    return Column(key: const Key('guided-summary'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        metric(pct(sum.sensitivity), 'sinais de sono detectados (sensibilidade)', AppColors.accent),
        const SizedBox(width: 8),
        metric('${sum.fp}', 'alarmes falsos', sum.fp == 0 ? AppColors.green : AppColors.red),
        const SizedBox(width: 8),
        metric(eyesTime == null ? '–' : '${formatSeconds(eyesTime.round())} s', 'tempo médio até o alerta (olhos)',
            AppColors.blue),
      ]),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Acertos por comportamento', style: AppText.cardTitle),
          const SizedBox(height: 8),
          for (final r in sum.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(r.correct == r.total ? Icons.check_circle : Icons.error_outline,
                    size: 18, color: r.correct == r.total ? AppColors.green : AppColors.yellow),
                const SizedBox(width: 8),
                Expanded(child: Text(r.behavior.label)),
                Text('${r.correct}/${r.total}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Matriz de confusão', style: AppText.cardTitle),
          const SizedBox(height: 4),
          const Text('Positivo = o app deu ALERTA.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            cell('VP', sum.vp, AppColors.green, 'sono com alerta'),
            cell('FN', sum.fn, AppColors.red, 'sono sem alerta'),
          ]),
          Row(children: [
            cell('FP', sum.fp, AppColors.red, 'alarme falso'),
            cell('VN', sum.vn, AppColors.green, 'normal sem alerta'),
          ]),
          const SizedBox(height: 10),
          Text(
            'Especificidade ${pct(sum.specificity)} • Precisão ${pct(sum.precision)} • Acurácia ${pct(sum.accuracy)} • '
            'Falsos alarmes ${pct(sum.falseAlarmRate)} • Avisos de atenção em normais: ${sum.attentionOnNormal}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      const Text(
        'O tempo até o alerta inclui a reação da pessoa à instrução. Teste encenado: é uma indicação, não a validação '
        'com voluntários.',
        style: TextStyle(fontSize: 11.5, color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      PrimaryButton(
        key: const Key('guided-export'),
        label: 'Exportar resultado (CSV)',
        icon: Icons.ios_share,
        onPressed: _results.isEmpty ? null : _export,
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() => _stage = _Stage.intro),
        icon: const Icon(Icons.replay),
        label: const Text('Fazer de novo'),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Voltar ao painel'),
      ),
    ]);
  }
}
