import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/connection_monitor.dart';

/// Dezente Statusanzeige. Die Farbe ist nie der einzige Hinweis – der Text
/// steht immer dabei.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (const Color(0xFF1B7F3B), 'Verbunden'),
      ConnectionStatus.reconnecting =>
        (const Color(0xFFB45309), 'Verbindung wird wiederhergestellt …'),
      ConnectionStatus.offline => (const Color(0xFFC62828), 'Keine Verbindung'),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verbindet das Badge mit dem Live-Status einer Session.
class ConnectionIndicator extends ConsumerWidget {
  const ConnectionIndicator({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider(code)).value;
    if (status == null) return const SizedBox.shrink();
    return ConnectionBadge(status: status);
  }
}
