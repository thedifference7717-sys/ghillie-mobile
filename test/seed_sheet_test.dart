import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghillie/main.dart';
import 'package:ghillie/screens/recovery_words_screen.dart';
import 'package:ghillie/screens/setup_screen.dart';
import 'package:ghillie/wallet/password_check.dart';
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
}
