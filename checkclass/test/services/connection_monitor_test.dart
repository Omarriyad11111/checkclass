import 'dart:async';

import 'package:checkclass/services/connection_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late StreamController<bool> fromCache;
  late List<ConnectionStatus> statuses;
  late StreamSubscription<ConnectionStatus> sub;

  setUp(() {
    fromCache = StreamController<bool>();
    statuses = [];
    sub = monitorConnection(
      fromCache.stream,
      reconnectingAfter: const Duration(milliseconds: 40),
      offlineAfter: const Duration(milliseconds: 120),
    ).listen(statuses.add);
  });

  tearDown(() async {
    await sub.cancel();
    await fromCache.close();
  });

  test('Serverdaten → verbunden', () async {
    fromCache.add(false);
    await wait(10);
    expect(statuses, [ConnectionStatus.connected]);
  });

  test('Verbindungsverlust: wiederherstellen → offline → wieder verbunden', () async {
    fromCache.add(false);
    await wait(10);
    fromCache.add(true);
    await wait(80);
    expect(statuses.last, ConnectionStatus.reconnecting);
    await wait(100);
    expect(statuses.last, ConnectionStatus.offline);
    fromCache.add(false);
    await wait(10);
    expect(statuses, [
      ConnectionStatus.connected,
      ConnectionStatus.reconnecting,
      ConnectionStatus.offline,
      ConnectionStatus.connected,
    ]);
  });

  test('kurzer Aussetzer bleibt unsichtbar', () async {
    fromCache.add(false);
    await wait(10);
    fromCache.add(true);
    await wait(10);
    fromCache.add(false);
    await wait(200);
    expect(statuses, [ConnectionStatus.connected]);
  });

  test('ohne jede Serverantwort: erst wiederherstellen, dann offline', () async {
    await wait(200);
    expect(statuses, [ConnectionStatus.reconnecting, ConnectionStatus.offline]);
  });
}
