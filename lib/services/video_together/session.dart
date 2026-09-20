import 'dart:async';

import 'package:PiliPlus/services/video_together/client.dart';
import 'package:PiliPlus/services/video_together/models.dart';
import 'package:PiliPlus/services/video_together/playback.dart';
import 'package:PiliPlus/services/video_together/preferences.dart';
import 'package:get/get.dart';
import 'package:uuid/v4.dart';

typedef VideoTogetherOpenVideo = Future<bool> Function(String url);

final class VideoTogetherSession {
  VideoTogetherSession._();

  static final instance = VideoTogetherSession._();

  final role = VideoTogetherRole.none.obs;
  final connectionState = VideoTogetherConnectionState.disconnected.obs;
  final room = Rxn<VideoTogetherRoom>();
  final errorMessage = RxnString();
  final isBusy = false.obs;
  final messages = <VideoTogetherTextMessage>[].obs;

  VideoTogetherClient? _client;
  VideoTogetherPlayback? _playback;
  VideoTogetherMedia? _media;
  VideoTogetherOpenVideo? _openVideo;
  Timer? _timer;
  String _roomName = '';
  String _password = '';
  String _server = '';
  String _tempUser = '';
  String? _lastNavigationUrl;
  bool _running = false;
  bool _tickRunning = false;
  bool _reconnectRunning = false;
  bool _applyingRemoteState = false;
  bool _resumeAfterLoading = false;

  bool get inRoom => role.value != VideoTogetherRole.none;
  String get roomName => _roomName;
  String get server => _server;
  String get currentPassword => _password;
  VideoTogetherMedia? get media => _media;

  void configureNavigation(VideoTogetherOpenVideo callback) {
    _openVideo = callback;
  }

  void bindPlayback(VideoTogetherPlayback playback, VideoTogetherMedia media) {
    _playback = playback;
    _media = media;
    _lastNavigationUrl = null;
    if (_running) unawaited(_tick());
  }

  void unbindPlayback(VideoTogetherPlayback playback) {
    if (identical(_playback, playback)) {
      _playback = null;
      _media = null;
    }
  }

  Future<void> createRoom({
    required String roomName,
    required String password,
  }) async {
    await _start(
      targetRole: VideoTogetherRole.host,
      roomName: roomName,
      password: password,
    );
  }

  Future<void> joinRoom({
    required String roomName,
    required String password,
  }) async {
    await _start(
      targetRole: VideoTogetherRole.member,
      roomName: roomName,
      password: password,
    );
  }

