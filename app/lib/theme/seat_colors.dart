import 'package:flutter/material.dart';

/// The six seat colours, in seat order.
///
/// Chosen so no two neighbours on the board are confusable and all six stay
/// distinct for red–green colour deficiency — seat position and the chip's
/// white rim carry the difference, never hue alone.
const seatColors = <Color>[
  Color(0xFFE14B4B), // red
  Color(0xFF3FA35C), // green
  Color(0xFF3B72D9), // blue
  Color(0xFFE3B23C), // yellow
  Color(0xFF7E57C2), // purple
  Color(0xFFEF8022), // orange
];

const seatNames = <String>[
  'Red',
  'Green',
  'Blue',
  'Yellow',
  'Purple',
  'Orange',
];

/// Everything the board painter needs to draw in one theme.
///
/// Dark is a real palette, not a filter over the light one: the surface, grid
/// and home interiors are all their own colours. The chips are unchanged —
/// their white rim is exactly what lets one chip design work on both grounds.
class BoardPalette {
  const BoardPalette({
    required this.plate,
    required this.cell,
    required this.line,
    required this.star,
    required this.homeInterior,
    required this.slot,
    required this.die,
    required this.dieIdle,
    required this.dieEdge,
    required this.pip,
    required this.felt,
  });

  final Color plate;
  final Color cell;
  final Color line;
  final Color star;
  final Color homeInterior;
  final Color slot;
  final Color die;
  final Color dieIdle;
  final Color dieEdge;
  final Color pip;

  /// Behind the board itself.
  final Color felt;

  static const light = BoardPalette(
    plate: Color(0xFFFDFBF7),
    cell: Color(0xFFFFFFFF),
    line: Color(0xFFC9C1B2),
    star: Color(0xFF8A8478),
    homeInterior: Color(0xFFFFFFFF),
    slot: Color(0x17000000),
    die: Color(0xFFFFFFFF),
    dieIdle: Color(0xFFEFE9DD),
    dieEdge: Color(0xFFC9C1B2),
    pip: Color(0xFF2A2622),
    felt: Color(0xFFF2EDE3),
  );

  static const dark = BoardPalette(
    plate: Color(0xFF232830),
    cell: Color(0xFF2E343F),
    line: Color(0xFF4A5260),
    star: Color(0xFF8E96A4),
    homeInterior: Color(0xFF1B1F26),
    slot: Color(0x1AFFFFFF),
    die: Color(0xFFEAE6DE),
    dieIdle: Color(0xFF2A303A),
    dieEdge: Color(0xFF4A5260),
    pip: Color(0xFF171A21),
    felt: Color(0xFF12151B),
  );

  static BoardPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// App-wide themes. Light and dark are both first-class from day one; the app
/// follows the system unless the player picks one.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seatColors[2],
    brightness: brightness,
  ).copyWith(surface: dark ? const Color(0xFF161920) : const Color(0xFFF7F3EC));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: Typography.material2021(colorScheme: scheme).black.apply(
      bodyColor: dark ? const Color(0xFFEAE6DE) : const Color(0xFF2A2622),
      displayColor: dark ? const Color(0xFFEAE6DE) : const Color(0xFF2A2622),
    ),
  );
}
