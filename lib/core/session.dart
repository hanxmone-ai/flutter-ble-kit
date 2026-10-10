import 'dart:async';

import 'adapter.dart';
import 'models.dart';

enum SessionState { idle, connecting, ready, reconnecting, failed, closed }

/// A connection that discovers services and reconnects when the link drops.
///
/// Phones lose BLE links all the time (out of range, the peripheral reboots,
/// the OS reclaims the radio). After an unexpected disconnect the session
/// retries with exponential backoff: [backoff], then twice that, and so on, up
/// to [maxRetries] attempts.
class DeviceSession {
  DeviceSession(
    this.adapter,
    this.deviceId, {
    this.maxRetries = 3,
    this.backoff = const Duration(seconds: 1),
    this.desiredMtu = 247,
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  final BleAdapter adapter;
  final String deviceId;
  final int maxRetries;
  final Duration backoff;
  final int desiredMtu;
  final Future<void> Function(Duration) _sleep;

  final StreamController<SessionState> _states = StreamController.broadcast();
  StreamSubscription<ConnectionStatus>? _statusSub;
  SessionState _state = SessionState.idle;
  BleConnection? _connection;
  List<GattService> _services = const [];
  Object? _lastError;
  bool _closing = false;

  SessionState get state => _state;
  Stream<SessionState> get states => _states.stream;

  /// The current connection, when [state] is [SessionState.ready].
  BleConnection? get connection => _state == SessionState.ready ? _connection : null;

  List<GattService> get services => _services;

  /// The error behind the last failed attempt, if any.
  Object? get lastError => _lastError;

  /// Connects and discovers services. Throws if the first attempt fails.
  Future<void> open() async {
    if (_state != SessionState.idle && _state != SessionState.failed) {
      throw StateError('Session is already ${_state.name}');
    }
    _closing = false;
    _set(SessionState.connecting);
    try {
      await _connect();
    } catch (e) {
      _lastError = e;
      _set(SessionState.failed);
      rethrow;
    }
  }

  Future<void> _connect() async {
    await _statusSub?.cancel();
    final connection = await adapter.connect(deviceId);
    if (_closing) {
      await connection.disconnect();
      return;
    }
    _connection = connection;
    try {
      await connection.requestMtu(desiredMtu);
    } catch (_) {
      // Not every platform or device allows it; the default MTU still works.
    }
    _services = await connection.discoverServices();
    _statusSub = connection.status.listen((status) {
      if (status == ConnectionStatus.disconnected && !_closing && _state == SessionState.ready) {
        unawaited(_reconnect());
      }
    });
    _set(SessionState.ready);
  }

  Future<void> _reconnect() async {
    _set(SessionState.reconnecting);
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      await _sleep(backoff * (1 << attempt));
      if (_closing) return;
      try {
        await _connect();
        return;
      } catch (e) {
        _lastError = e;
      }
    }
    if (!_closing) _set(SessionState.failed);
  }

  /// Disconnects and stops reconnecting.
  Future<void> close() async {
    if (_state == SessionState.closed) return;
    _closing = true;
    await _statusSub?.cancel();
    _statusSub = null;
    final connection = _connection;
    _connection = null;
    _set(SessionState.closed);
    if (connection != null) {
      try {
        await connection.disconnect();
      } catch (_) {
        // Already gone.
      }
    }
    await _states.close();
  }

  void _set(SessionState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }
}
