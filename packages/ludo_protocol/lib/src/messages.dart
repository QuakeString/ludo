import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';

/// The version of this wire format.
///
/// Sent by the app in [Hello]. The server refuses anything older than it can
/// talk to with an [Oops] whose code is `update`, so a phone with an old copy of
/// the app is told to update instead of failing in some stranger way later.
const protocolVersion = 2;

/// What a room is doing right now.
enum RoomPhase { lobby, playing, finished }

/// One seat in a room, as everyone else sees it.
class SeatInfo {
  const SeatInfo({
    required this.seat,
    this.playerId,
    this.displayName,
    this.isComputer = false,
    this.connected = true,
    this.ready = false,
    this.level = 1,
    this.avatar,
  });

  final int seat;

  /// The player's picture, as [Avatar] writes it. Null for none chosen.
  final String? avatar;

  /// Null when the seat is empty.
  final String? playerId;
  final String? displayName;
  final bool isComputer;

  /// False while a player is away; their seat is held rather than freed.
  final bool connected;
  final bool ready;
  final int level;

  bool get isEmpty => playerId == null && !isComputer;

  Map<String, Object?> toJson() => {
        'seat': seat,
        if (playerId != null) 'playerId': playerId,
        if (displayName != null) 'name': displayName,
        'ai': isComputer,
        'connected': connected,
        'ready': ready,
        'level': level,
        if (avatar != null) 'avatar': avatar,
      };

  factory SeatInfo.fromJson(Map<String, Object?> j) => SeatInfo(
        seat: (j['seat'] as num).toInt(),
        playerId: j['playerId'] as String?,
        displayName: j['name'] as String?,
        isComputer: j['ai'] as bool? ?? false,
        connected: j['connected'] as bool? ?? true,
        ready: j['ready'] as bool? ?? false,
        level: (j['level'] as num?)?.toInt() ?? 1,
        avatar: j['avatar'] as String?,
      );
}

/// A player's picture, as it travels: `a:<n>` for one of the [animalCount]
/// drawn animals, or `p:<base64>` for a small photo of their own.
class Avatar {
  const Avatar._();

  static const animalCount = 20;

  /// The most a photo may take, encoded. A photo is shrunk on the phone to a
  /// thumbnail first, which comes in well under this.
  static const photoLimit = 24000;

  static String animal(int n) => 'a:$n';
  static String photo(String base64) => 'p:$base64';

  /// The animal [avatar] names, or null when it is not one.
  static int? animalOf(String? avatar) {
    if (avatar == null || !avatar.startsWith('a:')) return null;
    final n = int.tryParse(avatar.substring(2));
    return n != null && n >= 0 && n < animalCount ? n : null;
  }

  /// The photo [avatar] carries, still encoded, or null.
  static String? photoOf(String? avatar) =>
      avatar != null && avatar.startsWith('p:') ? avatar.substring(2) : null;

  /// Whether [avatar] is one the server will pass on.
  static bool isValid(String avatar) {
    if (animalOf(avatar) != null) return true;
    final p = photoOf(avatar);
    return p != null &&
        p.isNotEmpty &&
        avatar.length <= photoLimit &&
        RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(p);
  }
}

/// Everything the client needs to draw a lobby.
class RoomInfo {
  const RoomInfo({
    required this.code,
    required this.phase,
    required this.rules,
    required this.seats,
    required this.hostId,
    this.fillEmptySeatsWithAI = true,
  });

  final String code;
  final RoomPhase phase;
  final RuleConfig rules;
  final List<SeatInfo> seats;
  final String hostId;
  final bool fillEmptySeatsWithAI;

  RoomInfo copyWith({RoomPhase? phase}) => RoomInfo(
        code: code,
        phase: phase ?? this.phase,
        rules: rules,
        seats: seats,
        hostId: hostId,
        fillEmptySeatsWithAI: fillEmptySeatsWithAI,
      );

  Map<String, Object?> toJson() => {
        'code': code,
        'phase': phase.name,
        'rules': rules.toJson(),
        'seats': [for (final s in seats) s.toJson()],
        'host': hostId,
        'fillAi': fillEmptySeatsWithAI,
      };

