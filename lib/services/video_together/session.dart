import 'dart:async';

import 'package:PiliPlus/services/video_together/client.dart';
import 'package:PiliPlus/services/video_together/models.dart';
import 'package:PiliPlus/services/video_together/playback.dart';
import 'package:PiliPlus/services/video_together/preferences.dart';
import 'package:PiliPlus/services/video_together/protocol.dart';
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
  final isControlling = false.obs;
  final messages = <VideoTogetherTextMessage>[].obs;

  VideoTogetherClient? _client;
  VideoTogetherPlayback? _playback;
  VideoTogetherMedia? _media;
  VideoTogetherOpenVideo? _openVideo;
  VideoTogetherPlaybackSnapshot? _lastPlaybackSnapshot;
  Timer? _timer;
  String _roomName = '';
  String _password = '';
  String _server = '';
  String _memberUserId = '';
  String _controlUserId = '';
  String? _lastNavigationUrl;
  String? _expectedRemoteUrl;
  double? _pendingRoomUpdateTime;
  double _lastRoomUpdateAt = 0;
  double _lastMemberUpdateAt = 0;
  bool _running = false;
  bool _sessionReady = false;
  bool _tickRunning = false;
  bool _reconnectRunning = false;
  bool _syncRunning = false;
  bool _applyingRemoteState = false;
  bool _pendingLocalMediaChange = false;
  bool _memberLoadingStateChanged = false;
  bool _resumeAfterLoading = false;
  bool _hasHeldControl = false;
  VideoTogetherRoom? _pendingFollowerRoom;
  final _remotePlaybackSynchronizer = VideoTogetherRemotePlaybackSynchronizer();

  bool get inRoom => role.value != VideoTogetherRole.none;
  String get roomName => _roomName;
  String get server => _server;
  String get currentPassword => _password;
  VideoTogetherMedia? get media => _media;

  void configureNavigation(VideoTogetherOpenVideo callback) {
    _openVideo = callback;
  }

  void bindPlayback(VideoTogetherPlayback playback, VideoTogetherMedia media) {
    final previousMedia = _media;
    final expectedRemote = _expectedRemoteUrl;
    final openedExpectedRemote =
        expectedRemote != null && _isSameMedia(media.url, expectedRemote);
    final mediaChanged =
        previousMedia != null && !_isSameMedia(previousMedia.url, media.url);

    _playback = playback;
    _media = media;
    _remotePlaybackSynchronizer.reset();
    if (openedExpectedRemote) {
      _expectedRemoteUrl = null;
      _pendingLocalMediaChange = false;
    } else if (_running && _sessionReady && mediaChanged) {
      _pendingLocalMediaChange = true;
    }
    _capturePlaybackSnapshot();
    if (_running) unawaited(_tick());
  }

  void unbindPlayback(VideoTogetherPlayback playback) {
    if (identical(_playback, playback)) {
      _playback = null;
      _lastPlaybackSnapshot = null;
      _remotePlaybackSynchronizer.reset();
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
    _memberUserId = _newUserId();
    _controlUserId = _newUserId();
    role.value = targetRole;
    isControlling.value = targetRole == VideoTogetherRole.host;
    _hasHeldControl = targetRole == VideoTogetherRole.host;
    _running = true;
    connectionState.value = VideoTogetherConnectionState.connecting;

    try {
      await _connectClient();
      if (targetRole == VideoTogetherRole.host) {
        await _sendRoomUpdate();
      } else {
        await _joinAsFollower(forceMemberUpdate: true);
      }
      _sessionReady = true;
      connectionState.value = VideoTogetherConnectionState.connected;
      _capturePlaybackSnapshot();
      _timer = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => _tick(),
      );
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
    _sessionReady = false;
    _timer?.cancel();
    _timer = null;
    final client = _client;
    _client = null;
    await client?.disconnect();
    role.value = VideoTogetherRole.none;
    isControlling.value = false;
    connectionState.value = VideoTogetherConnectionState.disconnected;
    room.value = null;
    messages.clear();
    _roomName = '';
    _password = '';
    _server = '';
    _memberUserId = '';
    _controlUserId = '';
    _lastNavigationUrl = null;
    _expectedRemoteUrl = null;
    _pendingRoomUpdateTime = null;
    _lastRoomUpdateAt = 0;
    _lastMemberUpdateAt = 0;
    _pendingLocalMediaChange = false;
    _memberLoadingStateChanged = false;
    _resumeAfterLoading = false;
    _hasHeldControl = false;
    _pendingFollowerRoom = null;
    _lastPlaybackSnapshot = null;
    _remotePlaybackSynchronizer.reset();
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
    final previousRoom = room.value;
    final isOwnUpdate =
        method == VideoTogetherProtocol.roomUpdate &&
        _pendingRoomUpdateTime != null &&
        (value.lastUpdateClientTime - _pendingRoomUpdateTime!).abs() < 0.0001;
    room.value = value;
    errorMessage.value = null;

    if (method == VideoTogetherProtocol.roomUpdate) {
      if (isOwnUpdate) {
        role.value = VideoTogetherRole.host;
        isControlling.value = true;
        _hasHeldControl = true;
      } else {
        if (isControlling.value) {
          _remotePlaybackSynchronizer.reset();
        }
        role.value = VideoTogetherRole.member;
        isControlling.value = false;
        _resumeAfterLoading = false;
      }
    } else if (method == VideoTogetherProtocol.memberUpdate &&
        isControlling.value &&
        previousRoom?.waitForLoading != value.waitForLoading) {
      _memberLoadingStateChanged = true;
      unawaited(_tick());
    }

    if (_sessionReady && !isControlling.value) {
      _queueFollowerSync(value);
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
    if (!_running || _tickRunning || _applyingRemoteState) return;
    _tickRunning = true;
    try {
      final client = _client;
      if (client == null || !client.isConnected) {
        await _reconnect();
        return;
      }

      final playback = _playback;
      final now = _localNow();
      final snapshot = playback?.isReady == true
          ? VideoTogetherPlaybackSnapshot.capture(playback!, now)
          : null;
      final hasLocalPlaybackChange =
          snapshot != null &&
          VideoTogetherLocalChangeDetector.hasUserDrivenChange(
            _lastPlaybackSnapshot,
            snapshot,
          );
      final wantsToTakeControl =
          _pendingLocalMediaChange || hasLocalPlaybackChange;
      final canTakeControl = VideoTogetherSyncPolicy.canTakeControl(
        hasHeldControl: _hasHeldControl,
        bidirectionalSync: VideoTogetherPreferences.bidirectionalSync,
      );
      final shouldTakeControl = canTakeControl && wantsToTakeControl;

      if (!canTakeControl && wantsToTakeControl) {
        _pendingLocalMediaChange = false;
      }

      if (shouldTakeControl && playback?.isReady == true && _media != null) {
        if (!isControlling.value) {
          _controlUserId = _newUserId();
          role.value = VideoTogetherRole.host;
          isControlling.value = true;
          _hasHeldControl = true;
        }
        _pendingLocalMediaChange = false;
        await _sendRoomUpdate();
      } else if (isControlling.value) {
        if (_memberLoadingStateChanged || now - _lastRoomUpdateAt >= 1.8) {
          _memberLoadingStateChanged = false;
          await _sendRoomUpdate();
        }
      } else if (room.value case final currentRoom?) {
        if (_syncRunning) {
          _pendingFollowerRoom = currentRoom;
        } else {
          await _syncFollower(currentRoom);
        }
      }
    } catch (error) {
      if (_isAuthorityConflict(error)) {
        role.value = VideoTogetherRole.member;
        isControlling.value = false;
        errorMessage.value = null;
        await _reconnect(forceFollower: true);
      } else {
        errorMessage.value = _friendlyError(error);
      }
    } finally {
      _capturePlaybackSnapshot();
      _tickRunning = false;
    }
  }

  Future<void> _reconnect({bool forceFollower = false}) async {
    if (_reconnectRunning || !_running) return;
    _reconnectRunning = true;
    connectionState.value = VideoTogetherConnectionState.reconnecting;
    try {
      await _client?.disconnect();
      await _connectClient();
      if (forceFollower || !isControlling.value) {
        role.value = VideoTogetherRole.member;
        isControlling.value = false;
        await _joinAsFollower(forceMemberUpdate: true);
      } else {
        try {
          await _sendRoomUpdate();
        } catch (error) {
          if (!_isAuthorityConflict(error)) rethrow;
          role.value = VideoTogetherRole.member;
          isControlling.value = false;
          await _client?.disconnect();
          await _connectClient();
          await _joinAsFollower(forceMemberUpdate: true);
        }
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

  Future<void> _joinAsFollower({bool forceMemberUpdate = false}) async {
    final joinedRoom = await _client!.joinRoom(
      roomName: _roomName,
      password: _password,
    );
    room.value = joinedRoom;
    await _syncFollower(joinedRoom, forceMemberUpdate: forceMemberUpdate);
  }

  Future<void> _sendRoomUpdate() async {
    final client = _client;
    if (client == null || !client.isConnected) return;
    final playback = _playback;
    final currentRoom = room.value;

    final shouldWaitForLoading =
        VideoTogetherPreferences.waitForLoading &&
        currentRoom?.waitForLoading == true;
    if (shouldWaitForLoading &&
        playback?.isReady == true &&
        playback!.isPlaying) {
      _resumeAfterLoading = true;
      await playback.pause();
    } else if (_resumeAfterLoading &&
        !shouldWaitForLoading &&
        playback?.isReady == true) {
      _resumeAfterLoading = false;
      await playback!.play();
    }

    final isReady = playback?.isReady == true;
    final updateTime = client.serverNow;
    final fallbackPosition = currentRoom?.targetPosition(updateTime) ?? 0;
    _pendingRoomUpdateTime = updateTime;
    try {
      final future = client.updateRoom(
        tempUser: _controlUserId,
        password: _password,
        roomName: _roomName,
        playbackRate: isReady
            ? playback!.playbackRate
            : currentRoom?.playbackRate ?? 1,
        currentTime: isReady ? playback!.positionSeconds : fallbackPosition,
        paused: VideoTogetherSyncPolicy.advertisedPaused(
          isReady: isReady,
          isPlaying: isReady && playback!.isPlaying,
          isBuffering: isReady && playback!.isBuffering,
          pausedForMemberLoading: _resumeAfterLoading,
        ),
        url: _media?.url ?? '',
        lastUpdateClientTime: updateTime,
        duration: isReady && playback!.durationSeconds > 0
            ? playback.durationSeconds
            : currentRoom?.duration ?? 1000000000,
        isProtected: VideoTogetherPreferences.passwordProtected,
        videoTitle: _media?.title ?? '',
        waitForResponse: true,
      );
      if (future == null) throw StateError('服务器未确认房间更新');
      room.value = await future;
      _lastRoomUpdateAt = _localNow();
    } finally {
      if (_pendingRoomUpdateTime == updateTime) {
        _pendingRoomUpdateTime = null;
      }
    }
  }

  Future<void> _syncFollower(
    VideoTogetherRoom currentRoom, {
    bool forceMemberUpdate = false,
  }) async {
    final client = _client;
    if (client == null ||
        !client.isConnected ||
        _syncRunning ||
        isControlling.value) {
      return;
    }
    _syncRunning = true;
    try {
      final sameMedia = _isSameMedia(_media?.url, currentRoom.url);
      if (!sameMedia &&
          currentRoom.url.isNotEmpty &&
          VideoTogetherPreferences.autoOpenVideo) {
        await _navigateTo(currentRoom.url);
      }

      final playback = _playback;
      var canSync = false;
      if (playback != null && _isSameMedia(_media?.url, currentRoom.url)) {
        canSync = await _applyRemoteState(playback, currentRoom);
      }

      final now = _localNow();
      if (forceMemberUpdate || now - _lastMemberUpdateAt >= 1.8) {
        client.updateMember(
          roomName: _roomName,
          password: _password,
          userId: _memberUserId,
          isLoading: !canSync || playback!.isBuffering,
          currentUrl: canSync ? currentRoom.url : _media?.url ?? '',
        );
        _lastMemberUpdateAt = now;
      }
    } finally {
      _capturePlaybackSnapshot();
      _syncRunning = false;
      if (_pendingFollowerRoom case final pendingRoom?) {
        _pendingFollowerRoom = null;
        _queueFollowerSync(pendingRoom);
      }
    }
  }

  void _queueFollowerSync(VideoTogetherRoom currentRoom) {
    if (_syncRunning) {
      _pendingFollowerRoom = currentRoom;
      return;
    }
    unawaited(_syncFollower(currentRoom));
  }

  Future<bool> _applyRemoteState(
    VideoTogetherPlayback playback,
    VideoTogetherRoom currentRoom,
  ) async {
    if (_applyingRemoteState) return false;
    _applyingRemoteState = true;
    try {
      return await _remotePlaybackSynchronizer.apply(
        playback: playback,
        room: currentRoom,
        getServerNow: () => _client!.serverNow,
        syncPlaybackRate: VideoTogetherPreferences.syncPlaybackRate,
        waitForLoading: VideoTogetherPreferences.waitForLoading,
        playingThreshold: VideoTogetherPreferences.syncThreshold,
      );
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
    _expectedRemoteUrl = url;
    final handled = await openVideo(url);
    if (!handled) {
      _expectedRemoteUrl = null;
      errorMessage.value = 'PiliPlus 暂不支持房间当前页面：$url';
    }
  }

  void _capturePlaybackSnapshot() {
    final playback = _playback;
    _lastPlaybackSnapshot = playback?.isReady == true
        ? VideoTogetherPlaybackSnapshot.capture(playback!, _localNow())
        : null;
  }

  static bool _isSameMedia(String? local, String remote) {
    if (local == null || local.isEmpty || remote.isEmpty) return false;
    return VideoTogetherMediaIdentity.fromUrl(local)
        .sameAs(VideoTogetherMediaIdentity.fromUrl(remote));
  }

  static bool _isAuthorityConflict(Object error) {
    final text = error.toString();
    return text.contains('其他房主正在同步') || text.contains('Other Host Is Syncing');
  }

  static String _newUserId() => '${const UuidV4().generate()}:${_localNow()}';

  static double _localNow() => DateTime.now().microsecondsSinceEpoch / 1000000;

  static String _friendlyError(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) return error.message ?? '请求超时';
    final text = error.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }
}
