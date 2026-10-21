import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:share_plus/share_plus.dart';

import '../net/online_session.dart';
import '../theme/seat_colors.dart';

/// Who you are online: your level, your friends, your last few games, and
/// how to take all of it to another phone.
///
/// Still no account. Everything here hangs off the identity this device was
/// given the first time it went online; the transfer code at the bottom is
/// the one way to carry it anywhere else.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.session});

  final OnlineSession session;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  OnlineSession get _session => widget.session;
  final _friendCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    _session.refreshProfile();
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _friendCode.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _addFriend() {
    final code = _friendCode.text.trim();
    if (code.isEmpty) return;
    _session.addFriend(code);
    _friendCode.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _nickname(FriendInfo friend) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(
        title: 'What do you call ${friend.name}?',
        initial: friend.nickname ?? '',
        hint: friend.name,
        help: 'Only you see this.',
      ),
    );
    if (name != null) _session.setNickname(friend.playerId, name);
  }

  Future<void> _unfriend(FriendInfo friend) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${friend.shownName}?'),
        content: const Text('You can add each other again with a code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure == true) _session.removeFriend(friend.playerId);
  }

  Future<void> _moveHere() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _TextDialog(
        title: 'Move here from another phone',
        initial: '',
        hint: 'Transfer code',
        help:
            'On your other phone, open Online, then your profile, and make a '
            'transfer code. This phone becomes that player; whoever it was '
            'playing as until now is left behind.',
        action: 'Move here',
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _session.useTransferCode(code);
      messenger.showSnackBar(
        SnackBar(content: Text('Welcome back, ${_session.myName}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'That code did not work. Codes work once, for ten minutes.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _session.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: profile == null
                ? const Center(child: CircularProgressIndicator())
                : _body(profile),
          ),
        ),
      ),
    );
  }

  Widget _body(ProfileInfo profile) {
    final level = levelFor(profile.xp);
    final theme = Theme.of(context);
    final error = _session.error;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: seatColors[2],
              child: Text(
                '${level.level}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text('Level ${level.level}'),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: level.into / level.need,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${level.into} of ${level.need} to level ${level.level + 1}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _Stat(label: 'Played', value: '${profile.played}'),
            _Stat(label: 'Won', value: '${profile.won}'),
            _Stat(
              label: 'Win rate',
              value: profile.played == 0
                  ? '–'
                  : '${(100 * profile.won / profile.played).round()}%',
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _Heading('Friends'),
        Card(
          child: ListTile(
            title: Text(
              profile.friendCode,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            subtitle: const Text('Your friend code. Give it to a friend.'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: profile.friendCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Friend code copied')),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Add me on Ludo! My friend code is '
                          '${profile.friendCode}.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _friendCode,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "A friend's code",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _addFriend(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _addFriend, child: const Text('Add')),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
        for (final request in profile.incoming)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add_alt_1),
            title: Text(request.name),
            subtitle: const Text('Wants to be friends'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () =>
                      _session.answerFriend(request.playerId, accept: false),
                  child: const Text('No'),
                ),
                FilledButton(
                  onPressed: () =>
                      _session.answerFriend(request.playerId, accept: true),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ),
        for (final friend in profile.friends)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _Presence(friend: friend),
            title: Text(friend.shownName),
            subtitle: Text(
              [
                if (friend.nickname != null) friend.name,
                'Level ${friend.level}',
                friend.online ? 'Online' : 'Offline',
              ].join(' · '),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (choice) =>
                  choice == 'name' ? _nickname(friend) : _unfriend(friend),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'name', child: Text('Give a nickname')),
                PopupMenuItem(value: 'remove', child: Text('Remove friend')),
              ],
            ),
          ),
        for (final sent in profile.outgoing)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(sent.name),
            subtitle: const Text('Request sent'),
            trailing: TextButton(
              onPressed: () => _session.removeFriend(sent.playerId),
              child: const Text('Cancel'),
            ),
          ),
        if (profile.friends.isEmpty &&
            profile.incoming.isEmpty &&
            profile.outgoing.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No friends yet. Swap codes with someone you play with, and '
              'you can see when they are online and ask them to your table.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 24),
        const _Heading('Recent games'),
        if (profile.history.isEmpty)
          const Text(
            'Finished online games show up here.',
            style: TextStyle(fontSize: 13),
          ),
        for (final match in profile.history)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              match.won ? Icons.emoji_events : Icons.sports_esports,
              color: match.won ? seatColors[2] : null,
            ),
            title: Text(
              match.won
                  ? 'Won'
                  : '${_ordinal(match.place)} of ${match.players}',
            ),
            subtitle: Text(
              [
                if (match.opponents.isNotEmpty)
                  'with ${match.opponents.join(', ')}',
                _when(match.at),
              ].join(' · '),
            ),
            trailing: Text('+${match.xp} XP'),
          ),
        const SizedBox(height: 24),
        const _Heading('Other phones'),
        if (_session.transferCode case final code?)
          Card(
            child: ListTile(
              title: SelectableText(
                code.code,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              subtitle: Text(
                'Enter this on your other phone within ${code.minutes} '
                'minutes. It works once.',
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _session.makeTransferCode,
            icon: const Icon(Icons.phonelink),
            label: const Text('Play as me on another phone'),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _moveHere,
          child: const Text('I already play on another phone'),
        ),
      ],
    );
  }

  static String _ordinal(int n) => switch (n) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${n}th',
  };

  static String _when(DateTime at) {
    final ago = DateTime.now().toUtc().difference(at);
    if (ago.inMinutes < 1) return 'just now';
    if (ago.inHours < 1) return '${ago.inMinutes} min ago';
    if (ago.inDays < 1) return '${ago.inHours} h ago';
    if (ago.inDays == 1) return 'yesterday';
    return '${ago.inDays} days ago';
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    ),
  );
}

/// A friend's initial, with a dot that is green while they are online.
class _Presence extends StatelessWidget {
  const _Presence({required this.friend});
  final FriendInfo friend;

  @override
  Widget build(BuildContext context) {
    final name = friend.shownName;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: friend.online ? const Color(0xFF2E9E5B) : Colors.grey,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.initial,
    required this.hint,
    this.help,
    this.action = 'Save',
  });

  final String title;
  final String initial;
  final String hint;
  final String? help;
  final String action;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.help != null) ...[
            Text(widget.help!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 16,
            decoration: InputDecoration(hintText: widget.hint),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
