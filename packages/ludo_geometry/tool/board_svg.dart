// Draws the board as an SVG, straight from the geometry the app uses.
//
// This is for arguing about the layout with something better than words. Every
// shape here is the shape the painter draws, in the geometry's own 600-unit
// space — so a radius you measure off the SVG is a constant you can change in
// geometry.dart, and a shape you drag is a shape somebody has to write down.
//
//   dart run tool/board_svg.dart          # writes build/board-6.svg, board-4.svg
import 'dart:io';
import 'dart:math' as math;

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// The geometry works in 0..1. Everything here is scaled back up into the
/// units the constants are actually written in — read off the board rather
/// than assumed, because the two boards do not share a reference and the
/// hexagon's changed once already. A square is 30 units on both.
double unitOf(BoardGeometry g) => 30 / g.cellSize;

const seatColours = [
  '#E14B4B', // red
  '#3FA35C', // green
  '#3B72D9', // blue
  '#E3B23C', // yellow
  '#7E57C2', // purple
  '#EF8022', // orange
];

String f(double v) => v.toStringAsFixed(2);

/// The four corners of a cell, in order.
List<Pt> cellCorners(CellShape c) {
  final h = c.size / 2;
  final cos = math.cos(c.rotation), sin = math.sin(c.rotation);
  return [
    for (final (dx, dy) in [(-h, -h), (h, -h), (h, h), (-h, h)])
      Pt(c.centre.x + dx * cos - dy * sin, c.centre.y + dx * sin + dy * cos)
  ];
}

String polygon(List<Pt> pts, String attrs, double u) =>
    '<polygon points="${pts.map((p) => '${f(p.x * u)},${f(p.y * u)}').join(' ')}" $attrs/>';

