import 'package:fatigue_guard/screens/explanation_screen.dart';
import 'package:fatigue_guard/screens/home_screen.dart';
import 'package:fatigue_guard/theme.dart';
import 'package:fatigue_guard/vision/vision_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tela inicial mostra título, privacidade e botão de início', (tester) async {
    final vision = VisionController();
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeScreen(vision: vision)));
    expect(find.text('Detecção de\nSonolência ao Volante'), findsOneWidget);
    expect(find.text('Processamento 100% local'), findsOneWidget);
    expect(find.byKey(const Key('button-iniciar')), findsOneWidget);
    vision.dispose();
  });

  testWidgets('tela explicativa lista as 4 etapas do pipeline', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const ExplanationScreen()));
    for (final title in ['Captura de imagem', 'Detecção facial', 'Métricas', 'Classificação e alerta']) {
      await tester.scrollUntilVisible(find.text(title), 200);
      expect(find.text(title), findsOneWidget);
    }
  });
}
