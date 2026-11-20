import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/up_next_overlay.dart';
import 'package:zanzibarr/src/rust/api/streaming.dart';

import 'l10n_test_helper.dart';

PlayableEntryDto _entry(String key, String name) => PlayableEntryDto(
  key: key,
  name: name,
  kind: 'direct',
  encodedBytes: BigInt.from(1024),
  partCount: 1,
);

Widget _host(UpNextOverlay overlay) =>
    Scaffold(body: Center(child: overlay));

void main() {
  group('queueAfterEntry', () {
    test('seçilen adaydan sonrakileri doğal sırayla döndürür', () {
      final entries = [
        _entry('direct:e01.mkv', 'e01.mkv'),
        _entry('direct:e02.mkv', 'e02.mkv'),
        _entry('direct:e03.mkv', 'e03.mkv'),
      ];

      final queue = queueAfterEntry(entries, 'direct:e01.mkv');

      expect(
        queue.map((entry) => entry.key),
        ['direct:e02.mkv', 'direct:e03.mkv'],
      );
      // Kaynak liste sonradan değişse de kuyruk değişmez (unmodifiable).
      expect(
        () => queue.add(_entry('direct:e04.mkv', 'e04.mkv')),
        throwsUnsupportedError,
      );
    });

    test('bilinmeyen/son/boş seçimde kuyruk boş döner', () {
      final entries = [
        _entry('direct:e01.mkv', 'e01.mkv'),
        _entry('direct:e02.mkv', 'e02.mkv'),
      ];

      expect(queueAfterEntry(entries, 'direct:yok.mkv'), isEmpty);
      expect(queueAfterEntry(entries, 'direct:e02.mkv'), isEmpty);
      expect(queueAfterEntry(entries, null), isEmpty);
      expect(queueAfterEntry([], 'direct:e01.mkv'), isEmpty);
    });
  });

  group('UpNextOverlay', () {
    testWidgets('başlığı, bölüm adını ve kalan süreyi gösterir', (
      tester,
    ) async {
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'dizi.s01e02.mkv',
            onPlayNow: () {},
            onCancel: () {},
            onClearQueue: () {},
          ),
        ),
      );

      expect(find.text('Sıradaki bölüm'), findsOneWidget);
      expect(find.text('dizi.s01e02.mkv'), findsOneWidget);
      expect(find.text('10 sn içinde başlıyor'), findsOneWidget);
    });

    testWidgets('"Şimdi oynat" geçişi hemen tetikler', (tester) async {
      var played = false;
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'e02.mkv',
            onPlayNow: () => played = true,
            onCancel: () {},
            onClearQueue: () {},
          ),
        ),
      );

      await tester.tap(find.text('Şimdi oynat'));
      await tester.pump();

      expect(played, isTrue);
    });

    testWidgets('"Bölümü bitir" otomatik geçişi iptal eder', (tester) async {
      var played = false;
      var cancelled = false;
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'e02.mkv',
            onPlayNow: () => played = true,
            onCancel: () => cancelled = true,
            onClearQueue: () {},
          ),
        ),
      );

      await tester.tap(find.text('Bölümü bitir'));
      await tester.pump();

      expect(cancelled, isTrue);
      expect(played, isFalse);
    });

    testWidgets('"Kuyruğu temizle" kuyruk kapışma eylemini tetikler', (
      tester,
    ) async {
      var cleared = false;
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'e02.mkv',
            onPlayNow: () {},
            onCancel: () {},
            onClearQueue: () => cleared = true,
          ),
        ),
      );

      await tester.tap(find.text('Kuyruğu temizle'));
      await tester.pump();

      expect(cleared, isTrue);
    });

    testWidgets('geri sayım bittiğinde otomatik geçiş yapılır', (tester) async {
      var played = false;
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'e02.mkv',
            onPlayNow: () => played = true,
            onCancel: () {},
            onClearQueue: () {},
          ),
        ),
      );

      expect(find.text('10 sn içinde başlıyor'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('7 sn içinde başlıyor'), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));

      expect(played, isTrue);
    });

    testWidgets('Esc kartı kapatır (geri sayım iptal)', (tester) async {
      var cancelled = false;
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'e02.mkv',
            onPlayNow: () {},
            onCancel: () => cancelled = true,
            onClearQueue: () {},
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('TV geri tuşu (goBack) da iptal eder', (tester) async {
      var cancelled = false;
      await tester.pumpWithL10n(
        _host(
          UpNextOverlay(
            entryName: 'e02.mkv',
            onPlayNow: () {},
            onCancel: () => cancelled = true,
            onClearQueue: () {},
          ),
        ),
      );

      // TV'nin Geri tuşu mantıksal goBack'e karşılık gelir; test altyapısı
      // fiziksel tuşu escape üzerinden ister (player_keyboard_controls_test
      // eşlemesi).
      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();

      expect(cancelled, isTrue);
    });
  });
}
