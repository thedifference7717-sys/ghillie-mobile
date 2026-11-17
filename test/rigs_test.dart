import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/rigs/rigs.dart';
import 'package:ghillie/screens/rigs_screen.dart';
import 'package:ghillie/wallet/subscriptions.dart';

String code(Map<String, Object?> j) =>
    'ghillie-rig:${base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '')}';
final good = {
  'v': 1,
  'name': 'iMac',
  'net': 'stagenet',
  'host': '192.168.1.20',
  'port': 39760,
  'fp': 'ab' * 32,
  'secret': 'S' * 43,
};

class FakeRig implements RigClient {
  bool mining = false;
  int threads = 0;
  final calls = <String>[];
  RigStatus get _s => RigStatus(
    mining ? RigState.mining : RigState.stopped,
    hashrate: mining ? 1234 : 0,
    threads: threads,
    maxThreads: 3,
    height: 100,
    payout: 'QRDxe3VE…Lxcb',
  );
  @override
  Future<RigStatus> status(RigPairing r) async => _s;
  @override
  Future<RigStatus> start(RigPairing r, int n) async {
    calls.add('start $n');
    mining = true;
    threads = n;
    return _s;
  }

  @override
  Future<RigStatus> stop(RigPairing r) async {
    calls.add('stop');
    mining = false;
    threads = 0;
    return _s;
  }
}

void main() {
  test('pairing codes: accepts the helper format, refuses anything else', () {
    final r = RigPairing.parse(code(good))!;
    expect([r.name, r.network, r.host, r.port], ['iMac', 'stagenet', '192.168.1.20', 39760]);
    expect(RigPairing.parse('  ${code(good)}\n'), isNotNull);
    for (final bad in [
      {...good, 'fp': 'xyz'},
      {...good, 'secret': 'short'},
      {...good, 'host': 'evil.example.com'}, // IP addresses only: no DNS lookups for rigs
      {...good, 'net': 'monero'},
      {...good, 'v': 2},
      {...good, 'port': 70000},
    ]) {
      expect(RigPairing.parse(code(bad)), isNull, reason: '$bad');
    }
    expect(RigPairing.parse('camo:Cabc'), isNull);
    expect(RigPairing.parse('ghillie-rig:!!!'), isNull);
  });

  test('rig list is stored and pairing the same computer again replaces it', () async {
    final store = MemorySubscriptionStore();
    final l = RigList(store: store);
    await l.load();
    await l.put(RigPairing.parse(code(good))!);
    await l.put(RigPairing.parse(code({...good, 'secret': 'T' * 43, 'fp': 'cd' * 32}))!);
    final again = RigList(store: store);
    await again.load();
    expect(again.items.single.secret, 'T' * 43);
    await again.remove(again.items.single.id);
    expect(again.items, isEmpty);
  });

  testWidgets('pair, start with chosen threads, stop', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final rigs = RigList(store: MemorySubscriptionStore());
    final fake = FakeRig();
    await t.pumpWidget(
      MaterialApp(
        home: RigsScreen(rigs: rigs, client: fake, poll: const Duration(hours: 1)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('MINE FROM YOUR POCKET'), findsOneWidget);

    await t.tap(find.byKey(const Key('rig-pair')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('rig-code')), 'not a code');
    await t.tap(find.byKey(const Key('rig-pair-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('not a Ghillie pairing code'), findsOneWidget);
    await t.enterText(find.byKey(const Key('rig-code')), code(good));
    await t.tap(find.byKey(const Key('rig-pair-save')));
    await t.pumpAndSettle();

    final id = rigs.items.single.id;
    expect(find.text('iMac'), findsOneWidget);
    expect(find.text('STOPPED'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // defaults to the computer's cap
    await t.tap(find.byKey(Key('rig-minus-$id')));
    await t.pump();
    await t.tap(find.byKey(Key('rig-start-$id')));
    await t.pumpAndSettle();
    expect(fake.calls, ['start 2']);
    expect(find.textContaining('MINING · 1234 H/s · 2 of 3 threads'), findsOneWidget);
    await t.tap(find.byKey(Key('rig-stop-$id')));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'stop');
    expect(find.text('STOPPED'), findsOneWidget);
  });

  // Real TLS + pinning + secret against the real helper (no camod needed). Set CAMO_RIG_AGENT to its path.
  final agent = Platform.environment['CAMO_RIG_AGENT'];
  test('HttpRigClient against the real rig helper: pinning and secret', () async {
    HttpOverrides.global = null; // flutter_test fakes HTTP; use real sockets here
    final home = Directory.systemTemp.createTempSync('rig');
    final env = {'CAMO_RIG_HOME': home.path};
    final addr = 'Q${'R' * 96}';
    var r = await Process.run('python3', [agent!, 'setup', '--stagenet', '--address', addr], environment: env);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    r = await Process.run('python3', [agent, 'pair'], environment: env);
    final line = '${r.stdout}'.split('\n').firstWhere((l) => l.startsWith('ghillie-rig:'));
    final p = RigPairing.parse(line)!;
    final local = RigPairing(
      id: p.id,
      name: p.name,
      network: p.network,
      host: '127.0.0.1',
      port: p.port,
      fingerprint: p.fingerprint,
      secret: p.secret,
    );
    final proc = await Process.start('python3', [agent, 'run'], environment: env);
    proc.stderr.transform(const SystemEncoding().decoder).listen((e) => print('helper: $e'));
    proc.stdout.transform(const SystemEncoding().decoder).listen((e) => print('helper: $e'));
    addTearDown(() {
      proc.kill();
      home.deleteSync(recursive: true);
    });
    for (var i = 0; i < 50; i++) {
      try {
        (await Socket.connect('127.0.0.1', p.port)).destroy();
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    final c = HttpRigClient();
    expect((await c.status(local)).state, RigState.noCamod); // paired and talking; no camod running here
    final wrongFp = RigPairing(
      id: 'x',
      name: 'x',
      network: 'stagenet',
      host: '127.0.0.1',
      port: p.port,
      fingerprint: '00' * 32,
      secret: p.secret,
    );
    expect((await c.status(wrongFp)).state, RigState.wrongCertificate);
    final wrongSecret = RigPairing(
      id: 'y',
      name: 'y',
      network: 'stagenet',
      host: '127.0.0.1',
      port: p.port,
      fingerprint: p.fingerprint,
      secret: 'Z' * 43,
    );
    expect((await c.status(wrongSecret)).state, RigState.refused);
  }, skip: agent == null ? 'set CAMO_RIG_AGENT to run against the real helper' : false);
}
