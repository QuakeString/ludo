import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/seat_colors.dart';

/// The twenty pictures anyone can play as: animals and insects everybody
/// knows, drawn by the phone's own emoji so they look at home on it.
const animals = <(String, String)>[
  ('🦁', 'Lion'),
  ('🐯', 'Tiger'),
  ('🐘', 'Elephant'),
  ('🐼', 'Panda'),
  ('🦊', 'Fox'),
  ('🐨', 'Koala'),
  ('🐵', 'Monkey'),
  ('🐸', 'Frog'),
  ('🦉', 'Owl'),
  ('🐧', 'Penguin'),
  ('🐢', 'Turtle'),
  ('🐬', 'Dolphin'),
  ('🐰', 'Rabbit'),
  ('🦒', 'Giraffe'),
  ('🐴', 'Horse'),
  ('🦋', 'Butterfly'),
  ('🐝', 'Bee'),
  ('🐞', 'Ladybird'),
  ('🐜', 'Ant'),
  ('🐌', 'Snail'),
];

/// This phone's player's picture, as [Avatar] writes it. Null until chosen.
String? myAvatar;

/// Where [myAvatar] is kept between launches.
class MyAvatar {
  const MyAvatar._();

  static const _key = 'ludo.avatar';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      myAvatar = saved != null && Avatar.isValid(saved) ? saved : null;
    } catch (_) {}
  }

  static Future<void> save(String? avatar) async {
    myAvatar = avatar;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (avatar == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, avatar);
      }
    } catch (_) {}
  }
}

/// A seat's picture in a circle ringed with the seat's colour: a photo, one
/// of the [animals], or a plain person (or robot) when there is neither.
class AvatarBubble extends StatelessWidget {
  const AvatarBubble({
    super.key,
    required this.avatar,
    required this.colour,
    this.radius = 14,
    this.robot = false,
  });

  final String? avatar;
  final Color colour;
  final double radius;
  final bool robot;

  @override
  Widget build(BuildContext context) {
    final animal = robot ? null : Avatar.animalOf(avatar);
    final photo = robot ? null : _decoded(Avatar.photoOf(avatar));
    final Widget inside;
    if (photo != null) {
      inside = ClipOval(
        child: Image.memory(
          photo,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    } else if (animal != null) {
      inside = Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.alphaBlend(
            colour.withValues(alpha: 0.22),
            BoardPalette.of(context).panel,
          ),
        ),
        child: Text(
          animals[animal].$1,
          style: TextStyle(fontSize: radius * 1.2, height: 1.1),
        ),
      );
    } else {
      inside = _fallback();
    }
    return Container(
      padding: EdgeInsets.all(radius > 16 ? 2.5 : 1.6),
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      child: inside,
    );
  }

  Widget _fallback() => CircleAvatar(
    radius: radius,
    backgroundColor: colour,
    child: Icon(
      robot ? Icons.smart_toy : Icons.person,
      size: radius * 1.05,
      color: Colors.white,
    ),
  );

  /// Decoding a photo on every frame would be wasteful, and the same few
  /// pictures are shown over and over, so the bytes are kept.
  static final _cache = <String, Uint8List?>{};

  static Uint8List? _decoded(String? base64) {
    if (base64 == null) return null;
    return _cache.putIfAbsent(base64, () {
      if (_cache.length > 32) _cache.clear();
      try {
        return base64Decode(base64);
      } catch (_) {
        return null;
      }
    });
  }
}

/// Lets the player pick their picture: a photo of their own, or an animal.
/// Returns the new one, or null when they backed out. Saved before it returns.
Future<String?> pickAvatar(BuildContext context) async {
  final chosen = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AvatarSheet(),
  );
  if (chosen != null) await MyAvatar.save(chosen);
  return chosen;
}

class _AvatarSheet extends StatefulWidget {
  const _AvatarSheet();

  @override
  State<_AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends State<_AvatarSheet> {
  String? _problem;

  Future<void> _photo() async {
    try {
      // Shrunk by the picker itself to a thumbnail: the picture is shown at
      // the size of a fingertip, and it travels to everyone at the table.
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 128,
        maxHeight: 128,
        imageQuality: 72,
      );
      if (file == null) return;
      final avatar = Avatar.photo(base64Encode(await file.readAsBytes()));
      if (!Avatar.isValid(avatar)) {
        setState(() => _problem = 'That photo is too big. Try another.');
        return;
      }
      if (mounted) Navigator.of(context).pop(avatar);
    } catch (_) {
      setState(() => _problem = 'Could not open your photos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colour = favouriteColour ?? ludoRed;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your picture',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('avatar-photo'),
              onPressed: _photo,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose a photo'),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _problem!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 14),
            const Text('Or play as'),
            const SizedBox(height: 8),
            GridView.extent(
              key: const ValueKey('avatar-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              maxCrossAxisExtent: 64,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var i = 0; i < animals.length; i++)
                  Semantics(
                    label: animals[i].$2,
                    button: true,
                    selected: myAvatar == Avatar.animal(i),
                    child: InkResponse(
                      key: ValueKey('avatar-$i'),
                      onTap: () => Navigator.of(context).pop(Avatar.animal(i)),
                      child: Center(
                        child: AvatarBubble(
                          avatar: Avatar.animal(i),
                          colour: myAvatar == Avatar.animal(i)
                              ? colour
                              : colour.withValues(alpha: 0.35),
                          radius: 24,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