String svgFor(BoardSpec spec,
    {required bool guides, bool measure = false}) {
  final g = BoardGeometry.forSpec(spec);
  final u = unitOf(g);
  final out = StringBuffer();

  out.writeln('<svg xmlns="http://www.w3.org/2000/svg" '
      'viewBox="0 0 ${f(u)} ${f(u)}" width="900" height="900">');
  out.writeln('<rect width="${f(u)}" height="${f(u)}" fill="#F2EFE7"/>');

  // --- the plate ----------------------------------------------------------
  out.writeln('<g id="plate">');
  out.writeln(polygon(g.plateOutline(),
      'fill="#FBFAF6" stroke="#CFCABA" stroke-width="1.5"', u));
  out.writeln('</g>');

  // --- the shared track ---------------------------------------------------
  // Start squares wear their owner's colour; the rest are plain.
  final starts = {
    for (var a = 0; a < spec.arms; a++) spec.startRing(a): a,
  };
  out.writeln('<g id="track" stroke="#D8D3C6" stroke-width="1">');
  for (var i = 0; i < spec.trackLength; i++) {
    final owner = starts[i];
    final fill = owner == null ? '#FFFFFF' : seatColours[owner % 6];
    out.writeln('  ${polygon(cellCorners(g.ringCell(i)), 'fill="$fill"'
        '${owner == null ? '' : ' id="start-$owner"'}', u)}');
  }
  out.writeln('</g>');

  // --- home columns -------------------------------------------------------
  out.writeln('<g id="home-columns" stroke="#D8D3C6" stroke-width="1">');
  for (var arm = 0; arm < spec.arms; arm++) {
    out.writeln('  <g id="home-column-$arm">');
    for (var i = 0; i < spec.homeColumn; i++) {
      out.writeln('    ${polygon(cellCorners(g.homeCell(arm, i)),
          'fill="${seatColours[arm % 6]}"', u)}');
    }
    out.writeln('  </g>');
  }
  out.writeln('</g>');

  // --- the houses ---------------------------------------------------------
  // On the hexagon these are the triangles under discussion. Each one is drawn
  // twice: the colour, then the interior inset from its own centroid.
  out.writeln('<g id="houses">');
  for (var arm = 0; arm < spec.arms; arm++) {
    final colour = seatColours[arm % 6];
    if (g is CrossGeometry) {
      final (tl, br) = g.yardSquare(arm);
      final w = (br.x - tl.x) * u, h = (br.y - tl.y) * u;
      out.writeln('  <g id="house-$arm">');
      out.writeln('    <rect x="${f(tl.x * u)}" y="${f(tl.y * u)}" '
          'width="${f(w)}" height="${f(h)}" fill="$colour"/>');
      out.writeln('    <rect x="${f(tl.x * u + 30)}" y="${f(tl.y * u + 30)}" '
          'width="${f(w - 60)}" height="${f(h - 60)}" fill="#FBFAF6"/>');
      out.writeln('  </g>');
    } else {
      final t = g.yardShape(arm);
      final pts = [t.a, t.b, t.c];
      final cx = pts.map((p) => p.x).reduce((a, b) => a + b) / 3;
      final cy = pts.map((p) => p.y).reduce((a, b) => a + b) / 3;
      final inner = [
        for (final p in pts)
          Pt(cx + (p.x - cx) * 0.80, cy + (p.y - cy) * 0.80)
      ];
      out.writeln('  <g id="house-$arm">');
      out.writeln('    ${polygon(pts, 'fill="$colour"', u)}');
      out.writeln('    ${polygon(inner, 'fill="#FBFAF6"', u)}');
      out.writeln('  </g>');
    }
    out.writeln('  <g id="house-slots-$arm" fill="#E6E2D6">');
    for (final s in g.yardSlots(arm)) {
      out.writeln('    <circle cx="${f(s.x * u)}" cy="${f(s.y * u)}" r="11"/>');
    }
    out.writeln('  </g>');
  }
  out.writeln('</g>');

  // --- the middle ---------------------------------------------------------
  out.writeln('<g id="centre" stroke="#FBFAF6" stroke-width="1">');
  final wedges = g.centreWedges();
  for (var k = 0; k < wedges.length; k++) {
    final w = wedges[k];
    out.writeln('  ${polygon([w.a, w.b, w.c],
        'fill="${seatColours[k % 6]}" id="wedge-$k"', u)}');
  }
  out.writeln('</g>');

  // --- measuring marks ----------------------------------------------------
  if (measure && g is HexGeometry) {
    final v = g.plateOutline();
    out.writeln('<g id="measure" font-family="monospace" font-size="13">');
    for (var i = 0; i < 12; i++) {
      final a = v[i], b = v[(i + 1) % 12];
      final len = (b - a).length * u;
      // Even edges face an arm and carry the track; odd edges face a house.
      final path = i.isEven;
      final mx = (a.x + b.x) / 2 * u, my = (a.y + b.y) / 2 * u;
      final dx = mx - u / 2, dy = my - u / 2;
      final d = math.sqrt(dx * dx + dy * dy);
      out.writeln('  <line x1="${f(a.x * u)}" y1="${f(a.y * u)}" '
          'x2="${f(b.x * u)}" y2="${f(b.y * u)}" '
          'stroke="${path ? '#1B6FD1' : '#C22'}" stroke-width="4"/>');
      out.writeln('  <text x="${f(mx + dx / d * 26)}" y="${f(my + dy / d * 26)}" '
          'text-anchor="middle" fill="${path ? '#1B6FD1' : '#C22'}">'
          '${f(len)}</text>');
    }

    // How much of each edge the thing behind it actually fills. A house fills
    // its edge end to end. The track is three cells wide and stops 13 units
    // short of the rim, so it fills 90 of its 146 — which is the difference
    // you are looking at when a home side reads as bigger than a path side.
    for (var arm = 0; arm < spec.arms; arm++) {
      final ang = (-90 + 60.0 * arm) * math.pi / 180;
      final ux = math.cos(ang), uy = math.sin(ang);
      Pt at(double r, double lat) => Pt(
          (u / 2 + ux * r - uy * lat) / u, (u / 2 + uy * r + ux * lat) / u);
      final a = at(259, -45), b = at(259, 45);
      out.writeln('  <line x1="${f(a.x * u)}" y1="${f(a.y * u)}" '
          'x2="${f(b.x * u)}" y2="${f(b.y * u)}" '
          'stroke="#1B6FD1" stroke-width="3" stroke-dasharray="5 3"/>');
      final m = at(236, 0);
      out.writeln('  <text x="${f(m.x * u)}" y="${f(m.y * u)}" '
          'text-anchor="middle" fill="#1B6FD1" font-size="12">90.00</text>');
    }
    out.writeln('</g>');
  }

  if (guides) {
    out.writeln('<!-- Delete this group once you are done marking it up. -->');
    out.writeln('<g id="guides" fill="none" stroke="#00000055" '
        'stroke-width="0.8" stroke-dasharray="4 4">');
    for (final r in [90.0, 244.0, 246.8, 259.0]) {
      out.writeln('  <circle cx="${u / 2}" cy="${u / 2}" r="${f(r)}"/>');
      out.writeln('  <text x="${f(u / 2 + 4)}" y="${f(u / 2 - r + 12)}" '
          'font-family="monospace" font-size="11" fill="#00000099" '
          'stroke="none">r=${f(r)}</text>');
    }
    out.writeln('</g>');
  }

  out.writeln('</svg>');
  return out.toString();
}

void main() {
  Directory('build').createSync(recursive: true);
  for (final (name, spec) in [
    ('board-6', BoardSpec.hexagon),
    ('board-4', BoardSpec.cross),
  ]) {
    File('build/$name.svg').writeAsStringSync(svgFor(spec, guides: true));
    File('build/$name-plain.svg').writeAsStringSync(svgFor(spec, guides: false));
    File('build/$name-measured.svg')
        .writeAsStringSync(svgFor(spec, guides: false, measure: true));
    stdout.writeln('wrote build/$name.svg');
  }
}
