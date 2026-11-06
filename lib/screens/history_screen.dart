import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/csv_export.dart';
import '../data/models.dart';
import '../data/session_database.dart';
import '../theme.dart';
import '../widgets/common.dart';

String formatDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '${m}min ${s.toString().padLeft(2, '0')}s' : '${s}s';
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.database});

  final SessionDatabase database;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SessionRecord>? _sessions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.database.listSessions();
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _export() async {
    final sessions = _sessions ?? [];
    if (sessions.isEmpty) return;
    final events = await widget.database.allEvents();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final sessionsFile = File(p.join(dir.path, 'sessoes_$stamp.csv'));
    final eventsFile = File(p.join(dir.path, 'alertas_$stamp.csv'));
    // BOM UTF‑8 para o Excel reconhecer os acentos.
    await sessionsFile.writeAsString('﻿${sessionsToCsv(sessions)}');
    await eventsFile.writeAsString('﻿${eventsToCsv(events)}');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(sessionsFile.path), XFile(eventsFile.path)],
      subject: 'Fatigue Guard — histórico de sessões',
      text: 'Histórico exportado do app Fatigue Guard (TCC).',
    ));
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Apagar histórico?'),
        content: const Text('Todas as sessões e alertas gravados neste aparelho serão apagados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apagar', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.database.deleteAll();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final totalAlerts = sessions?.fold<int>(0, (sum, s) => sum + s.totalAlerts) ?? 0;
    final totalTime = sessions?.fold<Duration>(Duration.zero, (sum, s) => sum + s.duration) ?? Duration.zero;
    return AppPage(
      children: [
        const Text('HISTÓRICO LOCAL', style: AppText.kicker),
        const SizedBox(height: 8),
        const Text('Sessões gravadas', style: AppText.h2),
        const SizedBox(height: 9),
        const Text(
          'Resumo de cada monitoramento, salvo em um banco SQLite no próprio aparelho. '
          'Somente números e horários são guardados — nenhuma imagem.',
          style: AppText.body,
        ),
        const SizedBox(height: 20),
        if (sessions == null)
          const Center(child: CircularProgressIndicator(color: AppColors.accent))
        else if (sessions.isEmpty)
          const Panel(
            child: Row(children: [
              Icon(Icons.inbox_outlined, color: AppColors.muted),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Nenhuma sessão ainda. Sessões com mais de 10 segundos no painel ao vivo aparecem aqui.',
                  style: AppText.body,
                ),
              ),
            ]),
          )
        else ...[
          Row(children: [
            Expanded(child: _Summary(label: 'Sessões', value: '${sessions.length}')),
            const SizedBox(width: 8),
            Expanded(child: _Summary(label: 'Tempo total', value: formatDuration(totalTime))),
            const SizedBox(width: 8),
            Expanded(child: _Summary(label: 'Alertas', value: '$totalAlerts', color: AppColors.red)),
          ]),
          const SizedBox(height: 16),
          for (final s in sessions) ...[
            _SessionTile(
              session: s,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionDetailScreen(database: widget.database, session: s),
              )).then((_) => _load()),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            key: const Key('button-exportar'),
            label: 'Exportar CSV',
            icon: Icons.ios_share,
            onPressed: _export,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline, color: AppColors.muted),
            label: const Text('Apagar histórico', style: TextStyle(color: AppColors.muted)),
          ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value, this.color = AppColors.text});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});
  final SessionRecord session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final alerts = session.totalAlerts;
    final color = alerts > 0 ? AppColors.red : session.attentionCount > 0 ? AppColors.yellow : AppColors.green;
    return Material(
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            StatusDot(color: color, size: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatDateTime(session.startedAt), style: AppText.cardTitle),
                const SizedBox(height: 4),
                Text(
                  '${formatDuration(session.duration)} • $alerts alerta(s) • '
                  '${session.attentionCount} atenção • PERCLOS máx ${(session.maxPerclos * 100).round()}%',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.database, required this.session});

  final SessionDatabase database;
  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final rows = [
      ('Início', formatDateTime(s.startedAt)),
      ('Duração', formatDuration(s.duration)),
      ('Alertas — olhos fechados', '${s.alertsEyes}'),
      ('Alertas — bocejo', '${s.alertsYawn}'),
      ('Alertas — cabeça caindo', '${s.alertsHead}'),
      ('Alertas — rosto fora da câmera', '${s.alertsFace}'),
      ('Avisos de atenção', '${s.attentionCount}'),
      ('PERCLOS máximo', '${(s.maxPerclos * 100).toStringAsFixed(1)}%'),
      ('Piscadas/min (média)', s.avgBlinkRate.toStringAsFixed(1)),
      ('Limiar EAR', s.earThreshold.toStringAsFixed(3)),
      ('Limiar MAR', s.marThreshold.toStringAsFixed(3)),
      ('Calibrado', s.calibrated ? 'Sim' : 'Não (valores padrão)'),
    ];
    return AppPage(
      children: [
        const Text('DETALHES DA SESSÃO', style: AppText.kicker),
        const SizedBox(height: 8),
        Text(formatDateTime(s.startedAt), style: AppText.h2),
        const SizedBox(height: 16),
        Panel(
          child: Column(children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(child: Text(label, style: AppText.body)),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        const Text('LINHA DO TEMPO', style: AppText.section),
        const SizedBox(height: 10),
        FutureBuilder<List<SessionEvent>>(
          future: s.id == null ? Future.value(s.events) : database.eventsFor(s.id!),
          builder: (context, snap) {
            final events = snap.data;
            if (events == null) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            if (events.isEmpty) {
              return const Text('Nenhum alerta ou aviso nesta sessão.', style: AppText.body);
            }
            return Column(children: [
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(
                        e.type == EventType.attention ? Icons.info_outline : Icons.warning_amber_rounded,
                        color: e.type == EventType.attention ? AppColors.yellow : AppColors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.type.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '+${formatDuration(e.time.difference(s.startedAt))} • EAR ${e.ear.toStringAsFixed(2)} • '
                            'MAR ${e.mar.toStringAsFixed(2)} • PERCLOS ${(e.perclos * 100).round()}%',
                            style: const TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]);
          },
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () async {
            final navigator = Navigator.of(context);
            if (s.id != null) await database.deleteSession(s.id!);
            navigator.pop();
          },
          icon: const Icon(Icons.delete_outline, color: AppColors.muted),
          label: const Text('Apagar esta sessão', style: TextStyle(color: AppColors.muted)),
        ),
      ],
    );
  }
}
