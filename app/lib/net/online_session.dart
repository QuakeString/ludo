import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import 'connection.dart';

/// What the app knows about an online table.
///
/// The one rule this class exists to enforce: **the server is right**. Nothing
/// here ever applies a move to the game state. Taps become intents, intents go
/// down the wire, and the position only ever changes because a [MatchUpdate]
/// came back. That is why an online game and an offline game cannot drift —
/// there is only one place a rule is ever evaluated.
class OnlineSession extends ChangeNotifier {
  OnlineSession(this.connection) {
    _sub = connection.messages.listen(_receive);
  }

  final LudoConnection connection;
  late final StreamSubscription<Envelope> _sub;

  RoomInfo? room;

  /// The position, straight from the server.
  GameState? state;
  int? yourSeat;

  /// The move that produced [state], so the board can play it out rather than
  /// having chips appear somewhere new.
  Move? lastMove;
  int? secondsLeft;
  bool lastWasAutoPlay = false;

  /// The most recent complaint from the server, for showing to the player.
  String? error;

  /// Set when the socket goes away, so the UI can say so plainly.
  bool disconnected = false;

  String? get playerId => connection.playerId;
  String get myName => connection.displayName ?? 'Guest';

  bool get isHost => room != null && room!.hostId == playerId;
  bool get isMyTurn =>
      state != null && yourSeat != null && state!.turn == yourSeat;
  bool get inMatch => state != null && room?.phase != RoomPhase.lobby;

  /// Fired when a new position arrives, so the board can animate into it.
  final _matches = StreamController<MatchUpdate>.broadcast();
  Stream<MatchUpdate> get matches => _matches.stream;

  /// Reactions from the table, as they arrive.
  final _reactions = StreamController<Reaction>.broadcast();
  Stream<Reaction> get reactions => _reactions.stream;

  /// Chat from the table, as it arrives — this player's own lines included,
  /// once the server has passed them round.
  final _chat = StreamController<Said>.broadcast();
  Stream<Said> get chat => _chat.stream;

  /// This player's progress, friends and recent matches. Null until the
  /// server has sent it; ask with [refreshProfile].
  ProfileInfo? profile;

  /// A one-time code for moving to another phone, once one has been made.
  TransferCode? transferCode;

  /// Friends asking this player to their table.
  final _invites = StreamController<Invite>.broadcast();
  Stream<Invite> get invites => _invites.stream;

  /// Where the search for a quick match has got to, while there is one.
  QueueUpdate? queue;
  bool get searching => queue?.searching ?? false;

  /// A match this player dropped out of that still has their seat.
  String? get rejoinCode => connection.rejoin;

  bool get hasChosenName => connection.chosenName;

  bool _disposed = false;
  bool _reconnecting = false;

  /// Changing identity on purpose closes the socket; that is not a lost
  /// signal to recover from.
  bool _switching = false;

  // --- what the player can ask for -----------------------------------------

  void createRoom(RuleConfig rules, {bool fillEmptySeatsWithAI = false}) {
    error = null;
    connection.send(
      CreateRoom(rules: rules, fillEmptySeatsWithAI: fillEmptySeatsWithAI),
    );
  }

  void joinRoom(String code) {
    error = null;
    connection.rejoin = null;
    connection.send(JoinRoom(code.trim()));
  }

  void leaveRoom() {
    connection.send(const LeaveRoom());
    room = null;
    state = null;
    yourSeat = null;
    notifyListeners();
  }

  void setReady(bool ready) => connection.send(SetReady(ready));

  /// Filling an empty seat with a computer is the host's decision, never
  /// something that quietly happens to a table.
  void addComputer(int seat, AiLevel level) =>
      connection.send(AddComputer(seat: seat, level: level));

  void start() => connection.send(const StartMatch());

  /// Looks for strangers to play with.
  void quickMatch(int players) {
    error = null;
    queue = QueueUpdate(players: players, found: 1);
    connection.send(QuickMatch(players: players));
    notifyListeners();
  }

  void cancelQuickMatch() {
    queue = null;
    connection.send(const CancelMatch());
    notifyListeners();
  }

  void refreshProfile() => connection.send(const GetProfile());

  void addFriend(String code) {
    error = null;
    connection.send(AddFriend(code.trim()));
  }

  void answerFriend(String playerId, {required bool accept}) =>
      connection.send(AnswerFriend(playerId, accept: accept));

