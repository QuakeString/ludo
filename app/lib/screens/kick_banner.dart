import 'package:flutter/material.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// Asks the host whether a player who keeps letting the clock run out may
/// stay. It counts down; when it runs out the server takes silence as no.
class KickBanner extends StatelessWidget {
  const KickBanner({
    super.key,
    required this.ask,
    required this.until,
    required this.onKeep,
    required this.onRemove,
  });

  final KickAsk ask;
  final DateTime until;
  final VoidCallback onKeep;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = until.difference(DateTime.now());
    final total = Duration(seconds: ask.seconds);
    final start = total.inMilliseconds <= 0
        ? 0.0
        : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Material(
      key: const ValueKey('kick-banner'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${ask.name} has missed ${ask.missed} turns in a row. '
              'Give them 5 more chances?',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            // Runs down to nothing over the time the host has to answer.
            TweenAnimationBuilder<double>(
              tween: Tween(begin: start, end: 0),
              duration: left.isNegative ? Duration.zero : left,
              builder: (context, v, _) => Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${(v * ask.seconds).ceil()}s',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onTertiaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('kick-remove'),
                  onPressed: onRemove,
                  child: const Text('Remove'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  key: const ValueKey('kick-keep'),
                  onPressed: onKeep,
                  child: const Text('Give 5 more'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