  factory RoomInfo.fromJson(Map<String, Object?> j) => RoomInfo(
        code: j['code'] as String,
        phase: RoomPhase.values.firstWhere((p) => p.name == j['phase'],
            orElse: () => RoomPhase.lobby),
        rules: RuleConfig.fromJson(j['rules'] as Map<String, Object?>),
        seats: [
          for (final s in (j['seats'] as List))
            SeatInfo.fromJson(s as Map<String, Object?>)
        ],
        hostId: j['host'] as String? ?? '',
        fillEmptySeatsWithAI: j['fillAi'] as bool? ?? true,
      );
}

/// Base of everything that crosses the wire, in both directions.
///
/// One sealed family shared by the app and the server, so the two cannot drift
/// apart: a new message has to be added here, and both sides then fail to
/// compile until they handle it.
sealed class Envelope {
  const Envelope();

  String get type;
  Map<String, Object?> payload();

  String encode() => jsonEncode({'t': type, ...payload()});

  static Envelope decode(String raw) {
    final j = jsonDecode(raw) as Map<String, Object?>;
    final t = j['t'] as String?;
    return switch (t) {
      'hello' => Hello.fromJson(j),
      'welcome' => Welcome.fromJson(j),
      'createRoom' => CreateRoom.fromJson(j),
      'joinRoom' => JoinRoom.fromJson(j),
      'leaveRoom' => const LeaveRoom(),
      'setReady' => SetReady.fromJson(j),
      'addComputer' => AddComputer.fromJson(j),
      'swapSeats' => SwapSeats.fromJson(j),
      'setAvatar' => SetAvatar.fromJson(j),
      'kickAsk' => KickAsk.fromJson(j),
      'kickAnswer' => KickAnswer.fromJson(j),
      'startMatch' => const StartMatch(),
      'play' => Play.fromJson(j),
      'room' => RoomUpdate.fromJson(j),
      'match' => MatchUpdate.fromJson(j),
      'oops' => Oops.fromJson(j),
      'quickMatch' => QuickMatch.fromJson(j),
      'cancelMatch' => const CancelMatch(),
      'queue' => QueueUpdate.fromJson(j),
      'getProfile' => const GetProfile(),
      'addFriend' => AddFriend.fromJson(j),
      'answerFriend' => AnswerFriend.fromJson(j),
      'removeFriend' => RemoveFriend.fromJson(j),
      'setNickname' => SetNickname.fromJson(j),
      'inviteFriend' => InviteFriend.fromJson(j),
      'makeTransfer' => const MakeTransferCode(),
      'profile' => ProfileUpdate.fromJson(j),
      'invite' => Invite.fromJson(j),
      'transfer' => TransferCode.fromJson(j),
      'setName' => SetName.fromJson(j),
      'rematch' => const Rematch(),
      'react' => React.fromJson(j),
      'reaction' => Reaction.fromJson(j),
      'say' => Say.fromJson(j),
      'said' => Said.fromJson(j),
      'ping' => const Ping(),
      'pong' => const Pong(),
      _ => throw FormatException('unknown message "$t"'),
    };
  }
}

// --- app to server ---------------------------------------------------------

/// First thing a client sends. [guestId] and [secret] return an existing
/// anonymous identity; leaving them out asks the server to mint one.
///
/// The id alone is not enough to be somebody. Ids are public — every player at
/// a table sees everyone else's — so the server only accepts an id together
/// with the secret it handed out when it minted that id.
class Hello extends Envelope {
  const Hello({
    this.guestId,
    this.secret,
    this.displayName,
    this.version = protocolVersion,
    this.transfer,
  });
  final String? guestId;
  final String? secret;
  final String? displayName;

  /// A one-time code made on another phone, asking to become that player
  /// here as well. Takes the place of [guestId] and [secret].
  final String? transfer;

  /// The [protocolVersion] the sender speaks. Absent means the first version,
  /// from before the field existed.
  final int version;

