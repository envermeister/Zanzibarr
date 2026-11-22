# Building Zanzibarr for Samsung Tizen and LG webOS

Zanzibarr's native TV entrypoints target Samsung Tizen TV and LG webOS 26 Re:New+. Preview packages are published in the v2.0 release while main continues as v2.1. The desktop/mobile media_kit player is unchanged. TV builds use the official native `video_player` implementations and the same Rust NZB/NNTP/archive/range-server engine as every other platform.

This document records the four upstream references used for the port, their distinct requirements, and Zanzibarr's build/verification model.

## 1. Samsung: Flutter for Tizen

Reference: <https://developer.samsung.com/smarttv/develop/native/flutter.html>

What the guide establishes:

- Flutter apps are supported on **Samsung Smart TVs running Tizen 6.0 or later** (2021 model year onward).
- A TV application is packaged as a **`.tpk`** using `flutter-tizen build tpk -ptv`.
- TV input must work with the remote's keyboard-mapped keys. Focus visibility matters: the default focus blur may be insufficient, so the app needs an explicit focus treatment.
- For **2026 TV models, the 2026 SDK is required**. Native libraries and prebuilt plugin libraries must be compatible with the toolchain change from **GCC 9.2 to GCC 14.2**. Building only with an old sysroot is not a valid 2026 compatibility claim.
- `video_player_tizen` is the recommended playback plugin. Distribution is through Samsung Apps TV Seller Office; real-device testing is required before submission.

Zanzibarr's mapping:

- `tizen/tizen-manifest.xml` targets the Tizen 6.0 API line; `tizen/tizen-manifest-10.0.xml` targets the 2026 line. `tools/build_tizen.sh` selects the manifest, GCC version and sysroot together. For 2026, the public `tizen` rootstrap (`tizen-10.0-device.core`) is used because `tv-samsung` is not publicly available; this matches flutter-tizen's own fallback logic.
- The existing visible D-pad focus style and `PlayerKeyboardControls` are reused. No touchscreen-only interaction is required for search, settings or playback.
- The Tizen build uses `video_player_tizen` and its Tizen Media Player implementation. It supports seek, speed, volume and audio-track enumeration/selection. Seeking is nearest-keyframe and works at 1× speed, matching the plugin's documented limitation.
- The Tizen plugin **does not support TV emulators**, so successful packaging is not a substitute for a real Samsung TV test.

## 2. Samsung Research: flutter-tizen repository

Reference: <https://github.com/flutter-tizen/flutter-tizen>

What the repository adds:

- Supported targets are Smart TV Tizen 6.0+ and selected IoT devices; Galaxy Watch is no longer a target.
- The CLI substitutes for the standard `flutter` command. `create`, `run`, `build`, `doctor` and `precache` are the normal development flow.
- macOS is supported, but Apple Silicon requires Rosetta. A current installation uses **.NET**, the Tizen VS Code extension/SDK, and the Tizen native rootstrap. Tizen Studio is deprecated; the extension is the recommended installation path. An Apple Silicon TV emulator is not available.
- Tizen packages have `tizen-manifest.xml`, app/package IDs and privileges. Release TPKs must be signed with a valid certificate profile. The publishing guide explicitly requires testing on a real device.
- The plugin repository supplies `video_player_tizen`, `flutter_secure_storage_tizen`, `path_provider_tizen`, `package_info_plus_tizen` and `url_launcher_tizen`. These are non-endorsed platform implementations, so both the frontend package and its Tizen implementation are declared in the TV dependency profile.
- Flutter-Tizen can bundle native shared objects under the app's flat `lib/` directory. Its native-assets documentation maps Tizen runtime architecture to Linux, but the compiler/sysroot still must be the Tizen one rather than the host Linux compiler.

Zanzibarr's mapping:

- `tools/prepare_tv_workdir.sh` creates an isolated Tizen source copy. `tools/configure_tv_pubspec.py` removes media_kit/libmpv and native-only sources, then pins the Tizen plugin set.
- The engine is built as `armv7-unknown-linux-gnueabi/release/librust_lib_zanzibarr.so` using Samsung GCC and rootstrap, then copied to `tizen/lib/` before `build tpk`. The target `libstdc++.a` reported by that GCC is placed in an archive-only native search directory. This makes both unrar's build-script and Rust `#[link]` records select the static archive regardless of rustc's link-argument order; `-static-libstdc++` alone is not sufficient with rustc's `-nodefaultlibs` link.
- Tizen's dynamic loader can be sensitive to library search paths. `lib/engine/native_engine_loader.dart` therefore uses `AUL_ROOT_PATH/lib/librust_lib_zanzibarr.so` when available, with FRB's normal loader as fallback.
- The CI-only certificate uses `TESTPASS123`; it is not the owner's production certificate and is never embedded in source or release notes.

## 3. LG: Flutter for webOS guide

