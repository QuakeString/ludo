import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

void main() {
  extraRollTests();
  group('RuleConfig validation', () {
    test('presets are all valid', () {
      for (final preset in RuleConfig.presets) {
        expect(preset.validate, returnsNormally, reason: preset.name);
      }
    });

    test('seat count must be 2-6', () {
      expect(const RuleConfig(players: 1).validate,
          throwsA(isA<RuleConfigError>()));
      expect(const RuleConfig(players: 7).validate,
          throwsA(isA<RuleConfigError>()));
    });

    test('tokens per player must be 1-4', () {
      expect(const RuleConfig(tokensPerPlayer: 0).validate,
          throwsA(isA<RuleConfigError>()));
      expect(const RuleConfig(tokensPerPlayer: 5).validate,
          throwsA(isA<RuleConfigError>()));
      for (final n in [2, 3, 4]) {
        expect(RuleConfig(tokensPerPlayer: n).validate, returnsNormally);
      }
    });

    test('entry roll must be rollable, or 0 for any', () {
      expect(const RuleConfig(entryRoll: 7).validate,
          throwsA(isA<RuleConfigError>()));
      expect(const RuleConfig(entryRoll: 0).validate, returnsNormally);
    });

    test('teams must cover every seat exactly once', () {
      expect(
        const RuleConfig(players: 4, teams: [
          [0, 1],
          [2]
        ]).validate,
        throwsA(isA<RuleConfigError>()),
        reason: 'seat 3 is left out',
      );
      expect(
        const RuleConfig(players: 4, teams: [
          [0, 1],
          [1, 2, 3]
        ]).validate,
        throwsA(isA<RuleConfigError>()),
        reason: 'seat 1 is on two teams',
      );
      expect(
        const RuleConfig(players: 4, teams: [
          [0, 2],
          [1, 3]
        ]).validate,
        returnsNormally,
      );
    });

    test('teams must be the same size', () {
      expect(
        const RuleConfig(players: 6, teams: [
          [0, 1],
          [2, 3, 4, 5]
        ]).validate,
        throwsA(isA<RuleConfigError>()),
      );
      expect(
        const RuleConfig(players: 6, teams: [
          [0, 2, 4],
          [1, 3, 5]
        ]).validate,
        returnsNormally,
      );
    });

    test('a seat referenced by a team must exist', () {
      expect(
        const RuleConfig(players: 4, teams: [
          [0, 1],
          [2, 9]
        ]).validate,
        throwsA(isA<RuleConfigError>()),
      );
    });
  });

  group('teams', () {
    const teamed = RuleConfig(players: 6, teams: [
      [0, 2, 4],
      [1, 3, 5]
    ]);

    test('sameSide groups partners and separates opponents', () {
      expect(teamed.sameSide(0, 2), isTrue);
      expect(teamed.sameSide(0, 4), isTrue);
      expect(teamed.sameSide(0, 1), isFalse);
    });

    test('partnersOf excludes the player themselves', () {
      expect(teamed.partnersOf(0), [2, 4]);
      expect(teamed.partnersOf(3), [1, 5]);
    });

    test('without teams every seat is its own side', () {
      const solo = RuleConfig(players: 4);
      expect(solo.sameSide(0, 1), isFalse);
      expect(solo.sameSide(2, 2), isTrue);
      expect(solo.partnersOf(0), isEmpty);
    });
  });

  group('serialisation', () {
    test('JSON round-trips every field', () {
      const original = RuleConfig(
        name: 'House rules',
        players: 6,
        tokensPerPlayer: 3,
        entryRoll: 0,
        extraRollOnSix: false,
        captureGrantsExtraRoll: true,
        safeSquares: SafeSquares.none,
        exactHomeEntry: false,
        mustCaptureToWin: true,
        turnTimerDots: 6,
        teams: [
          [0, 2, 4],
          [1, 3, 5]
        ],
        pairMove: true,
        pairCapture: PairCapture.anyone,
      );
      final copy = RuleConfig.fromJson(original.toJson());
      expect(copy.toJson(), original.toJson());
      expect(copy.teams, original.teams);
      expect(copy.pairCapture, PairCapture.anyone);
      expect(copy.safeSquares, SafeSquares.none);
    });

    test('unknown JSON falls back to the defaults rather than throwing', () {
      final c = RuleConfig.fromJson({'players': 3, 'safeSquares': 'nonsense'});
      expect(c.players, 3);
      expect(c.safeSquares, const RuleConfig().safeSquares);
    });

    test('rule codes round-trip and are pasteable', () {
      final code = RuleConfig.sixSeat.toRuleCode();
      expect(code, startsWith('LUDO-'));
      expect(code, isNot(contains('=')));
      final back = RuleConfig.fromRuleCode(code);
      expect(back.toJson(), RuleConfig.sixSeat.toJson());
    });

    test('every preset round-trips through its code', () {
      for (final preset in RuleConfig.presets) {
        expect(RuleConfig.fromRuleCode(preset.toRuleCode()).toJson(),
            preset.toJson(),
            reason: preset.name);
      }
    });

    test('codes stay short — only the differences are written', () {
      // Classic says nothing at all; a heavily tweaked set is still typable.
      expect(RuleConfig.classic.toRuleCode().length, lessThan(16));
      expect(RuleConfig.quick.toRuleCode().length, lessThan(60));
      final busy = const RuleConfig(
        name: 'Teams 3v3',
        players: 6,
        tokensPerPlayer: 3,
        pairMove: true,
        turnTimerDots: 6,
        teams: [
          [0, 2, 4],
          [1, 3, 5]
        ],
      );
      expect(busy.toRuleCode().length, lessThan(140));
      expect(
          RuleConfig.fromRuleCode(busy.toRuleCode()).toJson(), busy.toJson());
    });

    test('a rule code survives whitespace and a missing prefix', () {
      final code = RuleConfig.quick.toRuleCode();
      expect(RuleConfig.fromRuleCode('  $code  ').toJson(),
          RuleConfig.quick.toJson());
      expect(RuleConfig.fromRuleCode(code.substring(5)).toJson(),
          RuleConfig.quick.toJson());
    });

    test('rubbish is rejected with a clear error', () {
      expect(() => RuleConfig.fromRuleCode('LUDO-not-a-code'),
          throwsA(isA<RuleConfigError>()));
      expect(
          () => RuleConfig.fromRuleCode(''), throwsA(isA<RuleConfigError>()));
    });

    test('a code carrying an invalid config is rejected, not loaded', () {
      final bad = const RuleConfig(players: 4, teams: [
        [0, 1],
        [2]
      ]).toRuleCode();
      expect(
          () => RuleConfig.fromRuleCode(bad), throwsA(isA<RuleConfigError>()));
    });
  });

  test('copyWith can clear teams back to a free-for-all', () {
    const teamed = RuleConfig(players: 4, teams: [
      [0, 2],
      [1, 3]
    ]);
    expect(teamed.copyWith(teams: null).isTeamGame, isFalse);
    expect(teamed.copyWith(name: 'x').isTeamGame, isTrue,
        reason: 'omitting teams must not clear them');
  });

  test('turn timer is dots times seconds', () {
    expect(
        const RuleConfig(turnTimerDots: 6, secondsPerDot: 5).turnSeconds, 30);
    expect(const RuleConfig().turnSeconds, 0, reason: 'off by default');
  });
}

