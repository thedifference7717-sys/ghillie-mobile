import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
import 'package:ghillie/screens/settings_screen.dart';
import 'package:ghillie/wallet/demo_wallet.dart';
import 'package:ghillie/wallet/quick_unlock.dart';
import 'package:ghillie/wallet/vault.dart';
import 'package:ghillie/wallet/wallet_service.dart';

Future<void> phone(WidgetTester t) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> tapKey(WidgetTester t, String k) async {
  await t.ensureVisible(find.byKey(Key(k)));
  await t.tap(find.byKey(Key(k)));
  await t.pumpAndSettle();
}

void main() {
  nodeTests();
  settingsNodeTest();
  sensitiveTest();
  quickUnlockTests();
  lockTests();
  lockWithQuickTest();
  lockToIntroTest();
  testWidgets(
    'create: password rules, words shown, 3 words checked, then home',
    (t) async {
      await phone(t);
      await t.pumpWidget(GhillieApp(vault: DemoVault(), showIntro: false));
      await tapKey(t, 'setup-create');
      await t.enterText(find.byKey(const Key('setup-pw')), 'short');
      await t.enterText(find.byKey(const Key('setup-pw2')), 'short');
      await tapKey(t, 'setup-make');
      expect(find.textContaining('at least 8'), findsWidgets);

      await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
      await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
      await tapKey(t, 'setup-make');
      expect(find.text('Your 25 words'), findsOneWidget);
      expect(find.textContaining('Anyone with these words'), findsOneWidget);

      // continue is disabled until the user says they wrote the words down
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('setup-continue')))
            .onPressed,
        isNull,
      );
      await tapKey(t, 'setup-wrote');
      await tapKey(t, 'setup-continue');

      final fields = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('setup-check-'),
      );
      expect(fields, findsNWidgets(3));
      for (final e in fields.evaluate().toList()) {
        final i = int.parse(
          (e.widget.key as ValueKey<String>).value.split('-').last,
        );
        await t.enterText(
          find.byKey(e.widget.key!),
          i == 0 ? 'wrong' : DemoVault.sampleWords[i],
        );
      }
      await tapKey(t, 'setup-confirm');
      // word #1 may not have been asked; only expect an error if it was
      if (find.byKey(const Key('setup-check-0')).evaluate().isNotEmpty) {
        expect(find.byKey(const Key('setup-error')), findsOneWidget);
        await t.enterText(
          find.byKey(const Key('setup-check-0')),
          DemoVault.sampleWords[0],
        );
        await tapKey(t, 'setup-confirm');
      }
      expect(find.text('1,239.63'), findsOneWidget);
    },
  );

  testWidgets('restore needs 25 words; unlock rejects a wrong password', (
    t,
  ) async {
    await phone(t);
    final v = DemoVault();
    await t.pumpWidget(GhillieApp(vault: v, showIntro: false));
    await tapKey(t, 'setup-restore');
    await t.enterText(find.byKey(const Key('setup-words')), 'only three words');
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await tapKey(t, 'setup-do-restore');
    expect(find.textContaining('you entered 3'), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('setup-words')),
      DemoVault.sampleWords.join(' '),
    );
    await tapKey(t, 'setup-do-restore');
    expect(find.text('1,239.63'), findsOneWidget);

    // next start: unlock screen
    await t.pumpWidget(
      GhillieApp(key: UniqueKey(), vault: v, showIntro: false),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('setup-pw')), 'nope nope');
    await tapKey(t, 'setup-unlock');
    expect(find.text('Wrong password.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await tapKey(t, 'setup-unlock');
    expect(find.text('1,239.63'), findsOneWidget);
  });
}

class _NodeVault extends DemoVault {
  @override
  bool get askNode => true;
}

