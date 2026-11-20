import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/streaming.dart';

/// Sezon paketi gibi birden çok video içeren NZB'lerde oynatılacak dosyayı
/// seçtiren diyalog (GitHub issue #5).
///
/// Seçilen adayın `key` değerini döndürür; Geri/vazgeç `null` döner.
/// D-pad: ilk öğe otomatik odaklıdır, yukarı/aşağı listede gezer,
/// DPAD_CENTER seçer; Geri diyalogu kapatır (showDialog varsayılanı).
///
/// [watchedKeys] verildiğinde izlenmiş adaylar onay işareti taşır ve otomatik
/// odak İLK İZLENMEDİK adaya gider; "kaldığın yerden devam" tek tuşla olur.
Future<String?> showPlayableEntryPicker(
  BuildContext context,
  List<PlayableEntryDto> entries, {
  Set<String> watchedKeys = const <String>{},
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _PlayableEntryPickerDialog(entries: entries, watchedKeys: watchedKeys),
  );
}

class _PlayableEntryPickerDialog extends StatelessWidget {
  const _PlayableEntryPickerDialog({
    required this.entries,
    this.watchedKeys = const <String>{},
  });

  final List<PlayableEntryDto> entries;
  final Set<String> watchedKeys;

  /// İlk izlenmedik adayın indeksi; hepsi izlenmişse baştan (yeniden izleme).
  int _firstUnwatchedIndex() {
    for (var index = 0; index < entries.length; index++) {
      if (!watchedKeys.contains(entries[index].key)) return index;
    }
    return 0;
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'direct' => Icons.movie_outlined,
    _ => Icons.inventory_2_outlined,
  };

  static String _kindLabel(AppLocalizations l10n, String kind) =>
      switch (kind) {
        'direct' => l10n.entryKindDirect,
        'probe' => l10n.entryKindArchive,
        // 7z/RAR marka adları çevrilmez.
        _ => kind.toUpperCase(),
      };

  /// GB/MB biçiminde boyut (arama ekranındakiyle aynı kural).
  static String _formatSize(BigInt sizeBytes) {
    final bytes = sizeBytes.toDouble();
    const giga = 1024 * 1024 * 1024;
    const mega = 1024 * 1024;
    if (bytes >= giga) return '${(bytes / giga).toStringAsFixed(1)} GB';
    if (bytes >= mega) return '${(bytes / mega).round()} MB';
    return '<1 MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final firstUnwatched = _firstUnwatchedIndex();
    return AlertDialog(
      title: Text(l10n.entryPickerTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.entryPickerSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final subtitle = StringBuffer(
                    '${_formatSize(entry.encodedBytes)} · '
                    '${_kindLabel(l10n, entry.kind)}',
                  );
                  if (entry.partCount > 1) {
                    subtitle.write(
                      ' · ${l10n.entryParts(entry.partCount.toInt())}',
                    );
                  }
                  return ListTile(
                    // D-pad gezintisi ilk izlenmedik bölümden başlar (issue #4
                    // dersi: otomatik odak yoksa kumandayla diyalog ölü doğar).
                    autofocus: index == firstUnwatched,
                    leading: Icon(_iconFor(entry.kind), size: 20),
                    title: Text(
                      entry.name,
                      // Uzun sürüm adlarında bölüm numarası sonda kalır; tek
                      // satır + kesme onu yuttuğu için iki satıra izin verilir.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      subtitle.toString(),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: watchedKeys.contains(entry.key)
                        ? Tooltip(
                            message: l10n.entryWatchedTooltip,
                            child: Icon(
                              Icons.check_circle,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(entry.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
