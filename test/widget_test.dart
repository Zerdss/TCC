import 'package:fatigue_guard/screens/calibration_screen.dart';
import 'package:fatigue_guard/screens/explanation_screen.dart';
import 'package:fatigue_guard/screens/home_screen.dart';
import 'package:fatigue_guard/screens/settings_screen.dart';
import 'package:fatigue_guard/theme.dart';
import 'package:fatigue_guard/vision/vision_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tela inicial mostra título, privacidade e botão de início', (tester) async {
    final vision = VisionController();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeScreen(vision: vision)));
    expect(find.text('Detecção de\nSonolência ao Volante'), findsOneWidget);
    expect(find.byKey(const Key('button-iniciar')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Processamento 100% local'), 200);
    expect(find.text('Processamento 100% local'), findsOneWidget);
    vision.dispose();
  });

  testWidgets('tela explicativa lista as 4 etapas do pipeline', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const ExplanationScreen()));
    for (final title in ['Captura de imagem', 'Detecção facial', 'Métricas', 'Classificação e alerta']) {
      await tester.scrollUntilVisible(find.text(title), 200);
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('configurações alteram o filtro de sorriso e o tempo do alerta', (tester) async {
    final vision = VisionController();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: SettingsScreen(vision: vision)));
    await tester.scrollUntilVisible(find.text('Ignorar sorriso e fala'), 200);
    expect(vision.settings.smileFilter, isTrue);
    await tester.tap(find.text('Ignorar sorriso e fala'));
    await tester.pump();
    expect(vision.settings.smileFilter, isFalse);
    await tester.scrollUntilVisible(find.text('Olhos fechados para alertar'), 200);
    expect(find.text('1,2 s'), findsOneWidget);
    vision.dispose();
  });

  testWidgets('sair de "Recalibrar só o sorriso" devolve o painel ao monitoramento', (tester) async {
    final vision = VisionController();
    expect(vision.calibrationStep, isNull); // painel monitorando
    await tester.pumpWidget(
        MaterialApp(theme: buildTheme(), home: CalibrationScreen(vision: vision, onlyStep: 3)));
    expect(vision.calibrationStep, 3);
    // Fecha a tela de calibração (como o botão voltar).
    await tester.pumpWidget(const SizedBox());
    expect(vision.calibrationStep, isNull);
    vision.dispose();
  });
}
