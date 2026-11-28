import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../search/search_screen.dart';
import '../settings/provider_settings.dart';
import 'playback_tab_profile.dart';
import 'player_launcher.dart';
import 'player_screen.dart';

typedef TabPlayerBuilder =
    Widget Function({
      required Key key,
      required String nzbPath,
      String? initialEntryKey,
      required PlaybackTabProfile profile,
      required VoidCallback onRequestClose,
    });

/// Owns the single desktop workspace route. Opening another NZB while the
/// workspace is covered by Home/Search returns to the same route and adds a tab
/// instead of destroying the active player route.
abstract final class PlaybackTabsCoordinator {
  static bool _enabled = false;
  static Route<void>? _route;
  static PlaybackTabsScreenState? _state;

  static bool get isEnabled => _enabled;

  static void enable() => _enabled = true;

  @visibleForTesting
  static void reset() {
    _enabled = false;
    _route = null;
    _state = null;
  }

  static Future<PlaybackTabProfile> _profile() async {
    try {
      final settings = await ProviderSettingsStore().load();
      return PlaybackTabProfile.fromProvider(settings.maxConnections);
    } catch (_) {
      return PlaybackTabProfile.fromProvider(1);
    }
  }

  static Future<void> open(
    BuildContext context,
    String nzbPath, {
    String? entryKey,
  }) async {
    if (!_enabled) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerLauncher.create(
            nzbPath: nzbPath,
            initialEntryKey: entryKey,
          ),
        ),
      );
      return;
    }

    final profile = await _profile();
    if (!context.mounted) return;
    final existing = _state;
    final route = _route;
    if (existing != null && existing.mounted && route != null) {
      existing.addTab(nzbPath, entryKey: entryKey, profile: profile);
      Navigator.of(
        context,
      ).popUntil((candidate) => identical(candidate, route));
      return;
    }

    late final MaterialPageRoute<void> workspaceRoute;
    workspaceRoute = MaterialPageRoute<void>(
      builder: (_) => PlaybackTabsScreen(
        initialNzbPath: nzbPath,
        initialEntryKey: entryKey,
        profile: profile,
      ),
    );
    _route = workspaceRoute;
    await Navigator.of(context).push(workspaceRoute);
    if (identical(_route, workspaceRoute)) {
      _route = null;
    }
  }

  static void _attach(PlaybackTabsScreenState state) => _state = state;

  static void _detach(PlaybackTabsScreenState state) {
    if (identical(_state, state)) _state = null;
  }
}

class PlaybackTabsScreen extends StatefulWidget {
  const PlaybackTabsScreen({
    super.key,
    required this.initialNzbPath,
    required this.profile,
    this.initialEntryKey,
    this.playerBuilder,
    this.titleBuilder,
    this.searchBuilder,
  });

  final String initialNzbPath;
  final String? initialEntryKey;
  final PlaybackTabProfile profile;
  final TabPlayerBuilder? playerBuilder;
  final String Function(String nzbPath)? titleBuilder;
  final WidgetBuilder? searchBuilder;

  @override
  State<PlaybackTabsScreen> createState() => PlaybackTabsScreenState();
}

class _PlaybackTab {
  _PlaybackTab({
    required this.id,
    required this.nzbPath,
    required this.entryKey,
    required this.profile,
    required this.title,
  });

  final int id;
  final String nzbPath;
  final String? entryKey;
  final PlaybackTabProfile profile;
  String title;
  final GlobalKey<State> key = GlobalKey<State>();
}

class PlaybackTabsScreenState extends State<PlaybackTabsScreen> {
  final List<_PlaybackTab> _tabs = [];
  var _selectedIndex = 0;
  var _nextId = 1;

  @override
  void initState() {
    super.initState();
    PlaybackTabsCoordinator._attach(this);
    _addTab(
      widget.initialNzbPath,
      entryKey: widget.initialEntryKey,
      profile: widget.profile,
    );
  }

  @override
  void dispose() {
    PlaybackTabsCoordinator._detach(this);
    super.dispose();
  }

  /// Adds a tab or focuses an existing one for the same NZB/episode.
  void addTab(
    String nzbPath, {
    String? entryKey,
    required PlaybackTabProfile profile,
  }) {
    final duplicateIndex = _tabs.indexWhere(
      (tab) => tab.nzbPath == nzbPath && tab.entryKey == entryKey,
    );
    if (duplicateIndex >= 0) {
      _selectTab(duplicateIndex);
      return;
    }
    if (_tabs.length >= profile.allowedTabs) {
      // A full workspace never silently replaces or kills another session.
      _selectTab(_selectedIndex);
      return;
    }
    _pauseTab(_selectedIndex);
    setState(() {
      _tabs.add(
        _PlaybackTab(
          id: _nextId++,
          nzbPath: nzbPath,
          entryKey: entryKey,
          profile: profile,
          title: widget.titleBuilder?.call(nzbPath) ?? _basename(nzbPath),
        ),
      );
      _selectedIndex = _tabs.length - 1;
    });
  }

  void _addTab(
    String nzbPath, {
    String? entryKey,
    required PlaybackTabProfile profile,
  }) {
    _tabs.add(
      _PlaybackTab(
        id: _nextId++,
        nzbPath: nzbPath,
        entryKey: entryKey,
        profile: profile,
        title: widget.titleBuilder?.call(nzbPath) ?? _basename(nzbPath),
      ),
    );
  }

  static String _basename(String path) =>
      path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;

  void _pauseTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final player = _tabs[index].key.currentState;
    if (player is PlayerScreenState) {
      unawaited(player.pauseForBackground());
    }
  }

  void _resumeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final player = _tabs[index].key.currentState;
    if (player is PlayerScreenState) {
      unawaited(player.resumeForBackground());
    }
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _selectedIndex) return;
    _pauseTab(_selectedIndex);
    setState(() => _selectedIndex = index);
    _resumeTab(index);
  }

  void closeTab(int id) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    final wasSelected = index == _selectedIndex;
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _selectedIndex = 0;
      } else if (index < _selectedIndex) {
        _selectedIndex--;
      } else if (wasSelected) {
        _selectedIndex = _selectedIndex.clamp(0, _tabs.length - 1);
      }
    });
    if (_tabs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else if (wasSelected) {
      _resumeTab(_selectedIndex);
    }
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: widget.searchBuilder ?? (_) => const SearchScreen(),
      ),
    );
  }

  Widget _playerFor(_PlaybackTab tab) {
    final builder = widget.playerBuilder;
    if (builder != null) {
      return builder(
        key: tab.key,
        nzbPath: tab.nzbPath,
        initialEntryKey: tab.entryKey,
        profile: tab.profile,
        onRequestClose: () => closeTab(tab.id),
      );
    }
    return PlayerLauncher.create(
      key: tab.key,
      nzbPath: tab.nzbPath,
      initialEntryKey: tab.entryKey,
      tabProfile: tab.profile,
      onRequestClose: () => closeTab(tab.id),
    );
  }

  Widget _tabButton(_PlaybackTab tab, bool selected) {
    final player = tab.key.currentState;
    if (player is PlayerScreenState) tab.title = player.displayName;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectTab(_tabs.indexOf(tab)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220, minHeight: 38),
            padding: const EdgeInsets.only(left: 12, right: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).closeTabTooltip,
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  onPressed: () => closeTab(tab.id),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            for (var index = 0; index < _tabs.length; index++)
                              _tabButton(_tabs[index], index == _selectedIndex),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context).openInNewTab,
                      onPressed: _openSearch,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [for (final tab in _tabs) _playerFor(tab)],
            ),
          ),
        ],
      ),
    );
  }
}
