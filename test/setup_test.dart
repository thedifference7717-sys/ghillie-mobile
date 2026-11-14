import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
import 'package:ghillie/wallet/vault.dart';

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
  testWidgets('create: password rules, words shown, 3 words checked, then home', (t) async {
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
    expect(t.widget<FilledButton>(find.byKey(const Key('setup-continue'))).onPressed, isNull);
    await tapKey(t, 'setup-wrote');
    await tapKey(t, 'setup-continue');

    final fields = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('setup-check-'));
    expect(fields, findsNWidgets(3));
    for (final e in fields.evaluate().toList()) {
      final i = int.parse((e.widget.key as ValueKey<String>).value.split('-').last);
      await t.enterText(find.byKey(e.widget.key!), i == 0 ? 'wrong' : DemoVault.sampleWords[i]);
    }
    await tapKey(t, 'setup-confirm');
    // word #1 may not have been asked; only expect an error if it was
    if (find.byKey(const Key('setup-check-0')).evaluate().isNotEmpty) {
      expect(find.byKey(const Key('setup-error')), findsOneWidget);
      await t.enterText(find.byKey(const Key('setup-check-0')), DemoVault.sampleWords[0]);
      await tapKey(t, 'setup-confirm');
    }
    expect(find.text('1,239.63'), findsOneWidget);
  });

  testWidgets('restore needs 25 words; unlock rejects a wrong password', (t) async {
    await phone(t);
    final v = DemoVault();
    await t.pumpWidget(GhillieApp(vault: v, showIntro: false));
    await tapKey(t, 'setup-restore');
    await t.enterText(find.byKey(const Key('setup-words')), 'only three words');
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await tapKey(t, 'setup-do-restore');
    expect(find.textContaining('you entered 3'), findsOneWidget);
    await t.enterText(find.byKey(const Key('setup-words')), DemoVault.sampleWords.join(' '));
    await tapKey(t, 'setup-do-restore');
    expect(find.text('1,239.63'), findsOneWidget);

    // next start: unlock screen
    await t.pumpWidget(GhillieApp(key: UniqueKey(), vault: v, showIntro: false));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('setup-pw')), 'nope nope');
    await tapKey(t, 'setup-unlock');
    expect(find.text('Wrong password.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await tapKey(t, 'setup-unlock');
    expect(find.text('1,239.63'), findsOneWidget);
  });
}
