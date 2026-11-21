import 'dart:io';
import 'dart:typed_data';

import 'package:jxl_native/jxl_native.dart';
import 'package:test/test.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  test('reports the bundled libjxl version', () {
    expect(jxlNativeDecoderVersion, greaterThanOrEqualTo(13000));
  });

  test('decodes lossy images like djxl', () {
    final image = decodeJxl(fixture('lossy_64x48.jxl'));
    expect((image.width, image.height), (64, 48));
    // lossy_64x48_djxl.rgb is `djxl` v0.13.0 RGB8 output for the same file.
    final reference = fixture('lossy_64x48_djxl.rgb');
    var maxDelta = 0;
    for (var p = 0; p < 64 * 48; p++) {
      for (var c = 0; c < 3; c++) {
        final delta = (image.rgba[p * 4 + c] - reference[p * 3 + c]).abs();
        if (delta > maxDelta) maxDelta = delta;
      }
      expect(image.rgba[p * 4 + 3], 255);
    }
    // SIMD paths differ by at most one step across CPUs.
    expect(maxDelta, lessThanOrEqualTo(1));
  });

  test('keeps straight alpha', () {
    final image = decodeJxl(fixture('alpha_16x12.jxl'));
    expect((image.width, image.height), (16, 12));
    expect(image.rgba[0], greaterThan(245));
    expect(image.rgba[1], lessThan(10));
    expect(image.rgba[3], inInclusiveRange(124, 132));
  });

  test('expands grayscale to RGBA', () {
    final image = decodeJxl(fixture('gray_20x10.jxl'));
    expect((image.width, image.height), (20, 10));
    expect(image.rgba.length, 20 * 10 * 4);
    final mid = image.rgba.sublist(10 * 4, 10 * 4 + 4);
    expect(mid[0], mid[1]);
    expect(mid[1], mid[2]);
    expect(mid[3], 255);
  });

  test('rejects images above the pixel limit before decoding', () {
    expect(
      () => decodeJxl(fixture('lossy_64x48.jxl'), maxPixels: 100),
      throwsA(
        isA<JxlDecodeException>().having(
          (e) => e.message,
          'message',
          contains('pixel limit'),
        ),
      ),
    );
  });

  test('throws on invalid and truncated input', () {
    expect(
      () => decodeJxl(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<JxlDecodeException>()),
    );
    // With input closed, libjxl reports a cut-off file as a decode error.
    final bytes = fixture('lossy_64x48.jxl');
    expect(
      () => decodeJxl(Uint8List.sublistView(bytes, 0, bytes.length ~/ 2)),
      throwsA(isA<JxlDecodeException>()),
    );
    expect(() => decodeJxl(Uint8List(0)), throwsA(isA<JxlDecodeException>()));
  });
}
