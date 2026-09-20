import 'dart:async';
import 'dart:convert';

import 'package:PiliPlus/services/video_together/models.dart';
import 'package:PiliPlus/services/video_together/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef VideoTogetherRoomCallback = void Function(
  String method,
  VideoTogetherRoom room,
);
typedef VideoTogetherErrorCallback = void Function(String message);
typedef VideoTogetherTextCallback = void Function(
  String sender,
  String message,
);

final class VideoTogetherClient {
  VideoTogetherClient({
    required this.server,
    required this.onRoom,
    required this.onError,
    required this.onTextMessage,
    required this.onDisconnected,
  });

  final String server;
  final VideoTogetherRoomCallback onRoom;
  final VideoTogetherErrorCallback onError;
  final VideoTogetherTextCallback onTextMessage;
  final void Function() onDisconnected;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<VideoTogetherRoom>? _joinCompleter;
  Completer<VideoTogetherRoom>? _updateCompleter;
  bool _manualDisconnect = false;
  bool _connecting = false;
  bool _connected = false;
  double _clockOffset = 0;
  double _bestRoundTrip = double.infinity;
  double? _joinSentAt;
  double? _pendingUpdateClientTime;
  double? _updateSentAt;

  bool get isConnected => _connected;
  bool get isConnecting => _connecting;
  double get serverNow => _localNow + _clockOffset;
  double get _localNow => DateTime.now().microsecondsSinceEpoch / 1000000;