  void removeFriend(String playerId) => connection.send(RemoveFriend(playerId));

  void setNickname(String playerId, String? nickname) => connection.send(
    SetNickname(
      playerId,
      nickname == null || nickname.trim().isEmpty ? null : nickname.trim(),
    ),
  );

  void inviteFriend(String playerId) {
    error = null;
    connection.send(InviteFriend(playerId));
  }

  void makeTransferCode() => connection.send(const MakeTransferCode());

  /// Becomes, on this phone, the player who made [code] on another one.
  ///
  /// Throws when the code is refused. This device was somebody else until
  /// now, so what that somebody was doing is let go of first.
  Future<void> useTransferCode(String code) async {
    room = null;
    state = null;
    yourSeat = null;
    queue = null;
    profile = null;
    error = null;
    _switching = true;
    try {
      await connection.connect(transfer: code);
    } catch (_) {
      // The old identity is still the one this device has; go back to it.
      await connection.connect();
      rethrow;
    } finally {
      _switching = false;
      disconnected = false;
      notifyListeners();
    }
    error = null;
    refreshProfile();
  }

  /// Another game at the same table. The host's call, like starting.
  void rematch() => connection.send(const Rematch());

  void react(int index) => connection.send(React(index));

  void say(String text) => connection.send(Say(text));

  /// Host only, in the lobby: trade who sits in seats [a] and [b].
  void swapSeats(int a, int b) => connection.send(SwapSeats(a, b));

  void setName(String name) {
    error = null;
    connection.send(SetName(name));
  }

  void roll() => connection.send(Play.roll());
  void pass() => connection.send(Play.pass());
  void move(Move m) => connection.send(Play.move(m));
  void breakPair(int pairId) => connection.send(Play.breakPair(pairId));

  // --- what the server says ------------------------------------------------

  void _receive(Envelope message) {
    switch (message) {
      case RoomUpdate(room: final info):
        room = info;
        error = null;
        notifyListeners();

      case MatchUpdate():
        room = room?.copyWith(phase: RoomPhase.playing);
        state = message.state;
        yourSeat = message.yourSeat;
        lastMove = message.lastMove;
        secondsLeft = message.secondsLeft;
        lastWasAutoPlay = message.autoPlayed;
        _matches.add(message);
        notifyListeners();

      case Welcome():
        notifyListeners();

      case ProfileUpdate(profile: final p):
        profile = p;
        notifyListeners();

      case TransferCode():
        transferCode = message;
        notifyListeners();

      case Invite():
        _invites.add(message);

      case QueueUpdate():
        queue = message.searching ? message : null;
        notifyListeners();

      case Reaction():
        _reactions.add(message);

      case Said():
        _chat.add(message);

      case Oops(message: final text, code: final code):
        if (code == 'cooldown') queue = null;
        if (code == 'closed' && !_switching) {
          disconnected = true;
          _reconnect();
        }
        error = text;
        notifyListeners();

      default:
        break;
    }
  }

  /// Gets back to the table after the signal drops.
  ///
  /// A phone on the move loses its connection all the time, for a second or
  /// for a tunnel's worth. The server holds the seat for five minutes, so keep
  /// trying for about that long, backing off so a phone with no signal is not
  /// kept awake by it, and sit straight back down once through.
  Future<void> _reconnect() async {
    if (_reconnecting || _disposed) return;
    _reconnecting = true;
    try {
      var wait = const Duration(seconds: 1);
      final giveUp = DateTime.now().add(const Duration(minutes: 5));
      while (!_disposed && DateTime.now().isBefore(giveUp)) {
        await Future<void>.delayed(wait);
        if (_disposed) return;
        try {
          await connection.connect();
        } catch (_) {
          if (wait < const Duration(seconds: 15)) wait *= 2;
          continue;
        }
        if (_disposed) return;
        disconnected = false;
        error = null;
        final code = room?.code;
        if (code != null) {
          connection.send(JoinRoom(code));
        } else if (queue != null) {
          // The server forgot the search when the socket went; ask again.
          connection.send(QuickMatch(players: queue!.players));
        }
        notifyListeners();
        return;
      }
    } finally {
      _reconnecting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    _matches.close();
    _reactions.close();
    _chat.close();
    _invites.close();
    super.dispose();
  }
}
