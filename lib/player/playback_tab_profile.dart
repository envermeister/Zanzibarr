/// Resource budget assigned to each player in the desktop tab workspace.
///
/// The provider setting is never rewritten. Every tab receives a deterministic
/// share of the saved connection limit, so N tabs cannot create N× the saved
/// number of NNTP connections.
class PlaybackTabProfile {
  const PlaybackTabProfile({
    required this.allowedTabs,
    required this.maxConnections,
  });

  factory PlaybackTabProfile.fromProvider(int providerMaxConnections) {
    final saved = providerMaxConnections < 1 ? 1 : providerMaxConnections;
    final allowedTabs = saved < 4 ? saved : 4;
    return PlaybackTabProfile(
      allowedTabs: allowedTabs,
      maxConnections: saved ~/ allowedTabs,
    );
  }

  /// Maximum number of simultaneous tabs allowed by the provider limit.
  final int allowedTabs;

  /// Per-tab NNTP pool limit used by PlayerScreen.
  final int maxConnections;
}