/// Three ways to earn another throw.
void extraRollTests() {
  const engine = LudoEngine();

  test('knocking somebody off buys another roll', () {
    var s = GameState.newGame(const RuleConfig());
    final b = s.board;
    // Seat 0 three squares behind a chip of seat 1.
    final victim =
        (3 - b.startRing(s.armOf(1)) + b.trackLength) % b.trackLength;
    final tokens = [...s.tokens];
    tokens[0] = tokens[0].copyWith(progress: 2);
    tokens[4] = tokens[4].copyWith(progress: victim);
    s = s.copyWith(tokens: tokens, dice: 1);

    final capture = engine.legalMoves(s).firstWhere((m) => m.isCapture);
    final after = engine.apply(s, PlayMove(capture));

    expect(after.turn, 0, reason: 'the turn passed on after a capture');
    expect(after.awaitingRoll, isTrue, reason: 'no extra roll was granted');
  });

  test('bringing a chip home buys another roll', () {
    var s = GameState.newGame(const RuleConfig());
    final b = s.board;
    final tokens = [...s.tokens];
    // One step short of home, with a one to play.
    tokens[0] = tokens[0].copyWith(progress: b.finalProgress - 1);
    s = s.copyWith(tokens: tokens, dice: 1);

    final home = engine.legalMoves(s).firstWhere(
          (m) => b.isFinished(m.toProgress),
        );
    final after = engine.apply(s, PlayMove(home));

    expect(after.turn, 0, reason: 'the turn passed on after getting home');
    expect(after.awaitingRoll, isTrue, reason: 'no extra roll was granted');
  });

  test('an ordinary move ends the turn', () {
    var s = GameState.newGame(const RuleConfig());
    final tokens = [...s.tokens];
    tokens[0] = tokens[0].copyWith(progress: 4);
    s = s.copyWith(tokens: tokens, dice: 3);

    final move = engine.legalMoves(s).first;
    final after = engine.apply(s, PlayMove(move));
    expect(after.turn, isNot(0), reason: 'a plain move must hand the turn on');
  });

  test('the earned rolls can be switched off', () {
    const strict = RuleConfig(
      captureGrantsExtraRoll: false,
      finishGrantsExtraRoll: false,
    );
    var s = GameState.newGame(strict);
    final b = s.board;
    final tokens = [...s.tokens];
    tokens[0] = tokens[0].copyWith(progress: b.finalProgress - 1);
    s = s.copyWith(tokens: tokens, dice: 1);
    final home = engine.legalMoves(s).firstWhere(
          (m) => b.isFinished(m.toProgress),
        );
    expect(engine.apply(s, PlayMove(home)).turn, isNot(0));
  });
}
