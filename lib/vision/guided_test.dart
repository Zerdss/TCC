import 'fatigue_engine.dart';

// ---------------------------------------------------------------------------
// Teste guiado: o próprio app executa o protocolo de validação do TCC
// (Tabela 3 — comportamentos encenados e respostas esperadas). Uma voz pede
// cada comportamento, o app observa o status e anota se acertou, medindo o
// tempo até o alerta. No fim, calcula a matriz de confusão e as medidas.
// ---------------------------------------------------------------------------

/// Um comportamento do roteiro.
class GuidedBehavior {
  const GuidedBehavior({
    required this.id,
    required this.label,
    required this.instruction,
    required this.expectAlert,
    required this.windowMs,
    this.backToNormal = 'Pode voltar ao normal e olhar para a câmera.',
  });

  final String id;

  /// Nome curto (tela e resumo).
  final String label;

  /// O que a voz diz para a pessoa fazer.
  final String instruction;

  /// Resposta esperada: ALERTA (sinal de sono) ou nenhum alerta (normal).
  final bool expectAlert;

  /// Tempo de observação depois da instrução.
  final int windowMs;

  final String backToNormal;
}

/// Roteiro baseado na Tabela 3 do TCC.
const guidedBehaviors = [
  GuidedBehavior(
    id: 'piscar',
    label: 'Piscar normalmente',
    instruction: 'Olhe para a câmera e pisque normalmente.',
    expectAlert: false,
    windowMs: 5000,
  ),
  GuidedBehavior(
    id: 'falar',
    label: 'Falar e sorrir',
    instruction: 'Fale uma frase qualquer e sorria.',
    expectAlert: false,
    windowMs: 5000,
  ),
  GuidedBehavior(
    id: 'olhos',
    label: 'Fechar os olhos',
    instruction: 'Feche os olhos agora e mantenha fechados até ouvir o alarme.',
    expectAlert: true,
    windowMs: 5000,
    backToNormal: 'Pode abrir os olhos.',
  ),
  GuidedBehavior(
    id: 'bocejo',
    label: 'Bocejar',
    instruction: 'Abra bem a boca, como num bocejo, e segure.',
    expectAlert: true,
    windowMs: 6000,
    backToNormal: 'Pode fechar a boca.',
  ),
  GuidedBehavior(
    id: 'cabeca',
    label: 'Cochilo com a cabeça caindo',
    instruction: 'Feche os olhos e deixe a cabeça cair para a frente, como num cochilo.',
    expectAlert: true,
    windowMs: 6000,
    backToNormal: 'Pode levantar a cabeça e abrir os olhos.',
  ),
  GuidedBehavior(
    id: 'rosto',
    label: 'Sair do enquadramento',
    instruction: 'Saia da frente da câmera.',
    expectAlert: true,
    windowMs: 8000,
    backToNormal: 'Pode voltar para a frente da câmera.',
  ),
];

/// Tamanho do teste.
enum GuidedSize { quick, full }

extension GuidedSizeInfo on GuidedSize {
  String get label => this == GuidedSize.quick ? 'Rápido' : 'Completo';

  /// Repetições de cada comportamento.
  int repsFor(GuidedBehavior b) => this == GuidedSize.quick ? 2 : (b.expectAlert ? 5 : 10);
}

/// Monta a sequência de tentativas (cada comportamento repetido seguido).
List<GuidedBehavior> guidedPlan(GuidedSize size) => [
      for (final b in guidedBehaviors)
        for (var i = 0; i < size.repsFor(b); i++) b,
    ];

/// Resultado de uma tentativa.
class GuidedTrialResult {
  const GuidedTrialResult({
    required this.behavior,
    required this.repetition,
    required this.gotAlert,
    required this.gotAttention,
    this.timeToAlertMs,
  });

  final GuidedBehavior behavior;
  final int repetition;
  final bool gotAlert;
  final bool gotAttention;

  /// Do fim da instrução até o primeiro ALERTA (inclui a reação da pessoa).
  final int? timeToAlertMs;

  bool get correct => behavior.expectAlert ? gotAlert : !gotAlert;

  /// VP, FN, FP ou VN (positivo = o app deu ALERTA).
  String get matrix => behavior.expectAlert ? (gotAlert ? 'VP' : 'FN') : (gotAlert ? 'FP' : 'VN');
}

/// Observa o status durante a janela de uma tentativa.
class GuidedTrial {
  GuidedTrial(this.behavior, this.repetition, this.startMs);

  final GuidedBehavior behavior;
  final int repetition;
  final int startMs;
  bool gotAlert = false, gotAttention = false;
  int? timeToAlertMs;

