import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/table_chat.dart';
import 'package:ludo_app/theme/seat_colors.dart';

/// Chat at an online table: typed along the bottom, shown at the top.
void main() {
  Future<List<String>> openBar(WidgetTester tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatBar(onSend: sent.add),
          ),
        ),
      ),
    );
    return sent;
  }

  testWidgets('typing and sending passes the line on and clears the box', (
    tester,
  ) async {
    final sent = await openBar(tester);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'gg ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    expect(sent, ['gg']);
    expect(find.text('gg '), findsNothing);
  });

  testWidgets('nothing to say sends nothing', (tester) async {
    final sent = await openBar(tester);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '   ');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    expect(sent, isEmpty);
  });

  testWidgets('emoji can be picked from the bar itself', (tester) async {
    final sent = await openBar(tester);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'yes');
    await tester.tap(find.byKey(const ValueKey('chat-emoji')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-emoji-grid')), findsOneWidget);
    await tester.tap(find.text('🎉'));
    await tester.pump();
    expect(find.text('yes🎉'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    expect(sent, ['yes🎉']);
  });

  testWidgets('a line shows who said it on a wash of their colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatLine(who: 'Ammu', text: 'hello 👋', colour: ludoRed),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ammu'), findsOneWidget);
    expect(find.textContaining('hello 👋'), findsOneWidget);
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ChatLine),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration,
            ),
          )
          .first,
    );
    final wash = (box.decoration! as BoxDecoration).color!;
    expect(wash.r, greaterThan(wash.g), reason: 'red, faintly');
  });
}
