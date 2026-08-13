/// Where the board's pieces are drawn, in a resolution-free unit square.
///
/// The engine decides what is legal; this decides where it appears. Keeping
/// them apart lets the rules be tested without pixels and the layout be tested
/// without a rendering framework.
library;

export 'src/geometry.dart';
