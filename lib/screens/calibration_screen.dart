import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/vision_controller.dart';
import '../widgets/camera_panel.dart';
import '../widgets/common.dart';
import 'demo_screen.dart';

class _Step {
  const _Step(this.label, this.icon, this.instruction, this.tip, this.prepare);
  final String label;
  final IconData icon;
  final String instruction;
  final String tip;

  /// Frase curta mostrada durante a contagem 3‑2‑1.
  final String prepare;
}

const _steps = [
  _Step('OLHOS ABERTOS', Icons.visibility_outlined,
      'Mantenha o olhar natural e os olhos abertos por alguns segundos.',
      'Olhe para a câmera como se estivesse olhando para a estrada.',
      'Olhe para a câmera com os olhos abertos'),
  _Step('OLHOS FECHADOS', Icons.visibility_off_outlined,
      'Agora feche os olhos suavemente. O sistema está aprendendo seu limiar pessoal.',
      'Mantenha o rosto parado. Abra os olhos quando ouvir o "plim" e sentir a vibração.',
      'Feche os olhos e espere o "plim"'),
  _Step('BOCEJO DE TESTE', Icons.record_voice_over_outlined,
      'Abra a boca como em um bocejo lento e sustentado para registrar seu padrão de MAR.',
      'Segure a boca bem aberta até ouvir o "plim".',
      'Abra a boca como num bocejo'),
  _Step('SORRISO / RISADA', Icons.sentiment_very_satisfied_outlined,
      'Sorria e ria naturalmente por alguns segundos. Isso ensina o sistema a não confundir '
          'expressões normais com fadiga.',
      'Etapa opcional — pode pular se preferir.',
      'Sorria e ria naturalmente'),
];

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.vision, this.onlyStep});

  final VisionController vision;

  /// Quando informado, refaz apenas esta etapa (ex.: 3 = sorriso) e volta.
  final int? onlyStep;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  late int step = widget.onlyStep ?? 0;
  bool _leavingToDemo = false;
  /// O painel ao vivo estava monitorando quando esta tela abriu? Precisa ser
  /// lido no initState, ANTES de beginCalibration — lido depois, já estaria em
  /// modo calibração e o painel nunca voltaria a monitorar.
  late final bool _wasMonitoring;

  /// Avança sozinho ao concluir cada etapa (útil na etapa de olhos fechados).
  bool _auto = true;

  /// Contagem regressiva antes de cada etapa (3, 2, 1). `null` = coletando.
  int? _countdown;
  Timer? _timer;
  Timer? _advanceTimer;
  bool _stepDone = false;

  VisionController get vision => widget.vision;
  bool get _single => widget.onlyStep != null;

  @override
  void initState() {
    super.initState();
    _wasMonitoring = vision.calibrationStep == null;
    _auto = vision.settings.autoAdvanceCalibration;
    vision.acquireCamera();
    vision.addListener(_onVision);
    _startStep(step);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advanceTimer?.cancel();
    vision.removeListener(_onVision);
    // Se abriu por cima do painel ao vivo, devolve o painel ao monitoramento.
    if (_wasMonitoring && !_leavingToDemo) vision.beginMonitoring();
    vision.releaseCamera();
    super.dispose();
  }

  /// Prepara a etapa: pausa a coleta e faz a contagem 3‑2‑1 com bipes.
  void _startStep(int s) {
    _timer?.cancel();
    _advanceTimer?.cancel();
    _stepDone = false;
    vision.beginCalibration(s, paused: true);
    setState(() => _countdown = 3);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      // Só conta com a câmera funcionando.
      if (vision.state != EngineState.running) return;
      final c = _countdown ?? 0;
      if (c > 1) {
        vision.playCue('tick');
        setState(() => _countdown = c - 1);
      } else {
        t.cancel();
        vision.playCue('tick');
        setState(() => _countdown = null);
        vision.resumeCalibration();
      }
    });
  }

  /// Detecta o fim da etapa: toca o "plim", vibra e (se automático) avança.
  void _onVision() {
    if (_stepDone || _countdown != null || vision.calibrationProgress < 100) return;
    _stepDone = true;
    vision.playCue('ok', vibrate: true);
    if (_auto) {
      _advanceTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) _next();
      });
    }
    if (mounted) setState(() {});
  }

  void _setAuto(bool value) {
    setState(() => _auto = value);
    vision.settings.autoAdvanceCalibration = value;
    vision.saveSettings();
    if (value && _stepDone) _next();
  }

  void _next() {
    _advanceTimer?.cancel();
    if (_single) {
      _finishSingle();
    } else if (step < 3) {
      setState(() => step++);
      _startStep(step);
    } else {
      _openDemo();
    }
  }

  void _finishSingle() {
    vision.saveCalibration();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Calibração do sorriso atualizada.')));
    Navigator.of(context).pop();
  }

  void _openDemo() {
    if (_leavingToDemo) return;
    _leavingToDemo = true;
    _timer?.cancel();
    _advanceTimer?.cancel();
    vision.saveCalibration();
    vision.beginMonitoring();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DemoScreen(vision: vision)));
  }

  @override
  Widget build(BuildContext context) {
    final info = _steps[step];
    return AppPage(
      children: [
        PageTitle(
          kicker: _single ? 'AJUSTE FINO' : 'ETAPA 02 / 04',
          title: _single ? 'Recalibrar sorriso' : 'Calibração pessoal',
          subtitle: 'Vamos ajustar os limiares para suas características faciais. Use a pré-visualização '
              'abaixo para se posicionar no centro do quadro.',
        ),
        const SizedBox(height: 18),
        if (!_single) ...[
          _StepIndicator(current: step),
          const SizedBox(height: 16),
        ],
        Stack(
          children: [
            CameraPanel(vision: vision),
            if (_countdown != null && vision.state == EngineState.running)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    key: const Key('calibration-countdown'),
                    color: const Color(0xD9F1F8F3),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('PREPARE-SE', style: AppText.kicker.copyWith(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('$_countdown',
                          style: AppText.number.copyWith(fontSize: 120, height: 1, color: AppColors.accent)),
                      const SizedBox(height: 8),
                      Text(info.prepare,
                          textAlign: TextAlign.center, style: AppText.h3.copyWith(fontSize: 22)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: vision,
          builder: (context, _) {
            final progress = vision.calibrationProgress;
            final done = progress >= 100;
            final running = vision.state == EngineState.running;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.panel2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: done ? AppColors.green : AppColors.accent),
                          ),
                          child: Icon(done ? Icons.check_rounded : info.icon,
                              color: done ? AppColors.green : AppColors.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text.rich(TextSpan(
                              text: '0${step + 1} ',
                              style: AppText.kicker,
                              children: const [
                                TextSpan(text: '/ 04', style: TextStyle(color: AppColors.muted)),
                              ],
                            )),
                            Text(info.label + (step == 3 && !_single ? ' (OPCIONAL)' : ''), style: AppText.h3),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(info.instruction, style: AppText.body.copyWith(color: AppColors.textSoft)),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.lightbulb_outline, size: 14, color: AppColors.accentDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(info.tip,
                              style: const TextStyle(color: AppColors.accentDark, fontSize: 12)),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: progress / 100),
                              duration: const Duration(milliseconds: 250),
                              builder: (context, v, _) => LinearProgressIndicator(
                                value: v,
                                minHeight: 8,
                                backgroundColor: AppColors.panel2,
                                color: done ? AppColors.green : AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('$progress%', style: AppText.number.copyWith(fontSize: 20)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        done
                            ? (_auto
                                ? 'Padrão registrado! ${_single || step == 3 ? 'Finalizando...' : 'Próxima etapa em instantes...'}'
                                : 'Padrão registrado com sucesso')
                            : !running
                                ? 'Aguardando câmera...'
                                : _countdown != null
                                    ? 'Começando em $_countdown...'
                                    : 'Analisando padrão facial...',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      if (running) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          _LiveValue(label: 'EAR', value: vision.metrics.ear.toStringAsFixed(3)),
                          const SizedBox(width: 8),
                          _LiveValue(label: 'MAR', value: vision.metrics.mar.toStringAsFixed(3)),
                          const SizedBox(width: 8),
                          _LiveValue(label: 'FPS', value: vision.fps.toStringAsFixed(0)),
                        ]),
                      ],
                    ],
                  ),
                ),
                if (vision.thresholds.eyeSeparation != null) ...[
                  const SizedBox(height: 12),
                  _EyeQualityBanner(low: vision.thresholds.lowEyeConfidence,
                      usesProb: vision.thresholds.eyeProbThreshold != null),
                ],
                const SizedBox(height: 18),
                PrimaryButton(
                  key: const Key('button-proxima'),
                  label: done
                      ? (_single ? 'Salvar e voltar' : step == 3 ? 'Abrir painel ao vivo' : 'Próxima etapa')
                      : 'Aguardando leitura...',
                  icon: done ? Icons.arrow_forward : Icons.center_focus_weak,
                  onPressed: done ? _next : null,
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const Key('switch-avancar-auto'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _auto,
                  onChanged: _setAuto,
                  title: const Text('Avançar automaticamente',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: const Text(
                    'Toca um "plim" e vibra ao concluir cada etapa e já passa para a próxima — '
                    'não precisa abrir os olhos para tocar no botão.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
                if (step == 3 && !_single)
                  TextButton(
                    key: const Key('button-skip-step'),
                    onPressed: _openDemo,
                    child: const Text('Pular etapa opcional',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Expanded(
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 5,
                decoration: BoxDecoration(
                  color: i < current
                      ? AppColors.green
                      : i == current
                          ? AppColors.accent
                          : AppColors.panel2,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(height: 6),
              Icon(_steps[i].icon,
                  size: 16,
                  color: i < current
                      ? AppColors.green
                      : i == current
                          ? AppColors.accent
                          : AppColors.muted),
            ]),
          ),
          if (i < _steps.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _LiveValue extends StatelessWidget {
  const _LiveValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(value, style: AppText.number.copyWith(fontSize: 16)),
        ]),
      ),
    );
  }
}

/// Resultado da etapa de olhos fechados: os olhos estão bem visíveis nesta
/// posição do celular? Se não, o app liga o modo de reforço.
class _EyeQualityBanner extends StatelessWidget {
  const _EyeQualityBanner({required this.low, required this.usesProb});
  final bool low;
  final bool usesProb;

  @override
  Widget build(BuildContext context) {
    final color = low ? AppColors.yellow : AppColors.green;
    return Container(
      key: const Key('eye-quality'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(low ? Icons.visibility_off_outlined : Icons.check_circle_outline, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(low ? 'Olhos pouco visíveis nesta posição' : 'Olhos bem visíveis nesta posição',
                style: AppText.cardTitle.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(
              low
                  ? 'O app vai reforçar a detecção: a inclinação da cabeça fica mais sensível'
                      '${usesProb ? ' e o olho fechado passa a ser medido também pela probabilidade do ML Kit' : ''}. '
                      'A boca continua sendo analisada normalmente. Se puder, coloque o celular mais alto '
                      'ou mais à frente do rosto.'
                  : 'A diferença entre olho aberto e fechado ficou clara. Detecção normal.',
              style: AppText.body.copyWith(fontSize: 12),
            ),
          ]),
        ),
      ]),
    );
  }
}