  @override
  String get type => 'hello';
  @override
  Map<String, Object?> payload() => {
        if (guestId != null) 'guestId': guestId,
        if (secret != null) 'secret': secret,
        if (displayName != null) 'name': displayName,
        'v': version,
        if (transfer != null) 'transfer': transfer,
      };

  factory Hello.fromJson(Map<String, Object?> j) => Hello(
        guestId: j['guestId'] as String?,
        secret: j['secret'] as String?,
        displayName: j['name'] as String?,
        version: (j['v'] as num?)?.toInt() ?? 1,
        transfer: j['transfer'] as String?,
      );
}

class CreateRoom extends Envelope {
  const CreateRoom({required this.rules, this.fillEmptySeatsWithAI = true});
  final RuleConfig rules;

  /// The host's choice, never automatic — an empty seat may simply stay empty.
  final bool fillEmptySeatsWithAI;

  @override
  String get type => 'createRoom';
  @override
  Map<String, Object?> payload() =>
      {'rules': rules.toJson(), 'fillAi': fillEmptySeatsWithAI};

  factory CreateRoom.fromJson(Map<String, Object?> j) => CreateRoom(
        rules: RuleConfig.fromJson(j['rules'] as Map<String, Object?>),
        fillEmptySeatsWithAI: j['fillAi'] as bool? ?? true,
      );
}

class JoinRoom extends Envelope {
  const JoinRoom(this.code);
  final String code;

  @override
  String get type => 'joinRoom';
  @override
  Map<String, Object?> payload() => {'code': code};

  factory JoinRoom.fromJson(Map<String, Object?> j) =>
      JoinRoom(j['code'] as String);
}

class LeaveRoom extends Envelope {
  const LeaveRoom();
  @override
  String get type => 'leaveRoom';
  @override
  Map<String, Object?> payload() => const {};
}

class SetReady extends Envelope {
  const SetReady(this.ready);
  final bool ready;

  @override
  String get type => 'setReady';
  @override
  Map<String, Object?> payload() => {'ready': ready};

  factory SetReady.fromJson(Map<String, Object?> j) =>
      SetReady(j['ready'] as bool? ?? false);
}

/// Host fills an empty seat with a computer player.
class AddComputer extends Envelope {
  const AddComputer({required this.seat, this.level = AiLevel.normal});
  final int seat;
  final AiLevel level;

  @override
  String get type => 'addComputer';
  @override
  Map<String, Object?> payload() => {'seat': seat, 'level': level.name};

  factory AddComputer.fromJson(Map<String, Object?> j) => AddComputer(
        seat: (j['seat'] as num).toInt(),
        level: AiLevel.values.firstWhere((l) => l.name == j['level'],
            orElse: () => AiLevel.normal),
      );
}

/// The picture to show for this player at every table, as [Avatar] writes
/// it. Null takes it away.
class SetAvatar extends Envelope {
  const SetAvatar(this.avatar);
  final String? avatar;

  @override
  String get type => 'setAvatar';
  @override
  Map<String, Object?> payload() => {if (avatar != null) 'avatar': avatar};

  factory SetAvatar.fromJson(Map<String, Object?> j) =>
      SetAvatar(j['avatar'] as String?);
}

/// The host's answer to a [KickAsk]: [keep] gives the player another run of
/// chances; false takes them off the table now.
class KickAnswer extends Envelope {
  const KickAnswer({required this.seat, required this.keep});
  final int seat;
  final bool keep;

  @override
  String get type => 'kickAnswer';
  @override
  Map<String, Object?> payload() => {'seat': seat, 'keep': keep};

  factory KickAnswer.fromJson(Map<String, Object?> j) => KickAnswer(
        seat: (j['seat'] as num).toInt(),
        keep: j['keep'] as bool? ?? false,
      );
}

/// Host moves whoever is in seat [a] to seat [b] and back, before the start.
/// In a team game the seats are the teams, so this is how the host decides
/// who partners whom.
class SwapSeats extends Envelope {
  const SwapSeats(this.a, this.b);
  final int a;
  final int b;

