import 'package:PiliPlus/services/video_together/models.dart';
import 'package:PiliPlus/services/video_together/playback.dart';
import 'package:PiliPlus/services/video_together/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoTogetherProtocol', () {
    test('maps HTTP server address to official WebSocket endpoint', () {
      expect(
        VideoTogetherProtocol.webSocketUri('https://vt.panghair.com:5000/')
            .toString(),
        'wss://vt.panghair.com:5000/ws?language=zh-cn',
      );
      expect(
        VideoTogetherProtocol.webSocketUri('http://localhost:5001/base/')
            .toString(),
        'ws://localhost:5001/base/ws?language=zh-cn',
      );
    });

    test('rejects unsupported server schemes', () {
      expect(
        () => VideoTogetherProtocol.serverUri('ftp://example.com'),
        throwsFormatException,
      );
      expect(
        () => VideoTogetherProtocol.serverUri('example.com'),
        throwsFormatException,
      );
    });

    test('encodes official member field spelling', () {
      final message = VideoTogetherProtocol.memberUpdateRequest(
        roomName: 'room',
        password: 'password',
        userId: 'user',
        isLoading: true,
        currentUrl: 'https://www.bilibili.com/video/BV1xx',
        sendLocalTimestamp: 10,
      );
      expect(message['method'], '/room/update_member');
      final data = message['data']! as Map<String, dynamic>;
      expect(data['isLoadding'], isTrue);
      expect(data.containsKey('isLoading'), isFalse);
    });

    test('uses NTP-compatible four timestamp calculation', () {
      expect(
        VideoTogetherProtocol.clockOffset(
          localSend: 100,
          serverReceive: 102,
          serverSend: 102.2,
          localReceive: 100.4,
        ),
        closeTo(1.9, 0.000001),
      );
      expect(
        VideoTogetherProtocol.roundTrip(
          localSend: 100,
          serverReceive: 102,
          serverSend: 102.2,
          localReceive: 100.4,
        ),
        closeTo(0.2, 0.000001),
      );
    });
  });

  group('VideoTogetherRoom', () {
    test('parses server values and projects a playing position', () {
      final room = VideoTogetherRoom.fromJson({
        'name': 'room',
        'lastUpdateClientTime': 10,
        'lastUpdateServerTime': 10.1,
        'playbackRate': 1.5,
        'currentTime': 20,
        'paused': false,
        'url': 'https://www.bilibili.com/video/BV1xx',
        'duration': 100,
        'public': false,
        'protected': true,
        'videoTitle': 'title',
        'waitForLoadding': true,
        'memberCount': 2,
      });

      expect(room.waitForLoading, isTrue);
      expect(room.memberCount, 2);
      expect(room.targetPosition(12), closeTo(23, 0.000001));
    });

    test('does not advance paused rooms', () {
      final room = VideoTogetherRoom.fromJson({
        'currentTime': 42,
        'paused': true,
      });
      expect(room.targetPosition(999), 42);
    });
  });

  group('VideoTogetherMediaIdentity', () {
    test('matches the same BV and defaults to first part', () {
      final first = VideoTogetherMediaIdentity.fromUrl(
        'https://www.bilibili.com/video/BV1ABC?spm_id_from=333',
      );
      final second = VideoTogetherMediaIdentity.fromUrl(
        'https://m.bilibili.com/video/bv1abc?p=1',
      );
      expect(first.sameAs(second), isTrue);
    });

    test('distinguishes different parts and episodes', () {
      final partOne = VideoTogetherMediaIdentity.fromUrl(
        'https://www.bilibili.com/video/BV1ABC?p=1',
      );
      final partTwo = VideoTogetherMediaIdentity.fromUrl(
        'https://www.bilibili.com/video/BV1ABC?p=2',
      );
      final episodeOne = VideoTogetherMediaIdentity.fromUrl(
        'https://www.bilibili.com/bangumi/play/ep100',
      );
      final episodeTwo = VideoTogetherMediaIdentity.fromUrl(
        'https://www.bilibili.com/bangumi/play/ep101',
      );
      expect(partOne.sameAs(partTwo), isFalse);
      expect(episodeOne.sameAs(episodeTwo), isFalse);
    });

    test('ignores VideoTogether state parameters for generic URLs', () {
      final first = VideoTogetherMediaIdentity.fromUrl(
        'https://example.com/watch?id=1&VideoTogetherRoomName=room',
      );
      final second = VideoTogetherMediaIdentity.fromUrl(
        'https://example.com/watch?id=1',
      );
      expect(first.sameAs(second), isTrue);
    });

    test('removes ignored-only queries and fragments from generic URLs', () {
      final decorated = VideoTogetherMediaIdentity.fromUrl(
        'https://example.com/watch?VideoTogetherRoomName=room#position',
      );
      final plain = VideoTogetherMediaIdentity.fromUrl(
        'https://example.com/watch',
      );
      expect(decorated.sameAs(plain), isTrue);
    });
  });

  group('VideoTogetherLocalChangeDetector', () {
    VideoTogetherPlaybackSnapshot snapshot({
      required double capturedAt,
      required bool isPlaying,
      required double position,
      double rate = 1,
      bool isBuffering = false,
    }) => VideoTogetherPlaybackSnapshot(
      capturedAt: capturedAt,
      isReady: true,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      positionSeconds: position,
      durationSeconds: 100,
      playbackRate: rate,
    );

    test('does not treat natural playback progress as a local action', () {
      final previous = snapshot(
        capturedAt: 100,
        isPlaying: true,
        position: 10,
      );
      final current = snapshot(
        capturedAt: 100.4,
        isPlaying: true,
        position: 10.4,
      );

      expect(
        VideoTogetherLocalChangeDetector.hasUserDrivenChange(
          previous,
          current,
        ),
        isFalse,
      );
    });

    test('detects play and pause changes', () {
      final previous = snapshot(
        capturedAt: 100,
        isPlaying: true,
        position: 10,
      );
      final current = snapshot(
        capturedAt: 100.2,
        isPlaying: false,
        position: 10.2,
      );

      expect(
        VideoTogetherLocalChangeDetector.hasUserDrivenChange(
          previous,
          current,
        ),
        isTrue,
      );
    });

    test('detects seeks and playback-rate changes', () {
      final previous = snapshot(
        capturedAt: 100,
        isPlaying: true,
        position: 10,
      );
      final seek = snapshot(
        capturedAt: 100.4,
        isPlaying: true,
        position: 20,
      );
      final rate = snapshot(
        capturedAt: 100.4,
        isPlaying: true,
        position: 10.4,
        rate: 2,
      );

      expect(
        VideoTogetherLocalChangeDetector.hasUserDrivenChange(previous, seek),
        isTrue,
      );
      expect(
        VideoTogetherLocalChangeDetector.hasUserDrivenChange(previous, rate),
        isTrue,
      );
    });

    test('ignores buffering transitions', () {
      final previous = snapshot(
        capturedAt: 100,
        isPlaying: true,
        position: 10,
      );
      final buffering = snapshot(
        capturedAt: 100.4,
        isPlaying: false,
        position: 10.1,
        isBuffering: true,
      );

      expect(
        VideoTogetherLocalChangeDetector.hasUserDrivenChange(
          previous,
          buffering,
        ),
        isFalse,
      );

      final resumed = snapshot(
        capturedAt: 100.8,
        isPlaying: true,
        position: 10.2,
      );
      expect(
        VideoTogetherLocalChangeDetector.hasUserDrivenChange(
          buffering,
          resumed,
        ),
        isFalse,
      );
    });
  });
}
