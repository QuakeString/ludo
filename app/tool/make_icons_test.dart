// Draws the LUDO Time icon at every size the platforms ask for.
//
//   flutter test tool/make_icons_test.dart
//
// Kept as code rather than as one exported picture so the icon can be changed
// in one place and every size redrawn from it, and so the small sizes are
// drawn at their size rather than shrunk from a big one.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _green = Color(0xFF3FA35C);
const _yellow = Color(0xFFE3B23C);
const _blue = Color(0xFF3B72D9);
const _red = Color(0xFFE14B4B);
const _track = Color(0xFFFDFBF7);
const _ink = Color(0xFF2A2622);
const _pip = Color(0xFFD32F2F);

/// The icon on a 100-unit square: the four corners of the board, the cross
/// of the track, and the die showing its red six. [rounded] cuts the corners
/// for places that show the picture as it is; iOS and Android's maskable
/// icons want the full square and cut it themselves.
void paintIcon(Canvas canvas, double side, {required bool rounded}) {
  canvas.scale(side / 100);
  if (rounded) {
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Radius.circular(22),
      ),
    );
  }
  final p = Paint();
  canvas.drawRect(const Rect.fromLTWH(0, 0, 50, 50), p..color = _green);
  canvas.drawRect(const Rect.fromLTWH(50, 0, 50, 50), p..color = _yellow);
  canvas.drawRect(const Rect.fromLTWH(50, 50, 50, 50), p..color = _blue);
  canvas.drawRect(const Rect.fromLTWH(0, 50, 50, 50), p..color = _red);
  canvas.drawRect(const Rect.fromLTWH(38, 0, 24, 100), p..color = _track);
  canvas.drawRect(const Rect.fromLTWH(0, 38, 100, 24), p..color = _track);

  canvas.save();
  canvas.translate(50, 50);
  canvas.rotate(-10 * math.pi / 180);
  canvas.translate(-50, -50);
  final die = RRect.fromRectAndRadius(
    const Rect.fromLTWH(31, 31, 38, 38),
    const Radius.circular(9),
  );
  canvas.drawRRect(
    die.shift(const Offset(1.2, 2)),
    Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
  );
  canvas.drawRRect(die, Paint()..color = Colors.white);
  canvas.drawRRect(
    die,
    Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2,
  );
  for (final x in [41.0, 59.0]) {
    for (final y in [40.0, 50.0, 60.0]) {
      canvas.drawCircle(Offset(x, y), 3.4, Paint()..color = _pip);
    }
  }
  canvas.restore();
}

Future<void> _write(
  WidgetTester tester,
  String path,
  int size, {
  required bool rounded,
}) async {
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (!rounded) {
      // Opaque all the way out: iOS refuses an icon with transparency.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..color = _track,
      );
    }
    paintIcon(canvas, size.toDouble(), rounded: rounded);
    final image = await recorder.endRecording().toImage(size, size);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('draw every icon', (tester) async {
    const android = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final e in android.entries) {
      await _write(
        tester,
        'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
        e.value,
        rounded: true,
      );
    }

    await _write(tester, 'web/favicon.png', 32, rounded: true);
    await _write(tester, 'web/icons/Icon-192.png', 192, rounded: true);
    await _write(tester, 'web/icons/Icon-512.png', 512, rounded: true);
    await _write(
      tester,
      'web/icons/Icon-maskable-192.png',
      192,
      rounded: false,
    );
    await _write(
      tester,
      'web/icons/Icon-maskable-512.png',
      512,
      rounded: false,
    );

    const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    const iosSizes = <String, int>{
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    for (final e in iosSizes.entries) {
      await _write(tester, '$ios/${e.key}', e.value, rounded: false);
    }
  });
}