  Future<void> connect() async {
    if (_connected || _connecting) return;
    _connecting = true;
    _manualDisconnect = false;
    try {
      await _subscription?.cancel();
      final channel = WebSocketChannel.connect(
        VideoTogetherProtocol.webSocketUri(server),
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onError: _onSocketError,
        onDone: _onDone,
        cancelOnError: false,
      );
      await channel.ready.timeout(const Duration(seconds: 10));
      _connected = true;
    } catch (error) {
      _connected = false;
      await _subscription?.cancel();
      _subscription = null;
      _channel = null;
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _connected = false;
    _connecting = false;
    _completePending(StateError('连接已关闭'));
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    await channel?.sink.close();
  }

  Future<VideoTogetherRoom> joinRoom({
    required String roomName,
    required String password,
  }) {
    final completer = Completer<VideoTogetherRoom>();
    _joinCompleter = completer;
    _joinSentAt = _localNow;
    _send(
      VideoTogetherProtocol.joinRequest(roomName: roomName, password: password),
    );
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        if (identical(_joinCompleter, completer)) {
          _joinCompleter = null;
          _joinSentAt = null;
        }
        throw TimeoutException('加入房间超时');
      },
    );
  }

  Future<VideoTogetherRoom>? updateRoom({
    required String tempUser,
    required String password,
    required String roomName,
    required double playbackRate,
    required double currentTime,
    required bool paused,
    required String url,
    required double lastUpdateClientTime,
    required double duration,
    required bool isProtected,
    required String videoTitle,
    bool waitForResponse = false,
  }) {
    Completer<VideoTogetherRoom>? completer;
    final sentAt = _localNow;
    if (waitForResponse) {
      completer = Completer<VideoTogetherRoom>();
      _updateCompleter = completer;
      _pendingUpdateClientTime = lastUpdateClientTime;
      _updateSentAt = sentAt;
    }
    _send(
      VideoTogetherProtocol.roomUpdateRequest(
        tempUser: tempUser,
        password: password,
        roomName: roomName,
        playbackRate: playbackRate,
        currentTime: currentTime,
        paused: paused,
        url: url,
        lastUpdateClientTime: lastUpdateClientTime,
        duration: duration,
        isProtected: isProtected,
        videoTitle: videoTitle,
        sendLocalTimestamp: sentAt,
      ),
    );
    return completer?.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        if (identical(_updateCompleter, completer)) {
          _updateCompleter = null;
          _pendingUpdateClientTime = null;
          _updateSentAt = null;
        }
        throw TimeoutException('更新房间超时');
      },
    );
  }

  void updateMember({
    required String roomName,
    required String password,
    required String userId,
    required bool isLoading,
    required String currentUrl,
  }) {
    _send(
      VideoTogetherProtocol.memberUpdateRequest(
        roomName: roomName,
        password: password,
        userId: userId,
        isLoading: isLoading,
        currentUrl: currentUrl,
        sendLocalTimestamp: _localNow,
      ),
    );
  }

  void sendTextMessage({required String sender, required String text}) {
    _send(VideoTogetherProtocol.textMessageRequest(sender: sender, text: text));
  }

  void _send(Map<String, dynamic> message) {
    if (!_connected || _channel == null) {
      throw StateError('尚未连接 VideoTogether 服务器');
    }
    _channel!.sink.add(jsonEncode(message));
  }

  void _onData(dynamic raw) {
    final text = raw is String ? raw : utf8.decode(raw as List<int>);
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded case final Map<String, dynamic> message) {
          _handleMessage(message);
        }
      } catch (error) {
        onError('服务器消息解析失败：$error');
      }
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    final method = message['method'] as String? ?? '';
    if (message['errorMessage'] case final String errorMessage) {
      onError(errorMessage);
      final error = StateError(errorMessage);
      if (method == VideoTogetherProtocol.roomJoin) {
        _completeJoinError(error);
      } else if (method == VideoTogetherProtocol.roomUpdate) {
        _completeUpdateError(error);
      } else {
        _completePending(error);
      }
      return;
    }

    final data = message['data'];
    if (method == VideoTogetherProtocol.timestampReply &&
        data is Map<String, dynamic>) {
      _updateClock(data);
      return;
    }

    if (method == VideoTogetherProtocol.textMessage &&
        data is Map<String, dynamic>) {
      final text = data['msg'] as String? ?? '';
      if (text.isNotEmpty) {
        onTextMessage(data['id'] as String? ?? '', text);
      }
      return;
    }

    if ((method == VideoTogetherProtocol.roomJoin ||
            method == VideoTogetherProtocol.roomUpdate ||
            method == VideoTogetherProtocol.memberUpdate) &&
        data is Map<String, dynamic>) {
      final receivedAt = _localNow;
      final room = VideoTogetherRoom.fromJson(data);
      final isOwnUpdate =
          method == VideoTogetherProtocol.roomUpdate &&
          _pendingUpdateClientTime != null &&
          (room.lastUpdateClientTime - _pendingUpdateClientTime!).abs() <
              0.0001;
      onRoom(method, room);
      if (method == VideoTogetherProtocol.roomJoin) {
        _updateClockFromRoomTimestamp(room, _joinSentAt, receivedAt);
        _joinCompleter?.complete(room);
        _joinCompleter = null;
        _joinSentAt = null;
      } else if (isOwnUpdate) {
        _updateClockFromRoomTimestamp(room, _updateSentAt, receivedAt);
        _updateCompleter?.complete(room);
        _updateCompleter = null;
        _pendingUpdateClientTime = null;
        _updateSentAt = null;
      }
    }
  }

  void _updateClock(Map<String, dynamic> data) {
    final localSend = _asDouble(data['sendLocalTimestamp']);
    final serverReceive = _asDouble(data['receiveServerTimestamp']);
    final serverSend = _asDouble(data['sendServerTimestamp']);
    final localReceive = _localNow;
    final trip = VideoTogetherProtocol.roundTrip(
      localSend: localSend,
      serverReceive: serverReceive,
      serverSend: serverSend,
      localReceive: localReceive,
    );
    if (trip >= 0 && trip <= _bestRoundTrip) {
      _bestRoundTrip = trip;
      _clockOffset = VideoTogetherProtocol.clockOffset(
        localSend: localSend,
        serverReceive: serverReceive,
        serverSend: serverSend,
        localReceive: localReceive,
      );
    }
  }

  void _updateClockFromRoomTimestamp(
    VideoTogetherRoom room,
    double? sentAt,
    double receivedAt,
  ) {
    final timestamp = room.timestamp;
    if (sentAt == null || timestamp == null || timestamp <= 0) return;
    final trip = receivedAt - sentAt;
    if (trip < 0 || trip > _bestRoundTrip) return;
    _bestRoundTrip = trip;
    _clockOffset = timestamp - ((sentAt + receivedAt) / 2);
  }

  void _onSocketError(Object error, StackTrace stackTrace) {
    _connected = false;
    onError('WebSocket 连接错误：$error');
    _completePending(error, stackTrace);
  }

  void _onDone() {
    _connected = false;
    _completePending(StateError('服务器连接已断开'));
    if (!_manualDisconnect) onDisconnected();
  }

  void _completePending(Object error, [StackTrace? stackTrace]) {
    _completeJoinError(error, stackTrace);
    _completeUpdateError(error, stackTrace);
  }

  void _completeJoinError(Object error, [StackTrace? stackTrace]) {
    if (_joinCompleter case final completer? when !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    _joinCompleter = null;
    _joinSentAt = null;
  }

  void _completeUpdateError(Object error, [StackTrace? stackTrace]) {
    if (_updateCompleter case final completer? when !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    _updateCompleter = null;
    _pendingUpdateClientTime = null;
    _updateSentAt = null;
  }

  static double _asDouble(Object? value) => switch (value) {
    num value => value.toDouble(),
    String value => double.tryParse(value) ?? 0,
    _ => 0,
  };
}
