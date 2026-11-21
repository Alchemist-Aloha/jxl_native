// Decodes a JPEG XL file and prints its size and the first pixel.
//
// dart run example/example.dart photo.jxl
import 'dart:io';
import 'dart:isolate';

import 'package:jxl_native/jxl_native.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run example/example.dart <file.jxl>');
    exitCode = 64;
    return;
  }
  final bytes = await File(args.single).readAsBytes();
  try {
    // decodeJxl blocks, so large images belong off the main isolate.
    final image = await Isolate.run(() => decodeJxl(bytes));
    final [r, g, b, a] = image.rgba.sublist(0, 4);
    print('${image.width}x${image.height}, first pixel rgba($r, $g, $b, $a)');
  } on JxlDecodeException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