  @override
  String get type => 'swapSeats';
  @override
  Map<String, Object?> payload() => {'a': a, 'b': b};

  factory SwapSeats.fromJson(Map<String, Object?> j) =>
      SwapSeats((j['a'] as num).toInt(), (j['b'] as num).toInt());
}

class StartMatch extends Envelope {
  const StartMatch();
  @override
  String get type => 'startMatch';
  @override
  Map<String, Object?> payload() => const {};
}

/// A move intent. The client never sends a resulting state — only what it
/// wants to do — so it cannot talk the server out of the rules.
class Play extends Envelope {
  const Play(
      {required this.action, this.tokenId, this.toProgress, this.pairId});

  /// One of: roll, move, pass, formPair, breakPair.
  final String action;
  final int? tokenId;
  final int? toProgress;
  final int? pairId;

  @override
  String get type => 'play';
  @override
  Map<String, Object?> payload() => {
        'a': action,
        if (tokenId != null) 'token': tokenId,
        if (toProgress != null) 'to': toProgress,
        if (pairId != null) 'pair': pairId,
      };

  factory Play.fromJson(Map<String, Object?> j) => Play(
        action: j['a'] as String,
        tokenId: (j['token'] as num?)?.toInt(),
        toProgress: (j['to'] as num?)?.toInt(),
        pairId: (j['pair'] as num?)?.toInt(),
      );

  static Play roll() => const Play(action: 'roll');
  static Play pass() => const Play(action: 'pass');
  static Play move(Move m) => Play(
        action: 'move',
        tokenId: m.tokenId,
        toProgress: m.toProgress,
      );
  static Play breakPair(int pairId) =>
      Play(action: 'breakPair', pairId: pairId);
}

/// Table sizes a player can ask to be matched into.
const quickMatchSizes = [2, 4];

/// Asks to be seated with whoever else is looking for a game of [players].
class QuickMatch extends Envelope {
  const QuickMatch({this.players = 4});
  final int players;

  @override
  String get type => 'quickMatch';
  @override
  Map<String, Object?> payload() => {'players': players};

  factory QuickMatch.fromJson(Map<String, Object?> j) =>
      QuickMatch(players: (j['players'] as num?)?.toInt() ?? 4);
}

/// Stops looking for a game.
class CancelMatch extends Envelope {
  const CancelMatch();
  @override
  String get type => 'cancelMatch';
  @override
  Map<String, Object?> payload() => const {};
}

/// Asks for this player's [ProfileUpdate]. One is also sent unasked whenever
/// it changes.
class GetProfile extends Envelope {
  const GetProfile();
  @override
  String get type => 'getProfile';
  @override
  Map<String, Object?> payload() => const {};
}

/// Sends a friend request to whoever has this friend code. If they had
/// already asked, the two are friends at once.
class AddFriend extends Envelope {
  const AddFriend(this.code);
  final String code;

  @override
  String get type => 'addFriend';
  @override
  Map<String, Object?> payload() => {'code': code};

  factory AddFriend.fromJson(Map<String, Object?> j) =>
      AddFriend(j['code'] as String? ?? '');
}

/// Accepts or declines a friend request from [playerId].
class AnswerFriend extends Envelope {
  const AnswerFriend(this.playerId, {required this.accept});
  final String playerId;
  final bool accept;

  @override
  String get type => 'answerFriend';
  @override
  Map<String, Object?> payload() => {'id': playerId, 'accept': accept};

  factory AnswerFriend.fromJson(Map<String, Object?> j) =>
      AnswerFriend(j['id'] as String? ?? '',
          accept: j['accept'] as bool? ?? false);
}

/// Unfriends [playerId], or withdraws a request sent to them.
class RemoveFriend extends Envelope {
  const RemoveFriend(this.playerId);
  final String playerId;

  @override
  String get type => 'removeFriend';
  @override
  Map<String, Object?> payload() => {'id': playerId};

  factory RemoveFriend.fromJson(Map<String, Object?> j) =>
      RemoveFriend(j['id'] as String? ?? '');
}

