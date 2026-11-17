import 'package:fatigue_guard/vision/fatigue_engine.dart';
import 'package:fatigue_guard/vision/guided_test.dart';
import 'package:flutter_test/flutter_test.dart';

GuidedBehavior _b(String id) => guidedBehaviors.firstWhere((b) => b.id == id);

GuidedTrialResult _run(String id, List<(int, FatigueStatus)> frames) {
  final t = GuidedTrial(_b(id), 1, 1000);
  for (final (now, s) in frames) {
    if (t.observe(now, s)) break;
  }
  return t.result;
}

void main() {
  test('roteiro segue a Tabela 3: normais sem alerta, sinais de sono com alerta', () {
    expect(guidedBehaviors.where((b) => !b.expectAlert).map((b) => b.id), ['piscar', 'falar']);
    expect(guidedBehaviors.where((b) => b.expectAlert).map((b) => b.id), ['olhos', 'bocejo', 'cabeca', 'rosto']);
    expect(guidedPlan(GuidedSize.quick).length, 12);
    expect(guidedPlan(GuidedSize.full).length, 40); // 2×10 normais + 4×5 sinais de sono
  });

  test('sinal de sono: termina no primeiro ALERTA e mede o tempo', () {
    final t = GuidedTrial(_b('olhos'), 1, 1000);
    expect(t.observe(1500, FatigueStatus.attention), isFalse);
    expect(t.observe(2400, FatigueStatus.alert), isTrue);
    final r = t.result;
    expect(r.gotAlert, isTrue);
    expect(r.gotAttention, isTrue);
    expect(r.timeToAlertMs, 1400);
    expect(r.matrix, 'VP');
    expect(r.correct, isTrue);
  });

  test('sinal de sono sem alerta até o fim da janela vira FN', () {
    final r = _run('bocejo', [(2000, FatigueStatus.normal), (7000, FatigueStatus.attention)]);
    expect(r.gotAlert, isFalse);
    expect(r.matrix, 'FN');
    expect(r.correct, isFalse);
  });

  test('comportamento normal: ATENÇÃO não é erro, ALERTA é alarme falso', () {
    final ok = _run('falar', [(2000, FatigueStatus.attention), (6000, FatigueStatus.normal)]);
    expect(ok.matrix, 'VN');
    expect(ok.correct, isTrue);
    expect(ok.gotAttention, isTrue);
    // No normal, o ALERTA não encerra a tentativa antes da janela.
    final t = GuidedTrial(_b('piscar'), 1, 1000);
    expect(t.observe(2000, FatigueStatus.alert), isFalse);
    expect(t.observe(6000, FatigueStatus.normal), isTrue);
    expect(t.result.matrix, 'FP');
  });

  test('resumo calcula matriz de confusão e medidas', () {
    final results = [
      _run('olhos', [(1050, FatigueStatus.normal), (2200, FatigueStatus.alert)]),
      _run('olhos', [(1050, FatigueStatus.normal), (2600, FatigueStatus.alert)]),
      _run('bocejo', [(7000, FatigueStatus.normal)]), // FN
      _run('piscar', [(6000, FatigueStatus.normal)]), // VN
      _run('falar', [(2000, FatigueStatus.alert), (6000, FatigueStatus.normal)]), // FP
      _run('falar', [(2000, FatigueStatus.attention), (6000, FatigueStatus.normal)]), // VN com atenção
    ];
    final s = GuidedSummary(results);
    expect([s.vp, s.fn, s.fp, s.vn], [2, 1, 1, 2]);
    expect(s.sensitivity, closeTo(2 / 3, 1e-9));
    expect(s.specificity, closeTo(2 / 3, 1e-9));
    expect(s.precision, closeTo(2 / 3, 1e-9));
    expect(s.accuracy, closeTo(4 / 6, 1e-9));
    expect(s.falseAlarmRate, closeTo(1 / 3, 1e-9));
    expect(s.attentionOnNormal, 1);
    final olhos = s.rows.firstWhere((r) => r.behavior.id == 'olhos');
    expect(olhos.correct, 2);
    expect(olhos.total, 2);
    expect(olhos.avgTimeMs, 1400);
    expect(s.rows.map((r) => r.behavior.id), ['piscar', 'falar', 'olhos', 'bocejo']);

    final csv = s.toCsv(at: DateTime(2026, 11, 13), person: 'Teste');
    expect(csv, contains('Data;13/11/2026'));
    expect(csv, contains('Pessoa;Teste'));
    expect(csv, contains('1;Fechar os olhos;1;Alerta;Sim;Não;1,2;Não;;VP;Sim'));
    expect(csv, contains('Sensibilidade;67%'));
    expect(csv, contains('VN;2'));
  });

  test('resumo vazio não divide por zero', () {
    final s = GuidedSummary(const []);
    expect(s.sensitivity, isNull);
    expect(s.accuracy, isNull);
    expect(s.toCsv(), contains('Sensibilidade;-'));
  });

  test('começou antes do sinal: acerto vale, mas o tempo fica fora da média', () {
    // Alerta já ativo na primeira leitura (a pessoa fechou os olhos durante a fala).
    final early = GuidedTrial(_b('olhos'), 1, 1000);
    expect(early.observe(1050, FatigueStatus.alert), isTrue);
    expect(early.result.correct, isTrue);
    expect(early.result.early, isTrue);
    expect(early.result.timeToAlertMs, isNull);
    final ok = _run('olhos', [(1050, FatigueStatus.normal), (2500, FatigueStatus.alert)]);
    expect(ok.early, isFalse);
    expect(ok.timeToAlertMs, 1500);
    final s = GuidedSummary([early.result, ok]);
    expect(s.sensitivity, 1.0);
    expect(s.earlyStarts, 1);
    expect(s.rows.single.avgTimeMs, 1500); // só a tentativa válida
    expect(s.toCsv(), contains('Começou antes do sinal (fora do tempo médio);1'));
  });

  test('a voz pede para esperar o sinal em todas as instruções', () {
    for (final b in guidedBehaviors) {
      expect(b.instruction, startsWith('Quando ouvir o sinal'), reason: b.id);
    }
  });

  test('registra o motivo do alerta e resume os motivos dos alarmes falsos', () {
    final fp = GuidedTrial(_b('piscar'), 1, 1000);
    fp.observe(1050, FatigueStatus.normal);
    fp.observe(2000, FatigueStatus.alert, reason: AlertReason.eyes);
    fp.observe(6000, FatigueStatus.normal);
    expect(fp.result.matrix, 'FP');
    expect(fp.result.alertReason, AlertReason.eyes);
    final s = GuidedSummary([fp.result]);
    expect(s.falseAlarmReasons, {'olhos fechados': 1});
    final csv = s.toCsv();
    expect(csv, contains(';olhos fechados;FP;Não'));
    expect(csv, contains('Motivos dos alarmes falsos;olhos fechados (1)'));
  });
}
