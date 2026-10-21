import 'package:flutter/material.dart';

import '../match_history.dart';
import '../theme/seat_colors.dart';
import 'game_over.dart';
import 'match_stats.dart';

/// The last ten games finished on this device, each opening onto its stats.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<MatchRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await MatchHistoryStore.load();
    if (mounted) setState(() => _records = records);
  }

  Future<void> _clear() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recent matches?'),
        content: const Text('Their stats are gone for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await MatchHistoryStore.clear();
    _load();
  }

  void _open(MatchRecord record) {
    showDialog<void>(
      context: context,
      builder: (_) => MatchStatsSheet(
        state: record.state,
        aiSeats: record.aiSeats,
        elapsed: record.elapsed,
        nameOf: record.nameOf,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final records = _records;

    return Scaffold(
      backgroundColor: palette.felt,
      appBar: AppBar(
        backgroundColor: palette.felt,
        title: const Text('Recent matches'),
        actions: [
          if (records != null && records.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: records == null
            ? const SizedBox.shrink()
            : records.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Finished games show up here, with their stats.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.faint),
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _MatchTile(
                      record: records[i],
                      onTap: () => _open(records[i]),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.record, required this.onTap});

  final MatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final state = record.state;
    final winner = placings(state).first.seat;
    final colour = colourOfArm(state.armOf(winner), state.board.arms);
    final name = record.nameOf(winner);
    final won = name == 'You' ? 'You won' : '$name won';

    return Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.panelEdge),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colour,
                child: const Icon(
                  Icons.emoji_events_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      won,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${record.online ? 'Online' : 'On this phone'} · '
                      '${state.rules.players} seats · '
                      '${formatSpan(record.elapsed)}',
                      style: TextStyle(fontSize: 12, color: palette.faint),
                    ),
                    Text(
                      whenPlayed(record.finishedAt, DateTime.now()),
                      style: TextStyle(fontSize: 12, color: palette.faint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.bar_chart_rounded, color: palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today, 14:05", "Yesterday, 09:30", or "3 Oct, 18:12".
String whenPlayed(DateTime at, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final gap = today.difference(day).inDays;
  if (gap == 0) return 'Today, $time';
  if (gap == 1) return 'Yesterday, $time';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = at.year == now.year ? '' : ' ${at.year}';
  return '${at.day} ${months[at.month - 1]}$year, $time';
}
