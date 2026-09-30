import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/brand.dart';

// Explicitly run with flutter test tool/export_brand.dart to update assets.
void main() {
  test(
    'export the shared brand drawing to Android launcher densities',
    () async {
      Future<void> export(
        String path,
        int pixels, {
        bool adaptive = false,
      }) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        if (adaptive) {
          canvas.translate(pixels * .17, pixels * .17);
          canvas.scale(.66);
        }
        BrandPainter(
          background: !adaptive,
        ).paint(canvas, Size.square(pixels.toDouble()));
        final picture = recorder.endRecording();
        final image = await picture.toImage(pixels, pixels);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }

      for (final density in {
        'mdpi': 1.0,
        'hdpi': 1.5,
        'xhdpi': 2.0,
        'xxhdpi': 3.0,
        'xxxhdpi': 4.0,
      }.entries) {
        final root = 'android/app/src/main/res/mipmap-${density.key}';
        await export('$root/ic_launcher.png', (48 * density.value).round());
        await export(
          '$root/ic_launcher_foreground.png',
          (108 * density.value).round(),
          adaptive: true,
        );
      }
      await export('../../artifacts/brand/shiri-mark.png', 512);
    },
  );
}
