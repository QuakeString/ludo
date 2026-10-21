import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import '../theme/seat_colors.dart';
import 'avatars.dart';

/// Emoji offered from the chat bar's own button, for keyboards that make them
/// hard to reach. Anything the phone's keyboard can type works as well.
const chatEmoji = [
  '😀', '😂', '🤣', '😊', '😍', '😎', '🤔', '😮', '😢', '😭', //
  '😡', '🤯', '😴', '🥳', '😅', '🙏', '👍', '👎', '👏', '💪',
  '🔥', '🎉', '❤️', '💔', '⭐', '🎲', '🏆', '🍀', '😈', '👀',
];

/// How tall the chat bar is with its emoji panel shut.
const chatBarHeight = 56.0;

/// Where a player types to the rest of an online table, along the bottom of
/// the game. What they send shows at the top of everyone's board.
class ChatBar extends StatefulWidget {
  const ChatBar({super.key, required this.onSend});

  final ValueChanged<String> onSend;

  @override
  State<ChatBar> createState() => _ChatBarState();
}

class _ChatBarState extends State<ChatBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _emoji = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final line = _text.text.trim();
    if (line.isEmpty) return;
    widget.onSend(line);
    _text.clear();
    setState(() => _emoji = false);
  }

  /// Puts [e] where the cursor is, or at the end when there is none.
  void _insert(String e) {
    final v = _text.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, e);
    if (text.runes.length > chatLimit) return;
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + e.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    return Material(
      color: palette.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_emoji)
            SizedBox(
              height: 132,
              child: GridView.extent(
                key: const ValueKey('chat-emoji-grid'),
                maxCrossAxisExtent: 40,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                children: [
                  for (final e in chatEmoji)
                    InkResponse(
                      onTap: () => _insert(e),
                      child: Center(
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
          Container(
            height: chatBarHeight,
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('chat-emoji'),
                  tooltip: _emoji ? 'Keyboard' : 'Emoji',
                  onPressed: () {
                    setState(() => _emoji = !_emoji);
                    if (_emoji) {
                      _focus.unfocus();
                    } else {
                      _focus.requestFocus();
                    }
                  },
                  icon: Icon(
                    _emoji
                        ? Icons.keyboard_alt_outlined
                        : Icons.emoji_emotions_outlined,
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-input'),
                    controller: _text,
                    focusNode: _focus,
                    onTap: () => setState(() => _emoji = false),
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _send(),
                    inputFormatters: [_RuneLimit(chatLimit)],
                    decoration: InputDecoration(
                      hintText: 'Say something to the table',
                      isDense: true,
                      filled: true,
                      fillColor: palette.felt,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('chat-send'),
                  tooltip: 'Send',
                  onPressed: _text.text.trim().isEmpty ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [chatLimit] counted the way the server counts, so what is typed is what
/// arrives. TextField's own maxLength counts UTF-16 units, which charges an
/// emoji twice.
class _RuneLimit extends TextInputFormatter {
  _RuneLimit(this.limit);
  final int limit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.text.runes.length > limit ? oldValue : newValue;
}

/// A line of chat at the top of the board: who said it, with their picture,
/// on a faint wash of their colour as this player's board shows it.
class ChatLine extends StatelessWidget {
  const ChatLine({
    super.key,
    required this.who,
    required this.text,
    required this.colour,
    this.avatar,
  });

  /// Their picture, as [Avatar] writes it.
  final String? avatar;
  final String who;
  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final wash = Color.alphaBlend(
      colour.withValues(alpha: 0.22),
      palette.panel,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * -10),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colour.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AvatarBubble(avatar: avatar, colour: colour, radius: 14),
            const SizedBox(width: 8),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$who  ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: text),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
