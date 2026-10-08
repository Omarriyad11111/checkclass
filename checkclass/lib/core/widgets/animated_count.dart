import 'package:flutter/material.dart';

import 'motion.dart';

/// Zahl, die sanft zum neuen Wert zählt.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(end: value),
      duration: motionDuration(context, const Duration(milliseconds: 350)),
      builder: (_, v, _) => Text('$v', style: style),
    );
  }
}