void nodeTests() {
  test('node addresses', () {
    expect(looksLikeNode('3.134.132.214:39741'), isTrue);
    expect(looksLikeNode('node.camocoin.org:19741'), isTrue);
    expect(looksLikeNode('[2001:db8::1]:39741'), isTrue);
    expect(looksLikeNode('3.134.132.214'), isFalse);
    expect(looksLikeNode('http://x:1'), isFalse);
    expect(looksLikeNode('x:70000'), isFalse);
  });

  testWidgets('phone setup asks for a node and refuses a bad one', (t) async {
    await phone(t);
    final v = _NodeVault()..node = '';
    await t.pumpWidget(GhillieApp(vault: v, showIntro: false));
    await tapKey(t, 'setup-create');
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-node')), 'not a node');
    await tapKey(t, 'setup-make');
    expect(find.textContaining('host:port'), findsWidgets);
    await t.enterText(
      find.byKey(const Key('setup-node')),
      '3.134.132.214:39741',
    );
    await tapKey(t, 'setup-make');
    expect(find.text('Your 25 words'), findsOneWidget);
    expect(v.node, '3.134.132.214:39741');
  });
}

class _NodeWallet extends DemoWallet {
  String node = '1.2.3.4:39749';
  @override
  bool get canChangeNode => true;
  @override
  SyncState get sync => SyncState(
    connected: true,
    walletHeight: 10,
    chainHeight: 10,
    nodeLabel: node,
  );
  @override
  Future<void> changeNode(String n) async {
    node = n;
    notifyListeners();
  }
}

void settingsNodeTest() {
  testWidgets('settings: change node, bad address refused', (t) async {
    await phone(t);
    final w = _NodeWallet();
    await t.pumpWidget(MaterialApp(home: SettingsScreen(wallet: w)));
    await t.tap(find.byKey(const Key('settings-node')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('node-field')), 'nope');
    await t.tap(find.byKey(const Key('node-save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Use host:port'), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('node-field')),
      '3.134.132.214:39749',
    );
    await t.tap(find.byKey(const Key('node-save')));
    await t.pumpAndSettle();
    expect(w.node, '3.134.132.214:39749');
    expect(find.textContaining('3.134.132.214:39749'), findsOneWidget);
  });
}

void sensitiveTest() {
  testWidgets('the 25 words are covered when the app goes to the background', (
    t,
  ) async {
    await phone(t);
    await t.pumpWidget(GhillieApp(vault: DemoVault(), showIntro: false));
    await tapKey(t, 'setup-create');
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await tapKey(t, 'setup-make');
    expect(find.byKey(const Key('sensitive-cover')), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(find.byKey(const Key('sensitive-cover')), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.byKey(const Key('sensitive-cover')), findsNothing);
  });
}

void quickUnlockTests() {
  testWidgets(
    'Face ID: opt in when creating, then unlock without typing; refusal falls back to the password',
    (t) async {
      await phone(t);
      final q = MemoryQuickUnlock();
      quickUnlock = q;
      addTearDown(() => quickUnlock = NoQuickUnlock());
      final v = DemoVault();
      await t.pumpWidget(GhillieApp(vault: v, showIntro: false));
      await tapKey(t, 'setup-create');
      await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
      await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
      await tapKey(t, 'setup-remember');
      await tapKey(t, 'setup-make');
      await tapKey(t, 'setup-wrote');
      await tapKey(t, 'setup-continue');
      for (final e
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key as ValueKey<String>).value.startsWith(
                      'setup-check-',
                    ),
              )
              .evaluate()
              .toList()) {
        final i = int.parse(
          (e.widget.key as ValueKey<String>).value.split('-').last,
        );
        await t.enterText(find.byKey(e.widget.key!), DemoVault.sampleWords[i]);
      }
      await tapKey(t, 'setup-confirm');
      expect(await q.isSet(), isTrue);

      // next start: Face ID is offered at once and opens the wallet
      await t.pumpWidget(
        GhillieApp(key: UniqueKey(), vault: v, showIntro: false),
      );
      await t.pumpAndSettle();
      expect(find.text('1,239.63'), findsOneWidget);

      // Face ID refused: stays on the unlock screen with a message; the password still works
      q.approve = false;
      await t.pumpWidget(
        GhillieApp(key: UniqueKey(), vault: v, showIntro: false),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('not confirmed'), findsOneWidget);
      expect(find.byKey(const Key('setup-quick')), findsOneWidget);
      await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
      await tapKey(t, 'setup-unlock');
      expect(find.text('1,239.63'), findsOneWidget);
    },
  );

  testWidgets('Face ID is off unless chosen', (t) async {
    await phone(t);
    final q = MemoryQuickUnlock();
    quickUnlock = q;
    addTearDown(() => quickUnlock = NoQuickUnlock());
    await t.pumpWidget(GhillieApp(vault: DemoVault(), showIntro: false));
    await tapKey(t, 'setup-restore');
    expect(find.byKey(const Key('setup-remember')), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('setup-words')),
      DemoVault.sampleWords.join(' '),
    );
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await tapKey(t, 'setup-do-restore');
    expect(await q.isSet(), isFalse);
  });
}

