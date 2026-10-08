import 'package:flutter/material.dart';

import '../../../core/widgets/animated_count.dart';
import '../../../core/widgets/motion.dart';

/// Große Ergebniskachel: Anzahl, Prozent und animierter Balken.
class ResultTile extends StatelessWidget {
  const ResultTile({
    super.key,
    required this.emoji,
    required this.label,
    required this.count,
    required this.percent,
    required this.color,
  });

  final String emoji;
  final String label;
  final int count;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $count Antworten, $percent Prozent',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(label, style: text.titleMedium),
              const SizedBox(height: 12),
              AnimatedCount(
                value: count,
                style: text.displayMedium?.copyWith(fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  AnimatedCount(value: percent, style: text.titleLarge),
                  Text(' %', style: text.titleLarge),
                ],
              ),
              const SizedBox(height: 16),
              TweenAnimationBuilder<double>(
                tween: Tween(end: percent / 100),
                duration: motionDuration(context, const Duration(milliseconds: 450)),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 12,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
