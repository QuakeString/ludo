import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('every message survives the wire', () {
    final state = GameState.newGame(RuleConfig.sixSeat, seed: 5);
    final messages = <Envelope>[
      const Hello(guestId: 'g1', displayName: 'Rajat'),
      const Welcome(playerId: 'p1', displayName: 'Guest_4821'),
      CreateRoom(rules: RuleConfig.sixSeat, fillEmptySeatsWithAI: false),
      const JoinRoom('KX7P2Q'),
      const LeaveRoom(),
      const SetReady(true),
      const AddComputer(seat: 3, level: AiLevel.hard),
      const StartMatch(),
      Play.roll(),
      Play.pass(),
      const Play(action: 'move', tokenId: 4, toProgress: 12),
      MatchUpdate(state: state, yourSeat: 2, secondsLeft: 25),
      const Oops('it is not your turn', code: 'turn'),
      const Ping(),
      const Pong(),
    ];

    for (final m in messages) {
      final back = Envelope.decode(m.encode());
      expect(back.type, m.type, reason: m.type);
      expect(back.encode(), m.encode(), reason: m.type);
    }
  });

  test('a room round-trips with its seats', () {
    final room = RoomInfo(
      code: 'KX7P2Q',
      phase: RoomPhase.lobby,
      rules: RuleConfig.sixSeat,
      hostId: 'p1',
      seats: const [
        SeatInfo(seat: 0, playerId: 'p1', displayName: 'Rajat', ready: true),
        SeatInfo(seat: 1, isComputer: true),
        SeatInfo(seat: 2, playerId: 'p3', connected: false),
      ],
    );
    final back = RoomInfo.fromJson(room.toJson());
    expect(back.code, room.code);
    expect(back.seats, hasLength(3));
    expect(back.seats[1].isComputer, isTrue);
    expect(back.seats[2].connected, isFalse);
    expect(back.seats[0].isEmpty, isFalse);
  });

  test('a match update carries the move so the client can animate it', () {
    final state = GameState.newGame(const RuleConfig(), seed: 3);
    const move = Move(
      kind: MoveKind.advance,
      tokenIds: [2],
      owner: 0,
      steps: 3,
      fromProgress: 4,
      toProgress: 7,
      capturedTokenIds: [9],
    );
    final back = Envelope.decode(
            MatchUpdate(state: state, yourSeat: 0, lastMove: move).encode())
        as MatchUpdate;
    expect(back.lastMove!.tokenId, 2);
    expect(back.lastMove!.toProgress, 7);
    expect(back.lastMove!.capturedTokenIds, [9]);
    expect(back.state.fingerprint(), state.fingerprint());
  });

  test('every message added for playing online survives the wire', () {
    T trip<T extends Envelope>(T e) => Envelope.decode(e.encode()) as T;

    expect(trip(const Hello(transfer: 'ABCD2345')).transfer, 'ABCD2345');
    expect(
        trip(const Welcome(playerId: 'g1', displayName: 'A', rejoin: 'X'))
            .rejoin,
        'X');
    expect(trip(const QuickMatch(players: 2)).players, 2);
    expect(
        trip(const QueueUpdate(players: 4, found: 3, secondsToFill: 7))
            .secondsToFill,
        7);
    expect(trip(const SetName('Ammu')).name, 'Ammu');
    expect(trip(const Reaction(seat: 2, index: 1)).emoji, reactions[1]);
    expect(trip(const Say('nice one 🎉')).text, 'nice one 🎉');
    expect(trip(const SwapSeats(1, 2)).b, 2);
    expect(trip(const SetAvatar('a:3')).avatar, 'a:3');
    expect(trip(const SetAvatar(null)).avatar, isNull);
    expect(trip(const Said(seat: 1, text: 'gg 😂')).seat, 1);
    expect(trip(const AnswerFriend('g2', accept: true)).accept, isTrue);
    expect(trip(const SetNickname('g2', null)).nickname, isNull);
    expect(trip(const TransferCode(code: 'C', minutes: 10)).minutes, 10);

    final profile = ProfileInfo(
      playerId: 'g1',
      name: 'Ammu',
      friendCode: 'BCD234',
      xp: 260,
      played: 3,
      won: 1,
      friends: const [
        FriendInfo(playerId: 'g2', name: 'Rajat', nickname: 'R', online: true)
      ],
      history: [
        MatchSummary(
            at: DateTime.utc(2026, 10, 21),
            players: 4,
            place: 2,
            won: false,
            xp: 30,
            opponents: const ['Rajat', 'Computer']),
      ],
    );
    final back = trip(ProfileUpdate(profile)).profile;
    expect(back.level, 3);
    expect(back.friends.single.shownName, 'R');
    expect(back.history.single.opponents, ['Rajat', 'Computer']);
    expect(back.history.single.at, DateTime.utc(2026, 10, 21));
  });

  test('an unknown message is rejected rather than ignored', () {
    expect(() => Envelope.decode('{"t":"nonsense"}'), throwsFormatException);
  });

  test('avatars are an animal or a small photo, nothing else', () {
    expect(Avatar.animalOf(Avatar.animal(7)), 7);
    expect(Avatar.isValid('a:19'), isTrue);
    expect(Avatar.isValid('a:20'), isFalse);
    expect(Avatar.isValid('p:/9j/4AAQSkZJRg=='), isTrue);
    expect(Avatar.isValid('p:<script>'), isFalse);
    expect(Avatar.isValid('p:${'A' * Avatar.photoLimit}'), isFalse);
    expect(Avatar.isValid('x:1'), isFalse);
  });
}
