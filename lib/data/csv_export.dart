import 'models.dart';

// ---------------------------------------------------------------------------
// Exportação em CSV pronta para abrir no Excel / Planilhas Google em português:
// separador `;`, vírgula decimal, datas dd/mm/aaaa, cabeçalhos legíveis e
// sessões em ordem cronológica, com uma linha de TOTAL no fim.
// ---------------------------------------------------------------------------

const _sep = ';';

String _two(int v) => v.toString().padLeft(2, '0');

/// 11/11/2026
String csvDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// 17:05:09
String csvTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

/// Duração como hh:mm:ss (ex.: 00:12:05).
String csvDuration(Duration d) {
  final s = d.inSeconds.abs();
  return '${_two(s ~/ 3600)}:${_two(s % 3600 ~/ 60)}:${_two(s % 60)}';
}

/// Número com vírgula decimal (padrão brasileiro).
String csvNum(double v, int digits) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Escapa um campo que tenha `;`, aspas ou quebra de linha.
String csvField(Object? v) {
  final s = '${v ?? ''}';
  if (s.contains(_sep) || s.contains('"') || s.contains('\n')) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _row(List<Object?> cells) => cells.map(csvField).join(_sep);

/// Nome legível do tipo de evento para a planilha.
String eventTypeName(EventType t) => switch (t) {
      EventType.eyes => 'ALERTA - olhos fechados',
      EventType.yawn => 'ALERTA - bocejo',
      EventType.head => 'ALERTA - cabeça caindo',
      EventType.faceLost => 'ALERTA - rosto fora da câmera',
      EventType.attention => 'Atenção',
    };

const sessionsCsvHeader = [
  'Sessão',
  'Data',
  'Início',
  'Fim',
  'Duração',
  'Total de alertas',
  'Alertas: olhos fechados',
  'Alertas: bocejo',
  'Alertas: cabeça caindo',
  'Alertas: rosto fora da câmera',
  'Avisos de atenção',
  'PERCLOS máximo (%)',
  'Piscadas por minuto (média)',
  'Limiar EAR (olhos)',
  'Limiar MAR (boca)',
  'Calibração pessoal',
];

/// Sessões em ordem cronológica, numeradas de 1 em diante.
List<SessionRecord> _chronological(List<SessionRecord> sessions) =>
    [...sessions]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

/// CSV com uma linha por sessão e uma linha de TOTAL no fim.
String sessionsToCsv(List<SessionRecord> sessions) {
  final list = _chronological(sessions);
  final b = StringBuffer()..writeln(_row(sessionsCsvHeader));
  var n = 0;
  for (final s in list) {
    n++;
    b.writeln(_row([
      n,
      csvDate(s.startedAt),
      csvTime(s.startedAt),
      csvTime(s.endedAt),
      csvDuration(s.duration),
      s.totalAlerts,
      s.alertsEyes,
      s.alertsYawn,
      s.alertsHead,
      s.alertsFace,
      s.attentionCount,
      csvNum(s.maxPerclos * 100, 1),
      csvNum(s.avgBlinkRate, 1),
      csvNum(s.earThreshold, 3),
      csvNum(s.marThreshold, 3),
      s.calibrated ? 'Sim' : 'Não',
    ]));
  }
  if (list.isNotEmpty) {
    int sum(int Function(SessionRecord) f) => list.fold(0, (a, s) => a + f(s));
    final total = list.fold(Duration.zero, (a, s) => a + s.duration);
    final maxPerclos = list.map((s) => s.maxPerclos).reduce((a, b) => a > b ? a : b);
    final blink = list.fold(0.0, (a, s) => a + s.avgBlinkRate) / list.length;
    b.writeln(_row([
      'TOTAL',
      '${list.length} ${list.length == 1 ? 'sessão' : 'sessões'}',
      '',
      '',
      csvDuration(total),
      sum((s) => s.totalAlerts),
      sum((s) => s.alertsEyes),
      sum((s) => s.alertsYawn),
      sum((s) => s.alertsHead),
      sum((s) => s.alertsFace),
      sum((s) => s.attentionCount),
      csvNum(maxPerclos * 100, 1),
      csvNum(blink, 1),
      '',
      '',
      '',
    ]));
  }
  return b.toString();
}

const eventsCsvHeader = [
  'Sessão',
  'Data',
  'Horário',
  'Tempo na sessão',
  'Tipo',
  'EAR (olhos)',
  'MAR (boca)',
  'PERCLOS (%)',
];

/// CSV com uma linha por evento (alerta/atenção), na ordem em que aconteceram.
/// Com [sessions], mostra o número da sessão (o mesmo do outro arquivo) e o
/// tempo decorrido desde o início dela.
String eventsToCsv(List<SessionEvent> events, {List<SessionRecord> sessions = const []}) {
  final list = _chronological(sessions);
  final number = <int, int>{};
  final start = <int, DateTime>{};
  for (var i = 0; i < list.length; i++) {
    final id = list[i].id;
    if (id != null) {
      number[id] = i + 1;
      start[id] = list[i].startedAt;
    }
  }
  final sorted = [...events]..sort((a, b) => a.time.compareTo(b.time));
  final b = StringBuffer()..writeln(_row(eventsCsvHeader));
  for (final e in sorted) {
    final sid = e.sessionId;
    final began = sid == null ? null : start[sid];
    b.writeln(_row([
      sid == null ? '' : (number[sid] ?? sid),
      csvDate(e.time),
      csvTime(e.time),
      began == null ? '' : csvDuration(e.time.difference(began)),
      eventTypeName(e.type),
      csvNum(e.ear, 3),
      csvNum(e.mar, 3),
      csvNum(e.perclos * 100, 1),
    ]));
  }
  return b.toString();
}

/// Explicação de cada coluna, no fim do relatório.
const reportLegend = [
  ['Sessão', 'Número da sessão de monitoramento (1 = a mais antiga). É o mesmo número nas duas tabelas.'],
  ['Duração', 'Tempo da sessão em horas:minutos:segundos.'],
  ['Total de alertas', 'Soma dos alertas de sonolência da sessão (olhos, bocejo, cabeça e rosto).'],
  ['Alertas: olhos fechados', 'Olhos fechados de forma contínua por 1,2 s ou mais (piscadas normais não contam).'],
  ['Alertas: bocejo', 'Boca bem aberta de forma contínua por 1,8 s ou mais.'],
  ['Alertas: cabeça caindo', 'Cabeça baixa ou tombada para o lado (cochilo) com os olhos fechados.'],
  ['Alertas: rosto fora da câmera', 'O rosto sumiu da câmera por 4 s ou mais.'],
  ['Avisos de atenção', 'Sinais leves, antes do alerta (ex.: olhando para baixo ou para o lado por mais de 2,5 s).'],
  ['PERCLOS (%)', 'Porcentagem do último minuto com os olhos fechados. Quanto maior, mais cansaço.'],
  ['Piscadas por minuto', 'Média de piscadas. Muitas piscadas também indicam cansaço.'],
  ['EAR (olhos)', 'Abertura dos olhos medida pela câmera: quanto menor, mais fechados.'],
  ['MAR (boca)', 'Abertura da boca medida pela câmera: quanto maior, mais aberta.'],
  ['Limiar EAR / Limiar MAR', 'Limites usados para o motorista: olho abaixo do limiar = fechado, boca acima do limiar = bocejo.'],
  ['Calibração pessoal', 'Sim = limites medidos na calibração do motorista. Não = valores padrão do app.'],
  ['Tempo na sessão', 'Quanto tempo depois do início da sessão o alerta aconteceu.'],
];

/// Relatório completo num único arquivo, separado em seções (resumo, sessões,
/// alertas e legenda) com linhas em branco entre elas, para abrir no Excel ou
/// nas Planilhas Google.
String reportToCsv(List<SessionRecord> sessions, List<SessionEvent> events, {DateTime? generatedAt}) {
  final now = generatedAt ?? DateTime.now();
  final list = _chronological(sessions);
  final total = list.fold(Duration.zero, (a, s) => a + s.duration);
  final alerts = list.fold(0, (a, s) => a + s.totalAlerts);
  final attention = list.fold(0, (a, s) => a + s.attentionCount);
  final b = StringBuffer()
    ..writeln(_row(['FATIGUE GUARD - RELATÓRIO DE MONITORAMENTO']))
    ..writeln(_row(['Protótipo de detecção de sonolência em motoristas (TCC)']))
    ..writeln()
    ..writeln(_row(['Gerado em', '${csvDate(now)} ${csvTime(now)}']))
    ..writeln(_row(['Sessões', list.length]))
    ..writeln(_row(['Tempo total monitorado', csvDuration(total)]))
    ..writeln(_row(['Total de alertas', alerts]))
    ..writeln(_row(['Avisos de atenção', attention]))
    ..writeln()
    ..writeln()
    ..writeln(_row(['1. RESUMO DAS SESSÕES']))
    ..writeln(_row(['Uma linha por sessão de monitoramento, da mais antiga para a mais recente. '
        'A última linha (TOTAL) soma todas as sessões.']))
    ..writeln()
    ..write(list.isEmpty ? '${_row(['Nenhuma sessão registrada.'])}\n' : sessionsToCsv(list))
    ..writeln()
    ..writeln()
    ..writeln(_row(['2. ALERTAS E AVISOS']))
    ..writeln(_row(['Cada alerta de sonolência ou aviso de atenção, na ordem em que aconteceu. '
        'A coluna Sessão é o número da tabela 1.']))
    ..writeln()
    ..write(events.isEmpty ? '${_row(['Nenhum alerta ou aviso registrado.'])}\n' : eventsToCsv(events, sessions: list))
    ..writeln()
    ..writeln()
    ..writeln(_row(['3. COMO LER ESTE ARQUIVO']))
    ..writeln()
    ..writeln(_row(['Coluna', 'O que significa']));
  for (final l in reportLegend) {
    b.writeln(_row(l));
  }
  b
    ..writeln()
    ..writeln(_row(['Privacidade', 'O app não grava imagens nem vídeos: este arquivo tem só números e horários.']))
    ..writeln(_row(['Aviso', 'Protótipo acadêmico. Não substitui o descanso: ao sentir sono, pare em local seguro.']));
  return b.toString();
}
