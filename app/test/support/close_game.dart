import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puts a live game away at the end of a test.
///
/// A game screen nearly always has something scheduled — a number being read,
/// a chip walking, the computer thinking — so a test that stops at an
/// arbitrary moment leaves a timer ticking, and the framework rightly refuses
/// to let that pass. Replacing the tree disposes the screen, and the screen
/// cancels its own timers when it goes.
///
/// Called after the assertions, never before: they belong on the live board.
Future<void> closeGame(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
