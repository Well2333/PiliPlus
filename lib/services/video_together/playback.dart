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
