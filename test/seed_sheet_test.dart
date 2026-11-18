import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
import 'package:ghillie/screens/recovery_words_screen.dart';
import 'package:ghillie/screens/setup_screen.dart';
import 'package:ghillie/wallet/password_check.dart';
import 'package:ghillie/wallet/quick_unlock.dart';
import 'package:ghillie/wallet/demo_wallet.dart';
import 'package:ghillie/wallet/subscriptions.dart';
import 'package:ghillie/wallet/wallet_meta.dart';
import 'package:ghillie/ui/seed_sheet.dart';
import 'package:ghillie/wallet/vault.dart';
import 'package:pdf/pdf.dart';

void main() {
  test('the sheet has all 25 words, numbered, on one page', () async {
    final bytes = await seedSheetPdf(DemoVault.sampleWords, PdfPageFormat.letter, compress: false);
    final text = latin1.decode(bytes);
    expect(text.startsWith('%PDF'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1);
    for (final w in DemoVault.sampleWords) {
      expect(text, contains('($w)'), reason: w);
    }
    final out = Platform.environment['SEED_SHEET_OUT']; // for a visual check
    if (out != null) {
      final long = [...DemoVault.sampleWords.take(22), 'verification', 'demonstrate', 'laboratory'];
      File(out).writeAsBytesSync(await seedSheetPdf(long, PdfPageFormat.letter));
    }
  });

  testWidgets('words screen: PRINT RECOVERY SHEET warns first, then prints exactly the shown words', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    var printed = 0;
    String? pdf;
    await t.pumpWidget(MaterialApp(
      home: SetupScreen(
        vault: DemoVault(),
        onReady: (_) {},
        printer: (layout) async {
          printed++;
          pdf = latin1.decode(await layout(PdfPageFormat.a4));
          return true;
        },
      ),
    ));
    await t.pumpAndSettle();
    Future<void> tap(String k) async {
      await t.ensureVisible(find.byKey(Key(k)));
      await t.tap(find.byKey(Key(k)));
      await t.pumpAndSettle();
    }

    await tap('setup-create');
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await tap('setup-make');
    await tap('setup-print');
    expect(find.textContaining('Do not choose "Save as PDF"'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(printed, 0); // cancel = nothing printed
    await tap('setup-print');
    await tap('seed-print-go');
    expect(printed, 1);
    expect(pdf!.startsWith('%PDF'), isTrue);
    expect(find.byKey(const Key('setup-wrote')), findsOneWidget); // still on the words screen; still must tick + check 3 words
  });

  testWidgets('Settings > Recovery words: wrong password refused, right one shows the words; print works', (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(GhillieApp(vault: DemoVault(), showIntro: false));
    await t.pumpAndSettle();
    Future<void> tap(String k) async {
      if (find.byKey(Key(k)).evaluate().isEmpty) {
        await t.scrollUntilVisible(find.byKey(Key(k)), 200, scrollable: find.byType(Scrollable).first);
      }
      await t.ensureVisible(find.byKey(Key(k)));
      await t.tap(find.byKey(Key(k)));
      await t.pumpAndSettle();
    }

    await tap('setup-create');
    await t.enterText(find.byKey(const Key('setup-pw')), 'correct horse');
    await t.enterText(find.byKey(const Key('setup-pw2')), 'correct horse');
    await tap('setup-make');
    await tap('setup-wrote');
    await tap('setup-continue');
    for (final e in find
        .byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('setup-check-'))
        .evaluate()
        .toList()) {
      final i = int.parse((e.widget.key as ValueKey<String>).value.split('-').last);
      await t.enterText(find.byKey(e.widget.key!), DemoVault.sampleWords[i]);
    }
    await tap('setup-confirm');
    expect(PasswordCheck.known, isTrue);

    await t.tap(find.bySemanticsLabel('Settings'));
    await t.pumpAndSettle();
    await tap('settings-words');
    await t.enterText(find.byKey(const Key('words-pw')), 'wrong horse');
    await tap('words-pw-go');
    expect(find.text('Wrong password.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('words-pw')), 'correct horse');
    await tap('words-pw-go');
    expect(find.byType(RecoveryWordsScreen), findsOneWidget);
    expect(find.text(' 3 only'), findsOneWidget);
    expect(find.byKey(const Key('words-print')), findsOneWidget);
    Navigator.of(t.element(find.byType(RecoveryWordsScreen))).pop();
    await t.pumpAndSettle();

    // Face ID instead of typing (password forgotten): works only when the saved password matches
    final q = MemoryQuickUnlock();
    quickUnlock = q;
    addTearDown(() => quickUnlock = NoQuickUnlock());
    await q.save('correct horse');
    q.approve = false;
    await tap('settings-words');
    await tap('words-quick');
    expect(find.textContaining('not confirmed'), findsOneWidget);
    q.approve = true;
    await tap('words-quick');
    expect(find.byType(RecoveryWordsScreen), findsOneWidget);
    expect(find.textContaining('Made: ${sheetDate(DateTime.now())}'), findsOneWidget); // recorded when created

    await tap('words-meta-edit');
    await t.enterText(find.byKey(const Key('meta-height')), 'abc');
    await tap('meta-save');
    expect(find.textContaining('A block number'), findsOneWidget);
    await t.enterText(find.byKey(const Key('meta-height')), '7000');
    await tap('meta-save');
    expect(find.textContaining('Restore height: 7000'), findsOneWidget);

    var printed = 0;
    await t.pumpWidget(MaterialApp(
        home: RecoveryWordsScreen(words: DemoVault.sampleWords, printer: (layout) async {
      printed++;
      await layout(PdfPageFormat.letter);
      return true;
    })));
    await tap('words-print');
    await tap('seed-print-go');
    expect(printed, 1);
    PasswordCheck.forget();
    expect(PasswordCheck.matches('correct horse'), isFalse); // forgotten on lock
  });

  testWidgets('leaving the app closes the words screen; Face ID / Control Center (inactive) do not', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          key: const Key('open-words'),
          onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => RecoveryWordsScreen(words: DemoVault.sampleWords))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('open-words')));
    await t.pumpAndSettle();
    expect(find.byType(RecoveryWordsScreen), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); // Face ID prompt, Control Center
    await t.pumpAndSettle();
    expect(find.byType(RecoveryWordsScreen), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden); // home button / another app
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(); // no frames while in the background: the close finishes on return

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.byKey(const Key('sensitive-cover')), findsOneWidget); // covered during the closing animation
    await t.pumpAndSettle();
    expect(find.byType(RecoveryWordsScreen), findsNothing); // starts over: words not shown again
    expect(find.byKey(const Key('open-words')), findsOneWidget);
  });

  test('sheet prints the date made and restore height when known', () async {
    final m = WalletMeta(created: DateTime(2026, 11, 16), restoreHeight: 7000);
    final text = latin1.decode(await seedSheetPdf(DemoVault.sampleWords, PdfPageFormat.letter, compress: false, meta: m));
    expect(text, allOf(contains('[(Nov)]'), contains('[(16,)]'), contains('[(2026)]')));
    expect(text, contains('[(7000)]'));
    final out = Platform.environment['SEED_SHEET_OUT'];
    if (out != null) File(out).writeAsBytesSync(await seedSheetPdf(DemoVault.sampleWords, PdfPageFormat.letter, meta: m));
    final blank = latin1.decode(await seedSheetPdf(DemoVault.sampleWords, PdfPageFormat.letter, compress: false));
    expect(blank, isNot(contains('[(7000)]')));
  });

  test('a new wallet records today and the chain height minus the margin', () async {
    final store = MemorySubscriptionStore();
    final w = DemoWallet();
    await WalletMeta.recordCreated(w, store: store, now: DateTime(2026, 12, 15, 18));
    final m = await WalletMeta.load(w.walletName, store: store);
    expect(m.created, DateTime(2026, 12, 15, 18));
    expect(m.restoreHeight, w.sync.chainHeight > 0 ? lessThanOrEqualTo(w.sync.chainHeight - WalletMeta.margin) : isNull);
    await WalletMeta.recordRestored(w, 1234, store: store);
    expect((await WalletMeta.load(w.walletName, store: store)).restoreHeight, 1234);
  });

  test('older wallets: restore height from the wallet library, date estimated from that block', () async {
    final now = DateTime(2026, 11, 18, 12);
    // library height 7000, chain at 7000 + 1440 (one day of 1-minute blocks)
    final m = WalletMeta.fill(const WalletMeta(), libraryHeight: 7000, chainHeight: 8440, now: now);
    expect(m.restoreHeight, 7000);
    expect(m.created, DateTime(2026, 11, 17, 12));
    expect(m.createdEstimated, isTrue);
    expect(m.createdText, 'about Nov 17, 2026');
    // what Ghillie recorded wins; a recorded date is never marked estimated
    final rec = WalletMeta(created: DateTime(2026, 11, 16), restoreHeight: 6500);
    final kept = WalletMeta.fill(rec, libraryHeight: 7000, chainHeight: 8440, now: now);
    expect(kept.restoreHeight, 6500);
    expect(kept.createdText, 'Nov 16, 2026');
    // restored wallet with a typed height: date filled from that height
    expect(WalletMeta.fill(const WalletMeta(restoreHeight: 7000), chainHeight: 8440, now: now).createdText, 'about Nov 17, 2026');
    // height 0 (scan everything) or unknown chain height: no date guessed
    expect(WalletMeta.fill(const WalletMeta(), libraryHeight: 0, chainHeight: 8440, now: now).created, isNull);
    expect(WalletMeta.fill(const WalletMeta(), libraryHeight: 7000, chainHeight: 0, now: now).created, isNull);
    // no library height (demo / older engine): unchanged
    expect(WalletMeta.fill(const WalletMeta(), chainHeight: 8440, now: now).restoreHeight, isNull);
  });

  test('loadFor saves what it filled in, with the estimated flag', () async {
    final store = MemorySubscriptionStore();
    final w = _LibWallet(1218); // demo chain is 2658 tall: 1440 blocks (a day) back
    final m = await WalletMeta.loadFor(w, store: store, now: DateTime(2026, 11, 18, 12));
    expect(m.restoreHeight, 1218);
    expect(m.createdText, 'about Nov 17, 2026');
    final again = await WalletMeta.load(w.walletName, store: store);
    expect(again.restoreHeight, 1218);
    expect(again.createdEstimated, isTrue);
    final text = latin1.decode(await seedSheetPdf(DemoVault.sampleWords, PdfPageFormat.letter, compress: false, meta: again));
    expect(text, contains('[(about)]'));
  });
}

/// A demo wallet whose "library" knows its restore height (as the real engine does).
class _LibWallet extends DemoWallet {
  final int h;
  _LibWallet(this.h);
  @override
  int? get libraryRestoreHeight => h;
}