/// What this player calls a friend. Only they see it; null goes back to the
/// friend's own name.
class SetNickname extends Envelope {
  const SetNickname(this.playerId, this.nickname);
  final String playerId;
  final String? nickname;

  @override
  String get type => 'setNickname';
  @override
  Map<String, Object?> payload() =>
      {'id': playerId, if (nickname != null) 'nick': nickname};

  factory SetNickname.fromJson(Map<String, Object?> j) =>
      SetNickname(j['id'] as String? ?? '', j['nick'] as String?);
}

/// Asks an online friend to the table this player is sitting at.
class InviteFriend extends Envelope {
  const InviteFriend(this.playerId);
  final String playerId;

  @override
  String get type => 'inviteFriend';
  @override
  Map<String, Object?> payload() => {'id': playerId};

  factory InviteFriend.fromJson(Map<String, Object?> j) =>
      InviteFriend(j['id'] as String? ?? '');
}

/// Asks for a one-time code to carry this player to another phone.
class MakeTransferCode extends Envelope {
  const MakeTransferCode();
  @override
  String get type => 'makeTransfer';
  @override
  Map<String, Object?> payload() => const {};
}

/// The player picks the name everyone else sees. The server tidies it and
/// answers with a fresh [Welcome].
class SetName extends Envelope {
  const SetName(this.name);
  final String name;

  @override
  String get type => 'setName';
  @override
  Map<String, Object?> payload() => {'name': name};

  factory SetName.fromJson(Map<String, Object?> j) =>
      SetName(j['name'] as String? ?? '');
}

/// The host asks for another game at the same table, with the same seats.
class Rematch extends Envelope {
  const Rematch();
  @override
  String get type => 'rematch';
  @override
  Map<String, Object?> payload() => const {};
}

/// The fixed set of reactions a player can send at the table.
///
/// Fixed rather than free text on purpose: there is nothing to moderate in a
/// thumbs up, and strangers at a table can still say "nice one".
const reactions = ['👍', '😂', '😮', '😡', '🎉', '😢'];

/// One of [reactions], by index, sent to the rest of the table.
class React extends Envelope {
  const React(this.index);
  final int index;

  @override
  String get type => 'react';
  @override
  Map<String, Object?> payload() => {'i': index};

  factory React.fromJson(Map<String, Object?> j) =>
      React((j['i'] as num?)?.toInt() ?? -1);
}

/// The longest chat line, in characters. Long enough for a sentence, short
/// enough that a line across the top of the board stays one line or two.
const chatLimit = 140;

/// A line of chat for the rest of the table. Emoji are just characters here.
class Say extends Envelope {
  const Say(this.text);
  final String text;

  @override
  String get type => 'say';
  @override
  Map<String, Object?> payload() => {'text': text};

  factory Say.fromJson(Map<String, Object?> j) =>
      Say(j['text'] as String? ?? '');
}

// --- server to app ---------------------------------------------------------

/// Where a player looking for a game has got to.
///
/// [searching] false means they are no longer in the queue: a match was
/// found (a room update follows) or they cancelled.
class QueueUpdate extends Envelope {
  const QueueUpdate({
    required this.players,
    required this.found,
    this.searching = true,
    this.secondsToFill,
  });

  /// The size of table being looked for.
  final int players;

  /// How many people are waiting for one, this player included.
  final int found;
  final bool searching;

  /// Seconds until the table is dealt anyway, with computers in the empty
  /// seats.
  final int? secondsToFill;

  @override
  String get type => 'queue';
  @override
  Map<String, Object?> payload() => {
        'players': players,
        'found': found,
        'searching': searching,
        if (secondsToFill != null) 'fill': secondsToFill,
      };

  factory QueueUpdate.fromJson(Map<String, Object?> j) => QueueUpdate(
        players: (j['players'] as num).toInt(),
        found: (j['found'] as num?)?.toInt() ?? 1,
        searching: j['searching'] as bool? ?? true,
        secondsToFill: (j['fill'] as num?)?.toInt(),
      );
}

