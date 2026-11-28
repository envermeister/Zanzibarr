import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zanzibarr/player/playback_tab_profile.dart';
import 'package:zanzibarr/player/playback_tabs.dart';

import 'l10n_test_helper.dart';

class _FakePlayer extends StatefulWidget {
  const _FakePlayer({
    super.key,
    required this.name,
    required this.onClose,
    required this.onDispose,
  });

  final String name;
  final VoidCallback onClose;
  final ValueChanged<String> onDispose;

  @override
  State<_FakePlayer> createState() => _FakePlayerState();
}

class _FakePlayerState extends State<_FakePlayer> {
  @override
  void dispose() {
    widget.onDispose(widget.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.name));
}

void _noop() {}

TabPlayerBuilder _fakeBuilder(List<String> disposed) =>
    ({
      required key,
      required nzbPath,
      initialEntryKey,
      profile = const PlaybackTabProfile(allowedTabs: 4, maxConnections: 2),
      onRequestClose = _noop,
    }) {
      final name = nzbPath.split('/').last;
      return _FakePlayer(
        key: key,
        name: name,
        onClose: onRequestClose,
        onDispose: disposed.add,
      );
    };

PlaybackTabProfile _profile([int maxConnections = 8]) =>
    PlaybackTabProfile.fromProvider(maxConnections);

void main() {
  test('connection budget is shared without rewriting provider settings', () {
    expect(_profile(60).allowedTabs, 4);
    expect(_profile(60).maxConnections, 15);
    expect(_profile(4).allowedTabs, 4);
    expect(_profile(4).maxConnections, 1);
    expect(_profile(3).allowedTabs, 3);
    expect(_profile(3).maxConnections, 1);
    expect(_profile(2).allowedTabs, 2);
    expect(_profile(2).maxConnections, 1);
    expect(_profile(1).allowedTabs, 1);
    expect(_profile(1).maxConnections, 1);
    expect(_profile(0).allowedTabs, 1);
    expect(_profile(0).maxConnections, 1);
  });

  testWidgets(
    'tabs preserve independent state and dispose only the closed tab',
    (tester) async {
      final disposed = <String>[];
      late PlaybackTabsScreenState workspace;
      await tester.pumpWithL10n(
        PlaybackTabsScreen(
          initialNzbPath: '/tmp/a.nzb',
          profile: _profile(),
          playerBuilder: _fakeBuilder(disposed),
        ),
      );
      workspace = tester.state<PlaybackTabsScreenState>(
        find.byType(PlaybackTabsScreen),
      );

      expect(find.widgetWithText(_FakePlayer, 'a.nzb'), findsOneWidget);
      workspace.addTab('/tmp/b.nzb', profile: _profile());
      await tester.pump();
      expect(find.widgetWithText(_FakePlayer, 'b.nzb'), findsOneWidget);
      expect(disposed, isEmpty);

      // Duplicate NZB focuses the existing session instead of racing history.
      workspace.addTab('/tmp/b.nzb', profile: _profile());
      await tester.pump();
      expect(find.widgetWithText(_FakePlayer, 'b.nzb'), findsOneWidget);
      expect(disposed, isEmpty);

      workspace.closeTab(2);
      await tester.pump();
      expect(disposed, ['b.nzb']);
      expect(find.widgetWithText(_FakePlayer, 'a.nzb'), findsOneWidget);

      workspace.closeTab(1);
      await tester.pump();
      expect(disposed, ['b.nzb', 'a.nzb']);
    },
  );

  testWidgets('full workspace never replaces another session', (tester) async {
    final disposed = <String>[];
    late PlaybackTabsScreenState workspace;
    await tester.pumpWithL10n(
      PlaybackTabsScreen(
        initialNzbPath: '/tmp/a.nzb',
        profile: _profile(2),
        playerBuilder: _fakeBuilder(disposed),
      ),
    );
    workspace = tester.state<PlaybackTabsScreenState>(
      find.byType(PlaybackTabsScreen),
    );
    workspace.addTab('/tmp/b.nzb', profile: _profile(2));
    workspace.addTab('/tmp/c.nzb', profile: _profile(2));
    await tester.pump();

    expect(find.text('a.nzb'), findsOneWidget);
    expect(find.widgetWithText(_FakePlayer, 'b.nzb'), findsOneWidget);
    expect(find.text('c.nzb'), findsNothing);
    expect(disposed, isEmpty);
  });
}
