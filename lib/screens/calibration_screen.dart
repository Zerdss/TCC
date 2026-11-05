import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/vision_controller.dart';
import '../widgets/camera_panel.dart';
import '../widgets/common.dart';
import 'demo_screen.dart';

class _Step {
  const _Step(this.label, this.icon, this.instruction, this.tip);
  final String label;
  final IconData icon;
  final String instruction;
  final String tip;
}

const _steps = [
  _Step('OLHOS ABERTOS', Icons.visibility_outlined,
      'Mantenha o olhar natural e os olhos abertos por alguns segundos.',
      'Olhe para a câmera como se estivesse olhando para a estrada.'),
  _Step('OLHOS FECHADOS', Icons.visibility_off_outlined,
      'Agora feche os olhos suavemente. O sistema está aprendendo seu limiar pessoal.',
      'Mantenha o rosto parado; a barra avança sozinha.'),
  _Step('BOCEJO DE TESTE', Icons.record_voice_over_outlined,
      'Abra a boca como em um bocejo lento e sustentado para registrar seu padrão de MAR.',
      'Segure a boca bem aberta até a barra completar.'),
  _Step('SORRISO / RISADA', Icons.sentiment_very_satisfied_outlined,
      'Sorria e ria naturalmente por alguns segundos. Isso ensina o sistema a não confundir '
          'expressões normais com fadiga.',
      'Etapa opcional — pode pular se preferir.'),
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
  late final bool _wasMonitoring = vision.isMonitoring;

  VisionController get vision => widget.vision;
  bool get _single => widget.onlyStep != null;

  @override
  void initState() {
    super.initState();
    vision.beginCalibration(step);
    vision.acquireCamera();
  }

  @override
  void dispose() {
    // Se abriu por cima do painel ao vivo, devolve o painel ao monitoramento.
    if (_wasMonitoring && !_leavingToDemo) vision.beginMonitoring();
    vision.releaseCamera();
    super.dispose();
  }

  void _next() {
    if (_single) {
      _finishSingle();
    } else if (step < 3) {
      setState(() => step++);
      vision.beginCalibration(step);
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
    _leavingToDemo = true;
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
        CameraPanel(vision: vision),
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
                            border: Border.all(color: done ? AppColors.green : AppColors.amber),
                          ),
                          child: Icon(done ? Icons.check_rounded : info.icon,
                              color: done ? AppColors.green : AppColors.amber),
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
                        const Icon(Icons.lightbulb_outline, size: 14, color: AppColors.amberSoft),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(info.tip,
                              style: const TextStyle(color: AppColors.amberSoft, fontSize: 12)),
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
                                color: done ? AppColors.green : AppColors.amber,
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
                            ? 'Padrão registrado com sucesso'
                            : running
                                ? 'Analisando padrão facial...'
                                : 'Aguardando câmera...',
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
                const SizedBox(height: 18),
                PrimaryButton(
                  key: const Key('button-proxima'),
                  label: done
                      ? (_single ? 'Salvar e voltar' : step == 3 ? 'Abrir painel ao vivo' : 'Próxima etapa')
                      : 'Aguardando leitura...',
                  icon: done ? Icons.arrow_forward : Icons.center_focus_weak,
                  onPressed: done ? _next : null,
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
                          ? AppColors.amber
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
                          ? AppColors.amber
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
