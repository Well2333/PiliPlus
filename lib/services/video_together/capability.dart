abstract final class VideoTogetherCapability {
  static const nicknameSuffix = '[piliplus]';
  static const _clientIdSeparator = '\u2063';

  static String editableNickname(String value) {
    var nickname = value.trim();
    if (isPiliPlusNickname(nickname)) {
      nickname = nickname.substring(0, nickname.length - nicknameSuffix.length);
    }
    final separatorIndex = nickname.lastIndexOf(_clientIdSeparator);
    if (separatorIndex >= 0) {
      nickname = nickname.substring(0, separatorIndex);
    }
    return nickname.trim();
  }

  static String protocolNickname({
    required String nickname,
    required String clientId,
    required bool enabled,
  }) {
    final editable = editableNickname(nickname);
    final base = editable.isEmpty ? 'PiliPlus 用户' : editable;
    if (!enabled) return base;
    return '$base$_clientIdSeparator$clientId$nicknameSuffix';
  }

  static bool isPiliPlusNickname(String value) =>
      value.trim().toLowerCase().endsWith(nicknameSuffix);

  static String displayNickname(String value) {
    final nickname = value.trim();
    if (!isPiliPlusNickname(nickname)) return nickname;
    final withoutSuffix = nickname.substring(
      0,
      nickname.length - nicknameSuffix.length,
    );
    final separatorIndex = withoutSuffix.lastIndexOf(_clientIdSeparator);
    final base = separatorIndex >= 0
        ? withoutSuffix.substring(0, separatorIndex)
        : withoutSuffix;
    return '${base.trim()}$nicknameSuffix';
  }

  static String? clientId(String value) {
    final nickname = value.trim();
    if (!isPiliPlusNickname(nickname)) return null;
    final withoutSuffix = nickname.substring(
      0,
      nickname.length - nicknameSuffix.length,
    );
    final separatorIndex = withoutSuffix.lastIndexOf(_clientIdSeparator);
    if (separatorIndex < 0) return nickname.toLowerCase();
    final id = withoutSuffix.substring(separatorIndex + 1).trim();
    return id.isEmpty ? nickname.toLowerCase() : id;
  }

  static bool effectiveBidirectionalSync({
    required bool configured,
    required bool allParticipantsPiliPlus,
  }) => configured || allParticipantsPiliPlus;
}

final class VideoTogetherPresenceTracker {
  final Set<String> _clientIds = <String>{};
  int _memberCount = 0;

  int get recognizedCount => _clientIds.length;
  bool get allParticipantsRecognized =>
      _memberCount > 0 && _clientIds.length == _memberCount;

  bool updateMemberCount(int value) {
    final normalized = value < 0 ? 0 : value;
    if (_memberCount == normalized) return false;
    _memberCount = normalized;
    _clientIds.clear();
    return true;
  }

  bool register(String sender) {
    final id = VideoTogetherCapability.clientId(sender);
    return id != null && _clientIds.add(id);
  }

  void clear() {
    _memberCount = 0;
    _clientIds.clear();
  }
}

abstract final class VideoTogetherPlayerEntryPolicy {
  static bool shouldShow({
    required bool inRoom,
    required bool hideWhenNotInRoom,
  }) => inRoom || !hideWhenNotInRoom;
}
