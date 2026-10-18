// A WebSocket client that sends nowhere: it keeps what the app sent so a test
// can read the `register:group` frame, and lets the test play server events.

import 'dart:async';

import 'package:senclaw_desktop/core/config/app_config.dart';
import 'package:senclaw_desktop/core/transport/ws_client.dart';

class FakeWs implements WsClient {
  final sent = <Map<String, dynamic>>[];
  final _events = StreamController<WsEvent>.broadcast();
  final _status = StreamController<WsStatus>.broadcast();

  /// Frames of one `type` the app has sent.
  List<Map<String, dynamic>> sentOf(String type) =>
      [for (final m in sent) if (m['type'] == type) m];

  /// Plays a server event to whoever listens.
  void emit(WsEvent event) => _events.add(event);

  @override
  WsStatus get status => WsStatus.connected;
  @override
  Stream<WsStatus> get statusStream => _status.stream;
  @override
  Stream<WsEvent> get events => _events.stream;
  @override
  void updateConfig(AppConfig config) {}
  @override
  void connect() {}
  @override
  void subscribe(String groupJid) {}
  @override
  void unsubscribe(String groupJid) {}
  @override
  void send(Map<String, dynamic> msg) => sent.add(msg);
  @override
  void dispose() {
    _events.close();
    _status.close();
  }
}
