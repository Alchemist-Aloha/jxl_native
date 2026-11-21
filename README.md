# jxl_native

JPEG XL decoding for Dart and Flutter through [libjxl](https://github.com/libjxl/libjxl),
the decoder behind `djxl`. It uses Dart FFI and a native-assets build hook, so apps
need no CMake, compiler, or system libjxl: the hook downloads a prebuilt,
SHA-256-verified library for the target platform.

```dart
import 'dart:io';
import 'package:jxl_native/jxl_native.dart';

void main() {
  final image = decodeJxl(File('photo.jxl').readAsBytesSync());
  print('${image.width}x${image.height}, ${image.rgba.length} RGBA bytes');
}
```

`decodeJxl` returns the first displayed frame as straight (non-premultiplied)
RGBA8, matching `djxl`'s 8-bit output: orientation applied, lossy (XYB) images
converted to sRGB, grayscale expanded to RGB. It decodes on libjxl's thread
pool and blocks the calling isolate, so use `Isolate.run` for large images.
`maxPixels` (default 2^28) rejects oversized images before pixel memory is
allocated. Failures throw `JxlDecodeException`.

## Performance

Decoding a 3000×2000 (6 MP) lossy JPEG XL photo (`cjxl -d 1`, 3.2 MB, with
added noise as a worst case) to RGBA8 on an Intel Core i5-13600K, Linux x64:

| Decoder | Time |
| --- | --- |
| `jxl_native` 0.1.0 (libjxl 0.13.0, libjxl thread pool) | **28 ms** |
| `djxl` 0.13.0, single thread (includes writing a PPM file) | ~190 ms |
| [`koni_jxl`](https://pub.dev/packages/koni_jxl) 0.1.4 (pure Dart) | 985 ms |

Dart timings are AOT-compiled (`dart build cli`), averaged over three runs
after a warm-up decode; `djxl` is wall-clock time for the CLI. The thread pool
size comes from libjxl's suggestion for the image size, so small images use
fewer threads and gain less. Results vary with CPU, image content, and
encoder settings.

## Platforms

Android (arm64, arm, x64), iOS (device, arm64/x64 simulator), macOS (arm64,
x64), Linux (x64, arm64), and Windows (x64, arm64). On any other target the hook
bundles nothing and `decodeJxl` throws at runtime instead of failing the build.
Web is not supported.

## Limitations

- First frame only; no animation API.
- Lossless images with an embedded non-sRGB ICC profile are returned in that
  profile's colour space (the decoder-only build has no colour management).
- No metadata (EXIF/XMP) or JPEG bitstream reconstruction.

## Native builds

The libjxl commit is pinned in `native/versions.json`; its own submodules pin
brotli, highway, and skcms.

```sh
tool/native/build_unix.sh linux-x64     # or macos-arm64, android-arm64, ...
tool/use_local_build.py linux-x64       # point the manifest at that build
dart test
```

Windows uses `tool/native/build_windows.ps1 windows-x64|windows-arm64` from a
Visual Studio developer shell.

To release: run the **Native release** workflow (or push a `native-v*` tag),
then copy the published `manifest.json` into `native/manifest.json`.

## Licensing

The Dart package and C shim are MIT licensed. Bundled libraries keep their own
licenses, in `LICENSES/`: libjxl (BSD-3-Clause, with a patent grant), brotli
(MIT), highway (Apache-2.0), and skcms (BSD-3-Clause).
