import 'package:checkclass/core/widgets/connection_badge.dart';
import 'package:checkclass/services/connection_monitor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expected = {
    ConnectionStatus.connected: 'Verbunden',
    ConnectionStatus.reconnecting: 'Verbindung wird wiederhergestellt …',
    ConnectionStatus.offline: 'Keine Verbindung',
  };

  for (final entry in expected.entries) {
    testWidgets('zeigt "${entry.value}"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ConnectionBadge(status: entry.key))),
      );
      expect(find.text(entry.value), findsOneWidget);
    });
  }
}
