import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

@Native<Uint32 Function()>(symbol: 'jxl_native_decoder_version', isLeaf: true)
external int _decoderVersion();

@Native<Void Function(Pointer<Void>)>(symbol: 'jxl_native_free', isLeaf: true)
external void _nativeFree(Pointer<Void> pointer);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Pointer<Uint8>>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: 'jxl_native_decode')
external int _decode(
  Pointer<Uint8> data,
  int size,
  int maxPixels,
  Pointer<Pointer<Uint8>> rgba,
  Pointer<Int32> width,
  Pointer<Int32> height,
);

/// Version of the bundled libjxl decoder, e.g. `13000` for 0.13.0.
int get jxlNativeDecoderVersion => _decoderVersion();

/// A decoded JPEG XL frame as straight (non-premultiplied) RGBA8.
final class JxlImageData {
  const JxlImageData({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;

  /// `width * height * 4` bytes, row-major, top-left origin.
  final Uint8List rgba;
}

/// Thrown when libjxl cannot decode the input.
final class JxlDecodeException implements Exception {
  const JxlDecodeException(this.message);

  final String message;

  @override
  String toString() => 'JxlDecodeException: $message';
}

/// Decodes the first displayed frame of a JPEG XL image with libjxl.
///
/// Output matches `djxl` 8-bit output: orientation applied, lossy (XYB)
/// images converted to sRGB, grayscale expanded to RGB. Images with more than
/// [maxPixels] pixels are rejected before any pixel memory is allocated; pass
/// 0 to disable the limit. Decoding uses libjxl's thread pool and blocks the
/// calling isolate, so run it in a background isolate for large images.
JxlImageData decodeJxl(Uint8List bytes, {int maxPixels = 1 << 28}) {
  if (bytes.isEmpty) throw const JxlDecodeException('input is empty');
  if (maxPixels < 0) throw ArgumentError.value(maxPixels, 'maxPixels');

  final data = calloc<Uint8>(bytes.length);
  final rgba = calloc<Pointer<Uint8>>();
  final width = calloc<Int32>();
  final height = calloc<Int32>();
  try {
    data.asTypedList(bytes.length).setAll(0, bytes);
    final result = _decode(data, bytes.length, maxPixels, rgba, width, height);
    if (result != 0) throw JxlDecodeException(_message(result));
    final length = width.value * height.value * 4;
    return JxlImageData(
      width: width.value,
      height: height.value,
      rgba: Uint8List.fromList(rgba.value.asTypedList(length)),
    );
  } finally {
    if (rgba.value != nullptr) _nativeFree(rgba.value.cast());
    calloc.free(data);
    calloc.free(rgba);
    calloc.free(width);
    calloc.free(height);
  }
}

String _message(int code) => switch (code) {
  1 => 'invalid argument',
  2 => 'not a decodable JPEG XL image',
  3 => 'input is truncated',
  4 => 'image dimensions exceed the pixel limit',
  5 => 'out of memory',
  _ => 'unknown error $code',
};
