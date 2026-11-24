#!/usr/bin/env python3
"""Build Android-safe subtitle fonts with Arabic shaping and Latin/symbol glyphs.

Android's libass build has no system font provider/fontconfig, so a second
fallback file cannot fill missing glyphs. These merged fonts keep every glyph
ID from the Arabic base (and therefore its GSUB/GPOS/GDEF shaping tables) and
append the Latin/symbol glyphs after them. Run from the repository root with a
Python environment containing fontTools:

    python3 tools/build_subtitle_fonts.py

Source fonts remain unchanged in tools/font_sources/. Noto fonts use the OFL in
assets/fonts/OFL.txt; DejaVu's license is assets/fonts/DejaVu-LICENSE.txt.
"""

from copy import deepcopy
from pathlib import Path

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "tools" / "font_sources"
OUTPUT = ROOT / "assets" / "fonts"
MUSIC_CODEPOINTS = (0x2669, 0x266A, 0x266B, 0x266C)


def append_glyphs(base, donor, prefix, only_codepoints=None):
    """Append donor glyphs without changing any existing base glyph ID."""
    base_cmap = base["cmap"].getBestCmap()
    donor_cmap = donor["cmap"].getBestCmap()
    allowed = set(donor_cmap) if only_codepoints is None else set(only_codepoints)
    donor_names = sorted(
        {donor_cmap[cp] for cp in allowed if cp in donor_cmap},
        key=donor.getGlyphID,
    )
    if only_codepoints is None:
        donor_names = donor.getGlyphOrder()

    order = base.getGlyphOrder()
    name_map = {}
    for index, old_name in enumerate(donor_names):
        new_name = f"{prefix}{index}"
        assert new_name not in order
        name_map[old_name] = new_name
        order.append(new_name)

    for old_name, new_name in name_map.items():
        glyph = deepcopy(donor["glyf"][old_name])
        if glyph.isComposite():
            glyph.expand(donor["glyf"])
            for component in glyph.components:
                component.glyphName = name_map[component.glyphName]
        base["glyf"][new_name] = glyph
        base["hmtx"].metrics[new_name] = donor["hmtx"].metrics[old_name]

    additions = {}
    for cp, old_name in donor_cmap.items():
        if cp not in allowed or cp in base_cmap:
            continue
        additions[cp] = name_map[old_name]
    for table in base["cmap"].tables:
        if not table.isUnicode() or table.format not in (4, 12):
            continue
        for cp, new_name in additions.items():
            if table.format == 4 and cp > 0xFFFF:
                continue
            table.cmap[cp] = new_name

    for table_name in ("ulUnicodeRange1", "ulUnicodeRange2", "ulUnicodeRange3", "ulUnicodeRange4"):
        if hasattr(base["OS/2"], table_name) and hasattr(donor["OS/2"], table_name):
            setattr(
                base["OS/2"],
                table_name,
                getattr(base["OS/2"], table_name) | getattr(donor["OS/2"], table_name),
            )

    base.setGlyphOrder(order)
    base["maxp"].numGlyphs = len(order)
    base["hhea"].numberOfHMetrics = len(order)
    base["head"].recalcBBoxes = True


def rename_family(font, family):
    full_name = f"{family} Regular"
    postscript_name = f"{family.replace(' ', '')}-Regular"
    for record in font["name"].names:
        if record.nameID in (1, 16):
            record.string = family.encode(record.getEncoding())
        elif record.nameID == 4:
            record.string = full_name.encode(record.getEncoding())
        elif record.nameID == 6:
            record.string = postscript_name.encode(record.getEncoding())


def build(base_name, latin_name, symbol_name, output_name, family):
    base = TTFont(SOURCES / base_name)
    append_glyphs(base, TTFont(SOURCES / latin_name), "latin")
    append_glyphs(base, TTFont(SOURCES / symbol_name), "symbol", MUSIC_CODEPOINTS)
    rename_family(base, family)
    # Keep rebuilds byte-for-byte reproducible; fontTools otherwise updates
    # head.modified to the current time on every save.
    base.recalcTimestamp = False
    base["head"].created = 0
    base["head"].modified = 0
    output = OUTPUT / output_name
    base.save(output)
    print(f"Built {output.relative_to(ROOT)} ({base['maxp'].numGlyphs} glyphs, {family})")


def main():
    build(
        "subtitle_arabic_sans.ttf",
        "subtitle.ttf",
        "DejaVuSans.ttf",
        "subtitle.ttf",
        "Zanzibarr Sans",
    )
    build(
        "subtitle_arabic_serif.ttf",
        "subtitle_serif.ttf",
        "DejaVuSerif.ttf",
        "subtitle_serif.ttf",
        "Zanzibarr Serif",
    )
    build(
        "subtitle_arabic_sans.ttf",
        "subtitle_mono.ttf",
        "DejaVuSansMono.ttf",
        "subtitle_mono.ttf",
        "Zanzibarr Mono",
    )


if __name__ == "__main__":
    main()