  /// Atualiza com o status atual. Retorna `true` quando a tentativa acabou.
  bool observe(int now, FatigueStatus status) {
    if (status == FatigueStatus.attention) gotAttention = true;
    if (status == FatigueStatus.alert && !gotAlert) {
      gotAlert = true;
      timeToAlertMs = now - startMs;
      // Sinal de sono detectado: não precisa esperar o resto da janela.
      if (behavior.expectAlert) return true;
    }
    return now - startMs >= behavior.windowMs;
  }

  GuidedTrialResult get result => GuidedTrialResult(
        behavior: behavior,
        repetition: repetition,
        gotAlert: gotAlert,
        gotAttention: gotAttention,
        timeToAlertMs: timeToAlertMs,
      );
}

/// Acertos de um comportamento.
class GuidedRow {
  const GuidedRow(this.behavior, this.correct, this.total, this.avgTimeMs);
  final GuidedBehavior behavior;
  final int correct, total;
  final double? avgTimeMs;
}

/// Matriz de confusão e medidas do plano de validação.
class GuidedSummary {
  GuidedSummary(this.results);
  final List<GuidedTrialResult> results;

  int _count(String code) => results.where((r) => r.matrix == code).length;
  int get vp => _count('VP');
  int get fn => _count('FN');
  int get fp => _count('FP');
  int get vn => _count('VN');
  int get total => results.length;

  double? _ratio(int a, int b) => b == 0 ? null : a / b;
  double? get sensitivity => _ratio(vp, vp + fn);
  double? get specificity => _ratio(vn, vn + fp);
  double? get precision => _ratio(vp, vp + fp);
  double? get accuracy => _ratio(vp + vn, total);
  double? get falseAlarmRate => _ratio(fp, fp + vn);

  /// Avisos de ATENÇÃO em comportamentos normais (não são alarmes).
  int get attentionOnNormal => results.where((r) => !r.behavior.expectAlert && !r.gotAlert && r.gotAttention).length;

  List<GuidedRow> get rows => [
        for (final b in guidedBehaviors)
          if (results.any((r) => r.behavior.id == b.id))
            () {
              final rs = results.where((r) => r.behavior.id == b.id).toList();
              final times = [for (final r in rs) if (r.timeToAlertMs != null && b.expectAlert) r.timeToAlertMs!];
              return GuidedRow(b, rs.where((r) => r.correct).length, rs.length,
                  times.isEmpty ? null : times.reduce((a, c) => a + c) / times.length);
            }(),
      ];

  /// CSV no mesmo padrão do relatório do app (separador ;, vírgula decimal).
  String toCsv({DateTime? at, String person = ''}) {
    String n(double? v, [int d = 1]) => v == null ? '' : v.toStringAsFixed(d).replaceAll('.', ',');
    String pct(double? v) => v == null ? '-' : '${(v * 100).round()}%';
    final b = StringBuffer()
      ..writeln('FATIGUE GUARD - TESTE GUIADO (protocolo de validação, Tabela 3)')
      ..writeln('Data;${at == null ? '' : '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}/${at.year}'}')
      ..writeln('Pessoa;$person')
      ..writeln()
      ..writeln('Nº;Comportamento;Repetição;Esperado;Deu alerta?;Deu atenção?;Tempo até o alerta (s);Matriz;Acertou?');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      b.writeln([
        i + 1,
        r.behavior.label,
        r.repetition,
        r.behavior.expectAlert ? 'Alerta' : 'Nenhum alerta',
        r.gotAlert ? 'Sim' : 'Não',
        r.gotAttention ? 'Sim' : 'Não',
        r.timeToAlertMs == null ? '' : n(r.timeToAlertMs! / 1000),
        r.matrix,
        r.correct ? 'Sim' : 'Não',
      ].join(';'));
    }
    b
      ..writeln()
      ..writeln('RESUMO')
      ..writeln('VP;$vp')
      ..writeln('FN;$fn')
      ..writeln('FP;$fp')
      ..writeln('VN;$vn')
      ..writeln('Sensibilidade;${pct(sensitivity)}')
      ..writeln('Especificidade;${pct(specificity)}')
      ..writeln('Precisão;${pct(precision)}')
      ..writeln('Acurácia;${pct(accuracy)}')
      ..writeln('Taxa de falsos alarmes;${pct(falseAlarmRate)}')
      ..writeln('Avisos de atenção em comportamento normal;$attentionOnNormal')
      ..writeln()
      ..writeln('Tempo até o alerta inclui o tempo de reação da pessoa à instrução.');
    return b.toString();
  }
}
