import 'package:fatigue_guard/screens/calibration_screen.dart';
import 'package:fatigue_guard/screens/explanation_screen.dart';
import 'package:fatigue_guard/screens/guided_test_screen.dart';
import 'package:fatigue_guard/screens/home_screen.dart';
import 'package:fatigue_guard/screens/settings_screen.dart';
import 'package:fatigue_guard/theme.dart';
import 'package:fatigue_guard/vision/vision_controller.dart';
import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:fatigue_guard/vision/guided_test.dart';
import 'package:fatigue_guard/widgets/alert_progress.dart';
import 'package:fatigue_guard/widgets/floating_view.dart';
import 'package:fatigue_guard/widgets/light_mode_selector.dart';
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

  testWidgets('janela flutuante mostra o status de forma compacta', (tester) async {
    final vision = VisionController();
    await tester.binding.setSurfaceSize(const Size(200, 200)); // janela ampliada pelo usuário
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: FloatingView(vision: vision)));
    // Câmera desligada nos testes: não está monitorando.
    expect(find.text('PAUSADO'), findsOneWidget);
    expect(find.text('Abra o app para monitorar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Tamanho mínimo (~108 dp): só ícone e palavra.
    await tester.binding.setSurfaceSize(const Size(108, 108));
    await tester.pump();
    expect(find.text('PAUSADO'), findsOneWidget);
    expect(find.text('Abra o app para monitorar'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox());
    vision.dispose();
  });

  testWidgets('botão Dia / Noite / Automático troca o modo com um toque', (tester) async {
    final vision = VisionController();
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: Scaffold(body: LightModeSelector(vision: vision, compact: true))));
    expect(find.text('Dia'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('Noite'));
    await tester.pump();
    expect(vision.settings.lightMode, LightMode.night);
    expect(vision.nightActive, isTrue);
    await tester.tap(find.text('Dia'));
    await tester.pump();
    expect(vision.settings.lightMode, LightMode.day);
    await tester.pumpWidget(const SizedBox());
    vision.dispose();
  });

  testWidgets('"A caminho do alerta" mostra uma barra por regra com o limite', (tester) async {
    final vision = VisionController();
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: AlertProgressPanel(vision: vision)))));
    expect(find.text('A CAMINHO DO ALERTA'), findsOneWidget);
    for (final k in ['bar-olhos', 'bar-bocejo', 'bar-cabeca', 'bar-rosto']) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.text('0,0 / 1,2 s'), findsOneWidget); // olhos: limite padrão 1,2 s
    // Sem a regra da cabeça, a barra some.
    vision.settings.headEnabled = false;
    vision.saveSettings();
    await tester.pump();
    expect(find.byKey(const Key('bar-cabeca')), findsNothing);
    expect(tester.takeException(), isNull);
    vision.dispose();
  });

  testWidgets('teste guiado abre com explicação, tamanho e aviso de calibração', (tester) async {
    final vision = VisionController();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: GuidedTestScreen(vision: vision)));
    expect(find.text('Teste guiado'), findsOneWidget);
    expect(find.byKey(const Key('guided-needs-calibration')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('guided-size')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Rápido\n12 testes'), findsOneWidget);
    expect(find.text('Completo\n40 testes'), findsOneWidget);
    await tester.ensureVisible(find.text('Completo\n40 testes'));
    await tester.pump();
    await tester.tap(find.text('Completo\n40 testes'));
    await tester.pump();
    expect(find.textContaining('40 tentativas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    vision.dispose();
  });

  testWidgets('teste guiado: resultado mostra a matriz de confusão', (tester) async {
    final vision = VisionController();
    GuidedTrialResult r(String id, bool alert, [int? ms]) => GuidedTrialResult(
        behavior: guidedBehaviors.firstWhere((b) => b.id == id),
        repetition: 1,
        gotAlert: alert,
        gotAttention: false,
        timeToAlertMs: ms);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: GuidedTestScreen(
            vision: vision, initialResults: [r('olhos', true, 1500), r('bocejo', false), r('falar', false), r('piscar', true)])));
    expect(find.byKey(const Key('guided-summary')), findsOneWidget);
    expect(find.text('50%'), findsOneWidget); // sensibilidade: 1 de 2
    expect(find.text('1,5 s'), findsOneWidget); // tempo médio (olhos)
    for (final code in ['VP', 'FN', 'FP', 'VN']) {
      expect(find.text(code), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    vision.dispose();
  });
}