Reference: <https://webostv.developer.lge.com/develop/guides/flutter-for-webos>

What the guide establishes:

- **Only Ubuntu is an officially supported host** (22.04, 24.04 and 26.04). macOS/Windows developers must use a compatible environment such as the official Dev Container.
- The target is **webOS 26 Re:New or later**. This is not a generic older-webOS application path. Developer Mode is required for deployment.
- Build and packaging produce an **`.ipk`** at `build/webos/{arch}/{mode}/ipk/{id}_{version}_{arch}.ipk` with debug/profile/release modes.
- The NDK is **11.2.0**. `WEBOS_FLUTTER_NDK_ENV` points to its environment-setup script, which must be sourced before native builds. Engine artifacts are pre-cached with `flutter-webos precache`.
- `ares >= 3.2.4` is required for packaging/deployment. The guide lists Node.js 14.15.1–16.20.2, but the current `@webos-tools/cli` has moved to **Node.js >= 20**; Zanzibarr CI therefore uses the current Node.js 24 LTS rather than the outdated range.
- Luna Service calls are governed by ACG. Zanzibarr's raw NNTP/HTTP traffic does not require an extra Luna service or ACG group.
- The official `video_player_webos` plugin uses the platform video plane. The Flutter surface must be transparent. This release supports at most five concurrent pipelines, does not support per-stream `setVolume`, and does not support HTTP headers. Zanzibarr's loopback range server does not need custom headers.

Zanzibarr's mapping:

- `webos/meta/appinfo.json` sets `"type": "native"` and **`"transparent": true`** so the video plane is visible beneath Flutter controls.
- `tools/build_webos.sh` refuses to run on non-Linux hosts. CI uses Ubuntu 24.04; macOS developers can use LG's `linux/amd64` Dev Container.
- The NDK license is explicit. The owner approved it for this build; CI sets `WEBOS_NDK_ACCEPT_EULA=1` only as a consequence of that approval. No silent license acceptance is encoded as a default recommendation for other developers.
- webOS audio uses the platform default track and system-wide volume controls. Zanzibarr does not pretend that per-stream volume or audio-track selection is available there.
- `video_player_webos`, secure storage, path provider, package info and URL launcher dependencies are pinned to a reviewed plugin commit, not an unpinned moving branch.

## 4. LG: flutter-webos repository

Reference: <https://github.com/lg-flutter-webos/flutter-webos>

What the repository adds:

- `flutter-webos doctor`, `precache`, `devices`, `create --platforms webos`, `build webos --release` and `run` are the supported workflow.
- Engine artifacts can be overridden with `WEBOS_ENGINE_BASE_URL`; the default public release host is sufficient for Zanzibarr.
- The build uses the LG webOS NDK environment for native compilation. It is not a host-macOS compiler path.
- Native plugins can be declared with `ffiPlugin: true`. Their `<plugin>_bundled_libraries` lists are installed into `bundle/lib`; the runner's RPATH includes `$ORIGIN` and `$ORIGIN/lib`.
- `meta/flutter-conf.json` selects application data/cache locations and can enable Impeller. Zanzibarr retains the default Skia path rather than changing rendering engines without a device test.
- The webOS build graph assembles native application packages; adding a library through the plugin bundle mechanism is preferable to ad-hoc copying after installation.

Zanzibarr's mapping:

- `rust_builder/pubspec.yaml` declares webOS as an FFI platform.
- `rust_builder/webos/CMakeLists.txt` publishes `rust_lib_zanzibarr_bundled_libraries` for the engine and its matching C++ runtime under `lib/`.
- `tools/build_webos.sh` sources the LG environment and uses NDK G++ for unrar and final linking. This avoids mixing Clang's optional `libc++` flags with the NDK's generic GNU `stdc++` linkage.
- The native engine uses the NDK's exact `libstdc++.so.6`, bundled next to the engine with an `$ORIGIN` RPATH (both files are already inside `lib/`). The LG NDK does not ship a static `libstdc++.a`, so forcing static C++ linkage is not an option. Shipping the matching runtime avoids both missing GLIBCXX symbols and accidentally selecting an older system runtime. The runtime is explicitly listed in `rust_lib_zanzibarr_bundled_libraries`; copying it into the source directory alone does not install it into the IPK.

## Rust and playback architecture

Both TV targets use **`armv7-unknown-linux-gnueabi`**, the 32-bit ARM softfp ABI: floating-point instructions are allowed, but arguments use the soft-float calling convention. They are not hard-float `gnueabihf` builds.

The shared streaming chain is preserved:

```
NZB → Rust parser/segment map → NNTP pool (TLS) → yEnc + CRC
    → RAR/7z/PAR2 layers → localhost Range server → native TV video_player
```

The engine still fetches only watched ranges. The native player—not Flutter—determines codec and hardware-decoder support. No extra media fetch is introduced for the health pre-check, queue setup or HDR detection.

