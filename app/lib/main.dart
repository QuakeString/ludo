import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/online_screen.dart';
import 'theme/seat_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavouriteColour.load();
  runApp(const LudoApp());
}

/// The room code in an invite link, whichever shape it arrived in: the app's
/// own `ludo://join/CODE`, or the web page's `…/r/CODE` passed on to it.
String? inviteCodeIn(String link) {
  final match = RegExp(r'(?:join|/r)/([A-Za-z0-9-]{4,12})/?(?:[?#].*)?$')
      .firstMatch(link);
  return match?.group(1)?.toUpperCase().replaceAll('-', '');
}

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});

  @override
  State<LudoApp> createState() => _LudoAppState();
}

/// Also where invite links land.
///
/// Android hands the link to Flutter as a route. Flutter's own navigator
/// would try to find a page by that name and find none, so the link is caught
/// here first: once at start, for a link that opened the app, and again
/// whenever one arrives while it is already open.
class _LudoAppState extends State<LudoApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final opening = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final code = inviteCodeIn(opening);
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join(code));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async {
    final code = inviteCodeIn(info.uri.toString());
    if (code == null) return false;
    _join(code);
    return true;
  }

  void _join(String code) {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute(builder: (_) => OnlineScreen(joinCode: code)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Ludo',
      debugShowCheckedModeBanner: false,
      // Light and dark are both first class, following the system until the
      // player overrides it in settings.
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      // Whatever route the platform asked for, the app opens on the front
      // page; an invite link is acted on above, not looked up as a page.
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      ],
      home: const HomeScreen(),
    );
  }
}
