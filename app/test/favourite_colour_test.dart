import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/home_screen.dart';
import 'package:ludo_app/theme/seat_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each player picks the colour they play in, on their own screen.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => favouriteColour = null);

  List<Color> cross() => [for (var a = 0; a < 4; a++) colourOfArm(a, 4)];
  List<Color> hex() => [for (var a = 0; a < 6; a++) colourOfArm(a, 6)];

  test('with no choice, the board keeps its own colours', () {
    expect(cross(), [ludoGreen, ludoYellow, ludoBlue, ludoRed]);
  });

  test('your colour sits bottom-left and the corner it left takes red', () {
    favouriteColour = ludoBlue;
    expect(cross(), [ludoGreen, ludoYellow, ludoRed, ludoBlue]);
    expect(hex()[3], ludoBlue);
    expect(hex().toSet(), hasLength(6), reason: 'a colour was used twice');
  });

  test('a colour the small board does not paint simply replaces red', () {
    favouriteColour = ludoMagenta;
    expect(cross(), [ludoGreen, ludoYellow, ludoBlue, ludoMagenta]);
  });

  test('the choice is kept between launches', () async {
    await FavouriteColour.save(ludoGreen);
    favouriteColour = null;
    await FavouriteColour.load();
    expect(favouriteColour, ludoGreen);
  });

  testWidgets('picked on the front page', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    final yellow = find.byKey(const ValueKey('colour-Yellow'));
    await tester.ensureVisible(yellow);
    await tester.tap(yellow);
    await tester.pumpAndSettle();
    expect(favouriteColour, ludoYellow);
    expect(colourOfArm(3, 4), ludoYellow);
  });
}
