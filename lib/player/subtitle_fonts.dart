import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Altyazı font kataloğu. TTF'ler `assets/fonts/` altında paketlenir (OFL);
/// libmpv/fontconfig'e verilmeden önce uygulama destek dizinine çıkarılır
/// (Android'de fontconfig yok; tüm platformlarda aynı yol kullanılır).
class SubtitleFont {
  const SubtitleFont({
    required this.id,
    required this.asset,
    required this.family,
  });

  /// Tercih deposunda tutulan kimlik (`sans`/`serif`/`mono`).
  final String id;

  /// Paket içi asset yolu.
  final String asset;

  /// Fontun iç aile adı — mpv `sub-font` değeri bu olmalı.
  final String family;
}

/// Birleştirilmiş ana fontlar: Noto Latin glifleri, Arapça shaping ve DejaVu
/// müzik sembolleri tek ailede bulunur. Android'de fontconfig olmadığı için
/// seçilen font bütün karakterleri kendisi taşımalıdır.
const kSubtitleFonts = <SubtitleFont>[
  SubtitleFont(
    id: 'sans',
    asset: 'assets/fonts/subtitle.ttf',
    family: 'Zanzibarr Sans',
  ),
  SubtitleFont(
    id: 'serif',
    asset: 'assets/fonts/subtitle_serif.ttf',
    family: 'Zanzibarr Serif',
  ),
  SubtitleFont(
    id: 'mono',
    asset: 'assets/fonts/subtitle_mono.ttf',
    family: 'Zanzibarr Mono',
  ),
];

/// Fontconfig bulunan platformlar için seçici dışı fallback fontları. Ana
/// birleştirilmiş fontlar zaten Arapça ve sembolleri taşır; bu ham aileler
/// masaüstünde ek glif kapsamı sağlar. Android bunlara güvenmez.
const kSubtitleFallbackFonts = <SubtitleFont>[
  SubtitleFont(
    id: 'arabic_sans',
    asset: 'assets/fonts/subtitle_arabic_sans.ttf',
    family: 'Noto Sans Arabic',
  ),
  SubtitleFont(
    id: 'arabic_serif',
    asset: 'assets/fonts/subtitle_arabic_serif.ttf',
    family: 'Noto Naskh Arabic',
  ),
];

/// Resolver'ın `sub-fonts-dir` dizinine çıkardığı tüm fontlar. Birleştirilmiş
/// ana fontlar Android'de tek başına yeterlidir; fontconfig bulunan
/// platformlarda ham fallback aileleri de aynı dizinde bulunur.
const kSubtitleFontAssets = <SubtitleFont>[
  ...kSubtitleFonts,
  ...kSubtitleFallbackFonts,
];

const kDefaultSubtitleFontId = 'sans';

/// Kimliği bilinen fonta çözer; bilinmeyen kimlik varsayılana düşer.
SubtitleFont subtitleFontFor(String id) {
  for (final font in kSubtitleFonts) {
    if (font.id == id) return font;
  }
  return kSubtitleFonts.first;
}

/// Çözülmüş hedef: mpv `sub-fonts-dir` dizini + `sub-font` aile adı.
class SubtitleFontTarget {
  const SubtitleFontTarget({required this.fontsDir, required this.family});

  final String fontsDir;
  final String family;
}

/// Font asset'lerini diske çıkarıp mpv hedefini üretir. Testlerde sahte
/// uygulama enjekte edilir (asset/disk erişimi olmadan).
abstract class SubtitleFontResolver {
  Future<SubtitleFontTarget> resolve(String id);
}

class AssetSubtitleFontResolver implements SubtitleFontResolver {
  @override
  Future<SubtitleFontTarget> resolve(String id) async {
    final font = subtitleFontFor(id);
    final dir = await _fontsDirectory();
    // Birleştirilmiş ana font Android'de sistem font sağlayıcısı olmadan da
    // Arapça ve sembolleri gösterir. Fontconfig bulunan platformlar için ham
    // fallback ailelerini de aynı dizine çıkarırız.
    for (final assetFont in kSubtitleFontAssets) {
      final file = File('${dir.path}/${assetFont.id}.ttf');
      // Katalog sabit ve asset'ler uygulamayla birlikte sürümlenir; dosya varsa
      // tekrar yazılmaz (boyut kontrolü yeterli — içerik asset ile aynıdır).
      final data = await rootBundle.load(assetFont.asset);
      if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    }
    return SubtitleFontTarget(fontsDir: dir.path, family: font.family);
  }

  Future<Directory> _fontsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/subtitle_fonts');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
