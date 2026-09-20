abstract interface class VideoTogetherPlayback {
  bool get isReady;
  bool get isPlaying;
  bool get isBuffering;
  double get positionSeconds;
  double get durationSeconds;
  double get playbackRate;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(double seconds);
  Future<void> setPlaybackRate(double rate);
}

abstract final class VideoTogetherSyncPolicy {
  static const pausedCorrectionThreshold = 0.1;

  static bool canTakeControl({
    required bool hasHeldControl,
    required bool bidirectionalSync,
  }) => bidirectionalSync || hasHeldControl;

  static double correctionThreshold({
    required bool roomPaused,
    required double playingThreshold,
  }) => roomPaused ? pausedCorrectionThreshold : playingThreshold;

  static bool shouldPauseForMemberLoading({
    required bool waitForLoadingEnabled,
    required bool roomWaitsForLoading,
    required bool roomPaused,
    required bool localBuffering,
  }) =>
      waitForLoadingEnabled &&
      roomWaitsForLoading &&
      !roomPaused &&
      !localBuffering;

  static bool advertisedPaused({
    required bool isReady,
    required bool isPlaying,
    required bool isBuffering,
    required bool pausedForMemberLoading,
  }) => !isReady || (!pausedForMemberLoading && (!isPlaying || isBuffering));
}

final class VideoTogetherPlaybackSnapshot {
  const VideoTogetherPlaybackSnapshot({
    required this.capturedAt,
    required this.isReady,
    required this.isPlaying,
    required this.isBuffering,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.playbackRate,
  });

  factory VideoTogetherPlaybackSnapshot.capture(
    VideoTogetherPlayback playback,
    double capturedAt,
  ) => VideoTogetherPlaybackSnapshot(
    capturedAt: capturedAt,
    isReady: playback.isReady,
    isPlaying: playback.isPlaying,
    isBuffering: playback.isBuffering,
    positionSeconds: playback.positionSeconds,
    durationSeconds: playback.durationSeconds,
    playbackRate: playback.playbackRate,
  );

  final double capturedAt;
  final bool isReady;
  final bool isPlaying;
  final bool isBuffering;
  final double positionSeconds;
  final double durationSeconds;
  final double playbackRate;
}

abstract final class VideoTogetherLocalChangeDetector {
  static bool hasUserDrivenChange(
    VideoTogetherPlaybackSnapshot? previous,
    VideoTogetherPlaybackSnapshot current, {
    double seekThreshold = 0.75,
  }) {
    if (previous == null ||
        !previous.isReady ||
        !current.isReady ||
        previous.isBuffering ||
        current.isBuffering) {
      return false;
    }

    if (previous.isPlaying != current.isPlaying) {
      final endedNormally =
          !current.isPlaying &&
          current.durationSeconds > 0 &&
          current.positionSeconds >= current.durationSeconds - 0.5;
      if (!endedNormally) return true;
    }

    if ((previous.playbackRate - current.playbackRate).abs() > 0.01) {
      return true;
    }

    final elapsed = (current.capturedAt - previous.capturedAt).clamp(
      0,
      double.infinity,
    );
    final expectedPosition =
        previous.positionSeconds +
        (previous.isPlaying && !previous.isBuffering
            ? elapsed * previous.playbackRate
            : 0);
    return (current.positionSeconds - expectedPosition).abs() >= seekThreshold;
  }
}