/// The experience a player needs to go from [level] to the next one. Each
/// level asks a little more than the last.
int xpToNext(int level) => 100 + 50 * (level - 1);

/// The level [xp] has reached, and how far into it.
({int level, int into, int need}) levelFor(int xp) {
  var level = 1;
  var left = xp < 0 ? 0 : xp;
  while (left >= xpToNext(level)) {
    left -= xpToNext(level);
    level++;
  }
  return (level: level, into: left, need: xpToNext(level));
}

/// Another player as this one sees them: a friend, or a request either way.
class FriendInfo {
  const FriendInfo({
    required this.playerId,
    required this.name,
    this.nickname,
    this.online = false,
    this.level = 1,
  });

  final String playerId;
  final String name;

  /// What this player calls them, if they have given them a name of their own.
  final String? nickname;
  final bool online;
  final int level;

  String get shownName => nickname ?? name;

  Map<String, Object?> toJson() => {
        'id': playerId,
        'name': name,
        if (nickname != null) 'nick': nickname,
        'online': online,
        'level': level,
      };

  factory FriendInfo.fromJson(Map<String, Object?> j) => FriendInfo(
        playerId: j['id'] as String,
        name: j['name'] as String? ?? 'Player',
        nickname: j['nick'] as String?,
        online: j['online'] as bool? ?? false,
        level: (j['level'] as num?)?.toInt() ?? 1,
      );
}

/// One finished match, from this player's chair.
class MatchSummary {
  const MatchSummary({
    required this.at,
    required this.players,
    required this.place,
    required this.won,
    required this.xp,
    this.opponents = const [],
  });

  final DateTime at;
  final int players;
  final int place;
  final bool won;

  /// Experience this match earned.
  final int xp;

  /// Everyone else at the table, by name.
  final List<String> opponents;

  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'players': players,
        'place': place,
        'won': won,
        'xp': xp,
        'with': opponents,
      };

  factory MatchSummary.fromJson(Map<String, Object?> j) => MatchSummary(
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt(),
            isUtc: true),
        players: (j['players'] as num?)?.toInt() ?? 2,
        place: (j['place'] as num?)?.toInt() ?? 1,
        won: j['won'] as bool? ?? false,
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        opponents: [
          for (final o in (j['with'] as List? ?? const [])) o as String
        ],
      );
}

/// Everything about this player: progress, friends and recent matches.
class ProfileInfo {
  const ProfileInfo({
    required this.playerId,
    required this.name,
    required this.friendCode,
    this.xp = 0,
    this.played = 0,
    this.won = 0,
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.history = const [],
  });

  final String playerId;
  final String name;

  /// What a friend types to send this player a request. Not the player id:
  /// that is shown at every table, and a code can be handed out on purpose.
  final String friendCode;
  final int xp;
  final int played;
  final int won;
  final List<FriendInfo> friends;

  /// Requests from others, waiting on this player.
  final List<FriendInfo> incoming;

  /// Requests this player sent that have not been answered.
  final List<FriendInfo> outgoing;

  /// Most recent first.
  final List<MatchSummary> history;

  int get level => levelFor(xp).level;

  Map<String, Object?> toJson() => {
        'id': playerId,
        'name': name,
        'code': friendCode,
        'xp': xp,
        'played': played,
        'won': won,
        'friends': [for (final f in friends) f.toJson()],
        'in': [for (final f in incoming) f.toJson()],
        'out': [for (final f in outgoing) f.toJson()],
        'history': [for (final m in history) m.toJson()],
      };

  factory ProfileInfo.fromJson(Map<String, Object?> j) {
    List<FriendInfo> people(Object? list) => [
          for (final f in (list as List? ?? const []))
            FriendInfo.fromJson(f as Map<String, Object?>)
        ];
    return ProfileInfo(
      playerId: j['id'] as String,
      name: j['name'] as String? ?? 'Player',
      friendCode: j['code'] as String? ?? '',
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      played: (j['played'] as num?)?.toInt() ?? 0,
      won: (j['won'] as num?)?.toInt() ?? 0,
      friends: people(j['friends']),
      incoming: people(j['in']),
      outgoing: people(j['out']),
      history: [
        for (final m in (j['history'] as List? ?? const []))
          MatchSummary.fromJson(m as Map<String, Object?>)
      ],
    );
  }
}