void lockTests() {
  Future<void> openSettings(WidgetTester t) async {
    await t.tap(find.bySemanticsLabel('Settings'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Settings: lock the wallet, then turn Face ID on with the password',
    (t) async {
      await phone(t);
      final q = MemoryQuickUnlock();
      quickUnlock = q;
      addTearDown(() => quickUnlock = NoQuickUnlock());
      final v = DemoVault();
      await t.pumpWidget(GhillieApp(vault: v, showIntro: false));
      await tapKey(t, 'setup-restore');
      await t.enterText(
        find.byKey(const Key('setup-words')),
        DemoVault.sampleWords.join(' '),
      );
      await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
      await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
      await tapKey(t, 'setup-do-restore');
      expect(await q.isSet(), isFalse);

      // lock
      await openSettings(t);
      await tapKey(t, 'settings-lock');
      expect(find.byKey(const Key('setup-unlock')), findsOneWidget);
      await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
      await tapKey(t, 'setup-unlock');
      expect(find.text('1,239.63'), findsOneWidget);

      // turn Face ID on: back to the unlock screen with the box ticked; the password proves it
      await openSettings(t);
      expect(find.textContaining('off · turn on'), findsOneWidget);
      await tapKey(t, 'settings-quick-on');
      expect(
        t
            .widget<CheckboxListTile>(find.byKey(const Key('setup-remember')))
            .value,
        isTrue,
      );
      await t.enterText(find.byKey(const Key('setup-pw')), 'wrong password');
      await tapKey(t, 'setup-unlock');
      expect(await q.isSet(), isFalse); // a wrong password is never saved
      await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
      await tapKey(t, 'setup-unlock');
      expect(await q.isSet(), isTrue);
      await openSettings(t);
      expect(find.textContaining('on · turn off'), findsOneWidget);
    },
  );
}

void lockWithQuickTest() {
  testWidgets('with Face ID on, Lock really locks: Face ID waits for a tap', (
    t,
  ) async {
    await phone(t);
    final q = MemoryQuickUnlock();
    quickUnlock = q;
    addTearDown(() => quickUnlock = NoQuickUnlock());
    await q.save('correct horse');
    final v = DemoVault(hasWallet: true);
    await v.restore(DemoVault.sampleWords, 'correct horse', 0);
    await t.pumpWidget(GhillieApp(vault: v, showIntro: false));
    await t.pumpAndSettle();
    expect(
      find.text('1,239.63'),
      findsOneWidget,
    ); // app start: Face ID opened it
    await t.tap(find.bySemanticsLabel('Settings'));
    await t.pumpAndSettle();
    await tapKey(t, 'settings-lock');
    expect(
      find.byKey(const Key('setup-quick')),
      findsOneWidget,
    ); // locked, waiting
    expect(find.text('1,239.63'), findsNothing);
    await tapKey(t, 'setup-quick');
    expect(find.text('1,239.63'), findsOneWidget);
  });
}

void lockToIntroTest() {
  testWidgets('Lock goes back to the opening screen', (t) async {
    await phone(t);
    final v = DemoVault();
    await v.restore(DemoVault.sampleWords, 'correct horse', 0);
    await t.pumpWidget(GhillieApp(vault: v)); // with the opening screen
    for (var k = 0; k < 10; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text('Skip'));
    for (var k = 0; k < 10; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.tap(find.byKey(const Key('setup-unlock')));
    for (var k = 0; k < 10; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.bySemanticsLabel('Settings'));
    for (var k = 0; k < 10; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.ensureVisible(find.byKey(const Key('settings-lock')));
    await t.tap(find.byKey(const Key('settings-lock')));
    for (var k = 0; k < 10; k++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Skip'), findsOneWidget); // the scope screen
    expect(find.byKey(const Key('setup-pw')), findsNothing);
  });
}
