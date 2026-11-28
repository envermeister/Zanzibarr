import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/browser_stream.dart';

void main() {
  test('active loopback stream opens exactly once', () async {
    Uri? opened;
    final result = await openStreamInBrowser(
      streamUrl: 'http://127.0.0.1:43210/movie.mkv',
      launcher: (uri) async {
        opened = uri;
        return true;
      },
    );

    expect(result, isTrue);
    expect(opened?.scheme, 'http');
    expect(opened?.host, '127.0.0.1');
    expect(opened?.port, 43210);
    expect(opened?.path, '/movie.mkv');
  });

  test('null, LAN, cast-token and non-loopback URLs are rejected', () async {
    var calls = 0;
    for (final url in [
      null,
      'http://192.168.1.20:43210/cast/secret/movie.mkv',
      'http://localhost:43210/movie.mkv',
      'https://127.0.0.1:43210/movie.mkv',
      'https://example.com/movie.mkv',
    ]) {
      final result = await openStreamInBrowser(
        streamUrl: url,
        launcher: (_) async {
          calls++;
          return true;
        },
      );
      expect(result, isFalse);
    }
    expect(calls, 0);
  });

  test('launcher false and exceptions remain visible to the caller', () async {
    expect(
      () => openStreamInBrowser(
        streamUrl: 'http://127.0.0.1:43210/movie.mkv',
        launcher: (_) async => false,
      ),
      throwsStateError,
    );
    expect(
      () => openStreamInBrowser(
        streamUrl: 'http://127.0.0.1:43210/movie.mkv',
        launcher: (_) async => throw Exception('no browser'),
      ),
      throwsException,
    );
  });
}
