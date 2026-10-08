import 'dart:async';

enum ConnectionStatus { connected, reconnecting, offline }

/// Wandelt „kommen die Daten nur aus dem Cache?“-Ereignisse in einen ruhigen
/// Verbindungsstatus um.
///
/// * Serverdaten → [ConnectionStatus.connected]
/// * Cache-Daten länger als [reconnectingAfter] → reconnecting
/// * Cache-Daten länger als [offlineAfter] → offline
///
/// Kurze Aussetzer (< [reconnectingAfter]) bleiben unsichtbar, damit die
/// Anzeige nicht flackert.
Stream<ConnectionStatus> monitorConnection(
  Stream<bool> fromCache, {
  Duration reconnectingAfter = const Duration(milliseconds: 1500),
  Duration offlineAfter = const Duration(seconds: 6),
}) {
  late final StreamController<ConnectionStatus> controller;
  StreamSubscription<bool>? subscription;
  Timer? reconnectTimer;
  Timer? offlineTimer;
  ConnectionStatus? last;

  void emit(ConnectionStatus status) {
    if (status == last || controller.isClosed) return;
    last = status;
    controller.add(status);
  }

  void cancelTimers() {
    reconnectTimer?.cancel();
    offlineTimer?.cancel();
    reconnectTimer = null;
    offlineTimer = null;
  }

  void arm() {
    if (reconnectTimer != null) return; // läuft bereits
    reconnectTimer = Timer(reconnectingAfter, () => emit(ConnectionStatus.reconnecting));
    offlineTimer = Timer(offlineAfter, () => emit(ConnectionStatus.offline));
  }

  controller = StreamController<ConnectionStatus>(
    onListen: () {
      arm();
      subscription = fromCache.listen(
        (cached) {
          if (cached) {
            arm();
          } else {
            cancelTimers();
            emit(ConnectionStatus.connected);
          }
        },
        onError: (_) => arm(),
      );
    },
    onCancel: () {
      cancelTimers();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
