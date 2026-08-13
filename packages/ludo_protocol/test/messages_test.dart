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

  test('an unknown message is rejected rather than ignored', () {
    expect(() => Envelope.decode('{"t":"nonsense"}'), throwsFormatException);
  });
}
