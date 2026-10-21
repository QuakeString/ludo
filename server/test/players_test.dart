import 'dart:io';
import 'dart:math';

import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';

void main() {
  group('players', () {
    test('a minted player is proven by its secret and nothing else', () {
      final store = PlayerStore(random: Random(1));
      final (player, secret) = store.mint(name: 'Rajat');
      expect(store.verify(player.id, secret), same(player));
      expect(store.verify(player.id, '${secret}x'), isNull);
      expect(store.verify(player.id, null), isNull);
      expect(store.verify('nobody', secret), isNull);
      expect(player.secretHash, isNot(contains(secret)),
          reason: 'the secret itself is never stored');
    });

    test('names are tidied, and a useless one becomes a guest name', () {
      expect(PlayerStore.cleanName('  Rajat   Roy '), 'Rajat Roy');
      expect(PlayerStore.cleanName('<script>'), 'script');
      expect(PlayerStore.cleanName('x'), isNull);
      expect(PlayerStore.cleanName('A' * 40), hasLength(16));
      final (guest, _) = PlayerStore(random: Random(2)).mint(name: '!');
      expect(guest.name, startsWith('Guest_'));
      expect(guest.chosenName, isFalse);
    });

    test('players survive a restart', () async {
      final dir = await Directory.systemTemp.createTemp('ludo-players');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/players.json');

      final before = PlayerStore(file: file, random: Random(3));
      final (player, secret) = before.mint(name: 'Ammu');
      await before.flush();

      final after = PlayerStore(file: file);
      await after.load();
      expect(after.verify(player.id, secret)?.name, 'Ammu');
    });

    test('a broken data file is kept aside, not lost', () async {
      final dir = await Directory.systemTemp.createTemp('ludo-players');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/players.json')..writeAsStringSync('{oops');
      final store = PlayerStore(file: file);
      await store.load();
      expect(store.length, 0);
      expect(
        dir.listSync().where((f) => f.path.contains('.broken-')),
        hasLength(1),
      );
    });
  });

  group('rate limit', () {
    test('a burst is fine, a flood is warned, then dropped, then cut off', () {
      final limiter = RateLimiter(burst: 5, perSecond: 1, patience: 3);
      final t = DateTime.utc(2026);
      for (var i = 0; i < 5; i++) {
        expect(limiter.take(t), Allowance.ok);
      }
      expect(limiter.take(t), Allowance.warn);
      expect(limiter.take(t), Allowance.drop);
      expect(limiter.take(t), Allowance.drop);
      expect(limiter.take(t), Allowance.disconnect);
    });

    test('the bucket refills with time', () {
      final limiter = RateLimiter(burst: 2, perSecond: 2);
      final t = DateTime.utc(2026);
      limiter.take(t);
      limiter.take(t);
      expect(limiter.take(t), Allowance.warn);
      expect(limiter.take(t.add(const Duration(seconds: 1))), Allowance.ok);
    });
  });
}
