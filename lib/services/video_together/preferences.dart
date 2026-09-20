import 'package:PiliPlus/services/video_together/protocol.dart';
import 'package:PiliPlus/utils/storage.dart';

abstract final class VideoTogetherPreferences {
  static const serverKey = 'videoTogetherServer';
  static const nicknameKey = 'videoTogetherNickname';
  static const autoOpenVideoKey = 'videoTogetherAutoOpenVideo';
  static const syncPlaybackRateKey = 'videoTogetherSyncPlaybackRate';
  static const waitForLoadingKey = 'videoTogetherWaitForLoading';
  static const passwordProtectedKey = 'videoTogetherPasswordProtected';
  static const syncThresholdKey = 'videoTogetherSyncThreshold';
  static const lastRoomNameKey = 'videoTogetherLastRoomName';
  static const hidePlayerMenuEntryKey = 'videoTogetherHidePlayerMenuEntry';

  static String get server => GStorage.setting.get(
    serverKey,
    defaultValue: VideoTogetherProtocol.defaultServer,
  );

  static String get nickname =>
      GStorage.setting.get(nicknameKey, defaultValue: 'PiliPlus 用户');

  static bool get autoOpenVideo =>
      GStorage.setting.get(autoOpenVideoKey, defaultValue: true);

  static bool get syncPlaybackRate =>
      GStorage.setting.get(syncPlaybackRateKey, defaultValue: true);

  static bool get waitForLoading =>
      GStorage.setting.get(waitForLoadingKey, defaultValue: true);

  static bool get passwordProtected =>
      GStorage.setting.get(passwordProtectedKey, defaultValue: true);

  static double get syncThreshold =>
      (GStorage.setting.get(syncThresholdKey, defaultValue: 1.0) as num)
          .toDouble()
          .clamp(0.1, 5.0)
          .toDouble();

  static String get lastRoomName =>
      GStorage.setting.get(lastRoomNameKey, defaultValue: '');

  static bool get hidePlayerMenuEntry =>
      GStorage.setting.get(hidePlayerMenuEntryKey, defaultValue: false);
}
