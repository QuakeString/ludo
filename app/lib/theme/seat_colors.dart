import 'package:flutter/material.dart';

/// The six colours a table can be painted in.
///
/// Chosen so no two are confusable and all six stay distinct for red–green
/// colour deficiency — position and the chip's white rim carry the difference,
/// never hue alone. This is the palette, not the layout: which colour sits in
/// which corner is [colourOfArm]'s business, and differs between the boards.
const ludoRed = Color(0xFFE14B4B);
const ludoGreen = Color(0xFF3FA35C);
const ludoBlue = Color(0xFF3B72D9);
const ludoYellow = Color(0xFFE3B23C);
const ludoOrange = Color(0xFFEF8022);
const ludoMagenta = Color(0xFFCE3D93);

const seatColors = <Color>[
  ludoRed,
  ludoGreen,
  ludoBlue,
  ludoYellow,
  ludoMagenta,
  ludoOrange,
];

/// Parallel to [seatColors] — a map keyed by Color cannot be const.
const _names = <String>[
  'Red',
  'Green',
  'Blue',
  'Yellow',
  'Magenta',
  'Orange',
];

/// Where each colour sits on the four-arm board, by arm: top-left, top-right,
/// bottom-right, bottom-left.
///
/// Opposite arms are 0–2 and 1–3, so this seats green against blue and yellow
/// against red.
const _crossArms = <Color>[ludoGreen, ludoYellow, ludoBlue, ludoRed];

/// And on the six-arm board, going round from the top-right.
///
/// Opposite arms here are 0–3, 1–4 and 2–5, which is why this list is not the
/// four-arm one with two colours added: a single order cannot give both boards
/// the pairs they want. On four arms red faces yellow and green faces blue; on
/// six, red faces yellow, blue faces green and orange faces magenta. Those
/// demand different arrangements, and pretending otherwise would break one
/// board to keep one list.
const _hexArms = <Color>[
  ludoYellow, // top-right
  ludoOrange, // right
  ludoBlue, // bottom-right
  ludoRed, // bottom-left
  ludoMagenta, // left
  ludoGreen, // top-left
];

/// The colour of a *place* on the board.
///
/// A Ludo board has its colours painted on before anyone sits down; a player
/// takes the colour of the corner they play from. Keying off the seat index
/// instead meant an unoccupied corner had no colour of its own — which is
/// exactly the corner that needs one, because the board still has to show it.
///
/// [arms] is required rather than defaulted because the two boards genuinely
/// disagree, and a default would let a six-arm board quietly wear the
/// four-arm colours.
Color colourOfArm(int arm, int arms) {
  final places = arms == 6 ? _hexArms : _crossArms;
  return places[arm % places.length];
}

String nameOfArm(int arm, int arms) =>
    _names[seatColors.indexOf(colourOfArm(arm, arms))];

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
    required this.panel,
    required this.panelEdge,
    required this.faint,
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

  /// A seat's panel beside the board, its border, and the quieter text on it.
  final Color panel;
  final Color panelEdge;
  final Color faint;

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
    panel: Color(0xFFFAF6EE),
    panelEdge: Color(0xFFDED6C6),
    faint: Color(0xFF7A736A),
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
    panel: Color(0xFF1B2028),
    panelEdge: Color(0xFF39414E),
    faint: Color(0xFF98A0AE),
  );

  static BoardPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// App-wide themes. Light and dark are both first-class from day one; the app
/// follows the system unless the player picks one.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: ludoBlue,
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