class ProfileUpdate extends Envelope {
  const ProfileUpdate(this.profile);
  final ProfileInfo profile;

  @override
  String get type => 'profile';
  @override
  Map<String, Object?> payload() => {'profile': profile.toJson()};

  factory ProfileUpdate.fromJson(Map<String, Object?> j) =>
      ProfileUpdate(ProfileInfo.fromJson(j['profile'] as Map<String, Object?>));
}

/// A friend asks this player to their table.
class Invite extends Envelope {
  const Invite({required this.from, required this.code});
  final FriendInfo from;
  final String code;

  @override
  String get type => 'invite';
  @override
  Map<String, Object?> payload() => {'from': from.toJson(), 'code': code};

  factory Invite.fromJson(Map<String, Object?> j) => Invite(
        from: FriendInfo.fromJson(j['from'] as Map<String, Object?>),
        code: j['code'] as String,
      );
}

/// A one-time code for carrying this player to another phone.
class TransferCode extends Envelope {
  const TransferCode({required this.code, required this.minutes});
  final String code;

  /// How long it stays usable.
  final int minutes;

  @override
  String get type => 'transfer';
  @override
  Map<String, Object?> payload() => {'code': code, 'minutes': minutes};

  factory TransferCode.fromJson(Map<String, Object?> j) => TransferCode(
        code: j['code'] as String,
        minutes: (j['minutes'] as num?)?.toInt() ?? 10,
      );
}

/// Somebody at the table sent one of the [reactions].
class Reaction extends Envelope {
  const Reaction({required this.seat, required this.index});
  final int seat;
  final int index;

  String get emoji => reactions[index.clamp(0, reactions.length - 1)];

  @override
  String get type => 'reaction';
  @override
  Map<String, Object?> payload() => {'seat': seat, 'i': index};

  factory Reaction.fromJson(Map<String, Object?> j) => Reaction(
        seat: (j['seat'] as num).toInt(),
        index: (j['i'] as num).toInt(),
      );
}

/// Sent to the host: the player in [seat] has let the clock run out [missed]
/// turns running. Unless the host answers within [seconds] that they may stay,
/// the computer takes their seat.
class KickAsk extends Envelope {
  const KickAsk({
    required this.seat,
    required this.name,
    required this.missed,
    required this.seconds,
  });
  final int seat;
  final String name;
  final int missed;
  final int seconds;

  @override
  String get type => 'kickAsk';
  @override
  Map<String, Object?> payload() =>
      {'seat': seat, 'name': name, 'missed': missed, 'seconds': seconds};

  factory KickAsk.fromJson(Map<String, Object?> j) => KickAsk(
        seat: (j['seat'] as num).toInt(),
        name: j['name'] as String? ?? 'A player',
        missed: (j['missed'] as num?)?.toInt() ?? 0,
        seconds: (j['seconds'] as num?)?.toInt() ?? 10,
      );
}

/// Somebody at the table said something.
class Said extends Envelope {
  const Said({required this.seat, required this.text});
  final int seat;
  final String text;

  @override
  String get type => 'said';
  @override
  Map<String, Object?> payload() => {'seat': seat, 'text': text};

  factory Said.fromJson(Map<String, Object?> j) => Said(
        seat: (j['seat'] as num).toInt(),
        text: j['text'] as String? ?? '',
      );
}

class Welcome extends Envelope {
  const Welcome({
    required this.playerId,
    required this.displayName,
    this.secret,
    this.chosenName = false,
    this.rejoin,
  });
  final String playerId;
  final String displayName;

  /// The code of a match this player dropped out of and can still take their
  /// seat back in. Null when there is none.
  final String? rejoin;

  /// Only sent when the server has just minted [playerId]. The app keeps it
  /// and sends it back in every later [Hello]; nobody else ever sees it.
  final String? secret;

