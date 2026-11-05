import 'package:flutter/material.dart';

import '../theme.dart';
import '../vision/vision_controller.dart';
import '../widgets/camera_panel.dart';
import '../widgets/common.dart';
import 'demo_screen.dart';

const _labels = ['OLHOS ABERTOS', 'OLHOS FECHADOS', 'BOCEJO DE TESTE', 'SORRISO / RISADA (OPCIONAL)'];
const _instructions = [
  'Mantenha o olhar natural e os olhos abertos por alguns segundos.',
  'Agora feche os olhos suavemente. O sistema está aprendendo seu limiar pessoal.',
  'Abra a boca como em um bocejo lento e sustentado para registrar seu padrão de MAR.',
  'Sorria e ria naturalmente por alguns segundos. Isso ensina o sistema a não confundir '
      'expressões normais com fadiga.',
];

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.vision});

  final VisionController vision;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  int step = 0;
  bool _leavingToDemo = false;

  VisionController get vision => widget.vision;

  @override
  void initState() {
    super.initState();
    vision.beginCalibration(0);
    vision.start();
  }

  @override
  void dispose() {
    // Voltar para a tela inicial desliga a câmera.
    if (!_leavingToDemo) vision.stop();
    super.dispose();
  }

  void _next() {
    if (step < 3) {
      setState(() => step++);
      vision.beginCalibration(step);
    } else {
      _openDemo();
    }
  }

  void _openDemo() {
    _leavingToDemo = true;
    vision.saveCalibration();
    vision.beginMonitoring();
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DemoScreen(vision: vision)));
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      children: [
        const Text('ETAPA 02 / 04', style: AppText.kicker),
        const SizedBox(height: 8),
        const Text('Calibração pessoal', style: AppText.h2),
        const SizedBox(height: 9),
        const Text(
          'Vamos ajustar os limiares para suas características faciais. Use a pré-visualização abaixo '
          'para se posicionar no centro do quadro.',
          style: AppText.body,
        ),
        const SizedBox(height: 20),
        CameraPanel(vision: vision),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: vision,
          builder: (context, _) {
            final progress = vision.calibrationProgress;
            final done = progress >= 100;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(
                        text: '0${step + 1} ',
                        style: const TextStyle(
                            color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1),
                        children: const [TextSpan(text: '/ 04', style: TextStyle(color: AppColors.muted))],
                      )),
                      const SizedBox(height: 7),
                      Text(_labels[step],
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 7),
                      Text(_instructions[step], style: AppText.body),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          minHeight: 7,
                          backgroundColor: AppColors.panel2,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        done
                            ? 'Padrão registrado com sucesso'
                            : vision.state == EngineState.running
                                ? 'Analisando padrão facial... $progress%'
                                : 'Aguardando câmera...',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                      if (vision.state == EngineState.running) ...[
                        const SizedBox(height: 4),
                        Text(
                          'EAR ${vision.metrics.ear.toStringAsFixed(3)} • MAR ${vision.metrics.mar.toStringAsFixed(3)}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  key: const Key('button-proxima'),
                  label: done ? (step == 3 ? 'Abrir painel ao vivo' : 'Próxima etapa') : 'Aguardando leitura...',
                  icon: done ? Icons.arrow_forward : Icons.center_focus_weak,
                  onPressed: done ? _next : null,
                ),
                if (step == 3)
                  TextButton(
                    onPressed: _openDemo,
                    child: const Text('Pular etapa opcional',
                        style: TextStyle(
                            color: AppColors.muted, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