## Feature matrix

| Capability | Tizen | webOS 26 Re:New+ |
|---|---|---|
| Built-in Newznab/Prowlarr/Hydra/Easynews search | Yes | Yes |
| NZB health pre-check | Yes | Yes |
| RAR/7z/PAR2 engine and lazy Range streaming | Yes | Yes |
| Native seek/play-pause/rate | Yes | Yes |
| Episode picker, queue, Up next and history | Yes | Yes |
| Secure storage | `flutter_secure_storage_tizen` | `flutter_secure_storage_webos` |
| Audio-track selection and saved language | Yes | Platform default track |
| Per-stream volume | Yes | System-wide volume |
| OpenSubtitles SRT/WebVTT rendered by Flutter | Yes | Yes |
| D-pad navigation | Yes | Yes |
| Local NZB file picker | Not in this TV profile | Not in this TV profile |
| Smart Canvas / libmpv-only filters | Not available | Not available |
| Custom libmpv Dolby Vision Profile 5 reshape | Not claimed | Not claimed |
| PiP / casting from the TV app | Not in this TV profile | Not in this TV profile |
| TV emulator playback | Not supported by `video_player_tizen` | Real webOS TV required |

Native codecs, HDR and audio formats are determined by the TV and its media subsystem. TrueHD/DTS-HD/Dolby Vision support must not be inferred from the custom libmpv builds used on other platforms.

## Build and verify

### Tizen

Prerequisites: Tizen SDK/rootstrap, .NET, `flutter-tizen`, an active signing profile and Rust. On Apple Silicon, Samsung's host tools run under Rosetta; their x86_64 Homebrew dependencies must also be present (GCC 9.2 expects `libisl.19`, while GCC 14.2 expects `libisl.23`, `libintl.8` and `libzstd.1`). Ubuntu CI does not need those macOS host libraries.

```bash
export TIZEN_SDK=/path/to/tizen-studio
export FLUTTER_TIZEN_HOME=/path/to/flutter-tizen
export PATH="$FLUTTER_TIZEN_HOME/bin:$PATH"

tools/build_tizen.sh 6.0
tools/verify_tv_package.sh tizen dist/tizen/zanzibarr-tizen-6.0-arm.tpk

# 2026 models — requires the GCC 14.2/Tizen 10 SDK line
tools/build_tizen.sh 10.0
tools/verify_tv_package.sh tizen dist/tizen/zanzibarr-tizen-10.0-arm.tpk
```

`TIZEN_TOOLCHAIN` and `TIZEN_SYSROOT` can override auto-detected paths. The script fails early if they are absent rather than silently producing an incompatible TPK.

### webOS

Prerequisites: Ubuntu, `flutter-webos`, ares, LG NDK 11.2.0 and the owner's explicit NDK license approval.

```bash
export FLUTTER_WEBOS_HOME=/path/to/flutter-webos
export PATH="$FLUTTER_WEBOS_HOME/bin:$PATH"
export WEBOS_FLUTTER_NDK_ENV=/usr/local/starfish-sdk-x86_64/environment-setup-ca9v1-webosmllib32-linux-gnueabi

tools/build_webos.sh
tools/verify_tv_package.sh webos dist/webos/zanzibarr-webos26-arm.ipk
```

The verifier extracts the engine from each TPK/IPK and checks ARM ELF, SONAME and softfp ABI. Tizen must have no dynamic `libstdc++` dependency. webOS must have the engine's `$ORIGIN` RPATH and the matching bundled `libstdc++.so.6` runtime.

### CI

`.github/workflows/tv-build.yml` has three jobs: Tizen 6.0, Tizen 10.0 and webOS 26. It publishes unsigned-by-production-credentials release-candidate artifacts only; real-device installation and playback remain owner validation steps.

## Verification status

- Rust: 330 tests plus clippy.
- Flutter: 275 tests plus analysis, including TV audio preference, launcher, controls, fake native stream opening, queue transition and platform configuration tests.
- Both isolated TV dependency profiles and both SDK analyzers pass.
- The Tizen 6.0/GCC 9.2 and Tizen 10.0/GCC 14.2 engines were also built independently from CI. `readelf` confirmed ELF32/ARM, soft-float ABI and the expected SONAME, with no dynamic `libstdc++` dependency in either engine.
- [CI run 45067947147](https://github.com/envermeister/zanzibarr/actions/runs/45067947147) produced and verified all three packages. The downloaded Tizen 6.0 TPK, Tizen 10.0 TPK and webOS IPK were independently extracted and verified again with `tools/verify_tv_package.sh`.
- Real Samsung/LG TV installation, codec behavior, NNTP credentials, playback and remote behavior still require physical-device verification. Package/ABI verification does not establish on-device playback or hardware codec support.