  /// Whether the player picked [displayName] themselves, rather than being
  /// handed a `Guest_1234`. The app asks for a name once while this is false.
  final bool chosenName;

  @override
  String get type => 'welcome';
  @override
  Map<String, Object?> payload() => {
        'playerId': playerId,
        'name': displayName,
        if (secret != null) 'secret': secret,
        'chosen': chosenName,
        if (rejoin != null) 'rejoin': rejoin,
      };

  factory Welcome.fromJson(Map<String, Object?> j) => Welcome(
        playerId: j['playerId'] as String,
        displayName: j['name'] as String,
        secret: j['secret'] as String?,
        chosenName: j['chosen'] as bool? ?? false,
        rejoin: j['rejoin'] as String?,
      );
}

class RoomUpdate extends Envelope {
  const RoomUpdate(this.room);
  final RoomInfo room;

  @override
  String get type => 'room';
  @override
  Map<String, Object?> payload() => {'room': room.toJson()};

  factory RoomUpdate.fromJson(Map<String, Object?> j) =>
      RoomUpdate(RoomInfo.fromJson(j['room'] as Map<String, Object?>));
}

/// The authoritative position after something happened.
///
/// [yourSeat] saves the client working out which of the seats is theirs, and
/// [secondsLeft] drives the turn clock without the client having to trust its
/// own idea of when the turn started.
class MatchUpdate extends Envelope {
  const MatchUpdate({
    required this.state,
    required this.yourSeat,
    this.lastMove,
    this.secondsLeft,
    this.autoPlayed = false,
  });

  final GameState state;
  final int yourSeat;

  /// What just happened, so the client can animate it rather than snap.
  final Move? lastMove;
  final int? secondsLeft;

  /// True when the clock ran out and the server moved for someone.
  final bool autoPlayed;

  @override
  String get type => 'match';
  @override
  Map<String, Object?> payload() => {
        'state': state.toJson(),
        'seat': yourSeat,
        if (lastMove != null)
          'move': {
            'kind': lastMove!.kind.name,
            'tokens': lastMove!.tokenIds,
            'owner': lastMove!.owner,
            'from': lastMove!.fromProgress,
            'to': lastMove!.toProgress,
            'captured': lastMove!.capturedTokenIds,
          },
        if (secondsLeft != null) 'secs': secondsLeft,
        'auto': autoPlayed,
      };

  factory MatchUpdate.fromJson(Map<String, Object?> j) {
    final m = j['move'] as Map<String, Object?>?;
    return MatchUpdate(
      state: GameState.fromJson(j['state'] as Map<String, Object?>),
      yourSeat: (j['seat'] as num).toInt(),
      lastMove: m == null
          ? null
          : Move(
              kind: MoveKind.values.firstWhere((k) => k.name == m['kind'],
                  orElse: () => MoveKind.advance),
              tokenIds: [
                for (final t in (m['tokens'] as List)) (t as num).toInt()
              ],
              owner: (m['owner'] as num).toInt(),
              steps: 0,
              fromProgress: (m['from'] as num).toInt(),
              toProgress: (m['to'] as num).toInt(),
              capturedTokenIds: [
                for (final c in (m['captured'] as List? ?? const []))
                  (c as num).toInt()
              ],
            ),
      secondsLeft: (j['secs'] as num?)?.toInt(),
      autoPlayed: j['auto'] as bool? ?? false,
    );
  }
}

/// Something was refused. Carrying the reason matters: the client shows it
/// rather than silently doing nothing.
class Oops extends Envelope {
  const Oops(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String get type => 'oops';
  @override
  Map<String, Object?> payload() =>
      {'msg': message, if (code != null) 'code': code};

  factory Oops.fromJson(Map<String, Object?> j) =>
      Oops(j['msg'] as String, code: j['code'] as String?);
}

class Ping extends Envelope {
  const Ping();
  @override
  String get type => 'ping';
  @override
  Map<String, Object?> payload() => const {};
}

class Pong extends Envelope {
  const Pong();
  @override
  String get type => 'pong';
  @override
  Map<String, Object?> payload() => const {};
}
