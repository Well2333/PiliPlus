final class VideoTogetherReconnectBackoff {
  static const _delays = <double>[1, 2, 4, 8, 15];

  int _failureCount = 0;
  double _nextAttemptAt = 0;

  int get failureCount => _failureCount;
  double get nextAttemptAt => _nextAttemptAt;

  bool canAttempt(double now, {bool force = false}) =>
      force || now >= _nextAttemptAt;

  Duration registerFailure(double now) {
    final index = _failureCount.clamp(0, _delays.length - 1);
    final delay = _delays[index];
    _failureCount += 1;
    _nextAttemptAt = now + delay;
    return Duration(milliseconds: (delay * 1000).round());
  }

  void reset() {
    _failureCount = 0;
    _nextAttemptAt = 0;
  }
}

abstract final class VideoTogetherConnectionWatchdog {
  static const staleAfter = Duration(seconds: 8);

  static bool isStale({
    required double lastMessageAt,
    required double now,
    Duration timeout = staleAfter,
  }) =>
      lastMessageAt > 0 && now - lastMessageAt >= timeout.inMilliseconds / 1000;
}

abstract final class VideoTogetherLifecyclePolicy {
  static bool shouldSuspend({
    required bool playbackKeepsPlayingInBackground,
  }) => !playbackKeepsPlayingInBackground;
}
