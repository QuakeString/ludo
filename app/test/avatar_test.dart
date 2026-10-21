import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/seat_panel.dart';
import 'package:ludo_app/screens/avatars.dart';
import 'package:ludo_app/theme/seat_colors.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every player has a picture: a photo of their own or one of twenty animals.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    myAvatar = null;
  });

  test('there are twenty animals, as many as the server accepts', () {
    expect(animals, hasLength(20));
    expect(Avatar.animalCount, animals.length);
    expect(animals.map((a) => a.$2).toSet(), hasLength(20));
  });

  testWidgets('an animal is chosen from the sheet and remembered', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await pickAvatar(context),
            child: const Text('pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('avatar-photo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('avatar-3')));
    await tester.pumpAndSettle();

    expect(picked, Avatar.animal(3));
    expect(myAvatar, Avatar.animal(3));
    myAvatar = null;
    await MyAvatar.load();
    expect(myAvatar, Avatar.animal(3), reason: 'kept between launches');
  });

  testWidgets('the board shows the name over the picture', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 64,
              child: SeatPanel(
                arm: 0,
                arms: 4,
                name: 'Ammu',
                home: 0,
                total: 4,
                onTurn: false,
                avatar: Avatar.animal(0),
              ),
            ),
          ),
        ),
      ),
    );
    final name = tester.getRect(find.text('Ammu'));
    final face = tester.getRect(find.text(animals[0].$1));
    expect(name.bottom, lessThanOrEqualTo(face.top + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a computer is always a robot, whatever it is sent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AvatarBubble(avatar: 'a:2', colour: ludoBlue, robot: true),
      ),
    );
    expect(find.byIcon(Icons.smart_toy), findsOneWidget);
    expect(find.text(animals[2].$1), findsNothing);
  });
}