  Future<void> _start({
    required VideoTogetherRole targetRole,
    required String roomName,
    required String password,
  }) async {
    final normalizedRoomName = roomName.trim();
    if (normalizedRoomName.isEmpty) {
      throw const FormatException('请输入房间名');
    }

    isBusy.value = true;
    errorMessage.value = null;
    await leave(clearError: false);
    _roomName = normalizedRoomName;
    _password = password;
    _server = VideoTogetherPreferences.server;
    _tempUser = '${const UuidV4().generate()}:${_localNow()}';
    role.value = targetRole;
    _running = true;
    connectionState.value = VideoTogetherConnectionState.connecting;

    try {
      await _connectClient();
      if (targetRole == VideoTogetherRole.host) {
        await _sendHostUpdate(waitForResponse: true);
      } else {
        final joinedRoom = await _client!.joinRoom(
          roomName: _roomName,
          password: _password,
        );
        room.value = joinedRoom;
        await _syncMember(joinedRoom);
      }
      connectionState.value = VideoTogetherConnectionState.connected;
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    } catch (error) {
      errorMessage.value = _friendlyError(error);
      connectionState.value = VideoTogetherConnectionState.error;
      await leave(clearError: false);
      rethrow;
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> leave({bool clearError = true}) async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    final client = _client;
    _client = null;
    await client?.disconnect();
    role.value = VideoTogetherRole.none;
    connectionState.value = VideoTogetherConnectionState.disconnected;
    room.value = null;
    messages.clear();
    _roomName = '';
    _password = '';
    _server = '';
    _tempUser = '';
    _lastNavigationUrl = null;
    _resumeAfterLoading = false;
    if (clearError) errorMessage.value = null;
  }

  Future<void> sendTextMessage(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    final client = _client;
    if (client == null || !client.isConnected) {
      throw StateError('尚未连接 VideoTogether 服务器');
    }
    client.sendTextMessage(
      sender: VideoTogetherPreferences.nickname,
      text: text,
    );
  }

  Future<void> openCurrentRoomVideo() async {
    final url = room.value?.url;
    if (url == null || url.isEmpty) return;
    await _navigateTo(url, force: true);
  }

  Future<void> _connectClient() async {
    final client = VideoTogetherClient(
      server: _server,
      onRoom: _onRoom,
      onError: (message) => errorMessage.value = message,
      onTextMessage: _onTextMessage,
      onDisconnected: _onDisconnected,
    );
    _client = client;
    await client.connect();
  }

  void _onRoom(String method, VideoTogetherRoom value) {
    room.value = value;
    errorMessage.value = null;
    if (role.value == VideoTogetherRole.member) {
      unawaited(_syncMember(value));
    }
  }

  void _onTextMessage(String sender, String text) {
    messages.add(
      VideoTogetherTextMessage(
        sender: sender.isEmpty ? '匿名用户' : sender,
        text: text,
        receivedAt: DateTime.now(),
        isMine: sender == VideoTogetherPreferences.nickname,
      ),
    );
    if (messages.length > 100) messages.removeRange(0, messages.length - 100);
  }

  void _onDisconnected() {
    if (!_running) return;
    connectionState.value = VideoTogetherConnectionState.disconnected;
  }

  Future<void> _tick() async {
    if (!_running || _tickRunning) return;
    _tickRunning = true;
    try {
      final client = _client;
      if (client == null || !client.isConnected) {
        await _reconnect();
        return;
      }
      switch (role.value) {
        case VideoTogetherRole.host:
          await _sendHostUpdate();
        case VideoTogetherRole.member:
          final currentRoom = room.value;
          if (currentRoom != null) await _syncMember(currentRoom);
        case VideoTogetherRole.none:
          break;
      }
    } catch (error) {
      errorMessage.value = _friendlyError(error);
    } finally {
      _tickRunning = false;
    }
  }

  Future<void> _reconnect() async {
    if (_reconnectRunning || !_running) return;
    _reconnectRunning = true;
    connectionState.value = VideoTogetherConnectionState.reconnecting;
    try {
      await _client?.disconnect();
      await _connectClient();
      if (role.value == VideoTogetherRole.member) {
        room.value = await _client!.joinRoom(
          roomName: _roomName,
          password: _password,
        );
      } else if (role.value == VideoTogetherRole.host) {
        await _sendHostUpdate(waitForResponse: true);
      }
      connectionState.value = VideoTogetherConnectionState.connected;
      errorMessage.value = null;
    } catch (error) {
      connectionState.value = VideoTogetherConnectionState.error;
      errorMessage.value = _friendlyError(error);
    } finally {
      _reconnectRunning = false;
    }
  }

  Future<void> _sendHostUpdate({bool waitForResponse = false}) async {
    final client = _client;
    if (client == null || !client.isConnected) return;
    final playback = _playback;
    final currentRoom = room.value;

    if (VideoTogetherPreferences.waitForLoading &&
        currentRoom?.waitForLoading == true &&
        playback?.isReady == true &&
        playback!.isPlaying) {
      _resumeAfterLoading = true;
      await playback.pause();
    } else if (_resumeAfterLoading &&
        currentRoom?.waitForLoading != true &&
        playback?.isReady == true) {
      _resumeAfterLoading = false;
      await playback!.play();
    }

    final isReady = playback?.isReady == true;
    final future = client.updateRoom(
      tempUser: _tempUser,
      password: _password,
      roomName: _roomName,
      playbackRate: isReady ? playback!.playbackRate : 1,
      currentTime: isReady ? playback!.positionSeconds : 0,
      paused: !isReady || !playback!.isPlaying || playback.isBuffering,
      url: _media?.url ?? '',
      lastUpdateClientTime: client.serverNow,
      duration: isReady && playback!.durationSeconds > 0
          ? playback.durationSeconds
          : 1000000000,
      isProtected: VideoTogetherPreferences.passwordProtected,
      videoTitle: _media?.title ?? '',
      waitForResponse: waitForResponse,
    );
    if (future != null) room.value = await future;
  }

  Future<void> _syncMember(VideoTogetherRoom currentRoom) async {
    final client = _client;
    if (client == null || !client.isConnected || _applyingRemoteState) return;

    final sameMedia = _isSameMedia(_media?.url, currentRoom.url);
    if (!sameMedia &&
        currentRoom.url.isNotEmpty &&
        VideoTogetherPreferences.autoOpenVideo) {
      await _navigateTo(currentRoom.url);
    }

    final playback = _playback;
    final canSync =
        playback?.isReady == true && _isSameMedia(_media?.url, currentRoom.url);
    if (canSync) await _applyRemoteState(playback!, currentRoom);

    client.updateMember(
      roomName: _roomName,
      password: _password,
      userId: _tempUser,
      isLoading: !canSync || playback!.isBuffering,
      currentUrl: canSync ? currentRoom.url : _media?.url ?? '',
    );
  }

  Future<void> _applyRemoteState(
    VideoTogetherPlayback playback,
    VideoTogetherRoom currentRoom,
  ) async {
    if (_applyingRemoteState) return;
    _applyingRemoteState = true;
    try {
      if (VideoTogetherPreferences.syncPlaybackRate &&
          (playback.playbackRate - currentRoom.playbackRate).abs() > 0.01) {
        await playback.setPlaybackRate(currentRoom.playbackRate);
      }

      final target = currentRoom.targetPosition(_client!.serverNow);
      if ((playback.positionSeconds - target).abs() >=
          VideoTogetherPreferences.syncThreshold) {
        await playback.seek(target);
      }

      if (currentRoom.paused && playback.isPlaying) {
        await playback.pause();
      } else if (!currentRoom.paused && !playback.isPlaying) {
        await playback.play();
      }
    } finally {
      _applyingRemoteState = false;
    }
  }

  Future<void> _navigateTo(String url, {bool force = false}) async {
    if (!force && _lastNavigationUrl == url) return;
    final openVideo = _openVideo;
    if (openVideo == null) {
      errorMessage.value = '未配置视频跳转处理器';
      return;
    }
    _lastNavigationUrl = url;
    final handled = await openVideo(url);
    if (!handled) {
      errorMessage.value = 'PiliPlus 暂不支持房主当前页面：$url';
    }
  }

  static bool _isSameMedia(String? local, String remote) {
    if (local == null || local.isEmpty || remote.isEmpty) return false;
    return VideoTogetherMediaIdentity.fromUrl(local)
        .sameAs(VideoTogetherMediaIdentity.fromUrl(remote));
  }

  static double _localNow() => DateTime.now().microsecondsSinceEpoch / 1000000;

  static String _friendlyError(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) return error.message ?? '请求超时';
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }
}
