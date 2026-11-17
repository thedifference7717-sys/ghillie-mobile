// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Settings > Recovery words: the 25 words again, after the wallet password is typed again, with the print button.
// Protected like the words screen at creation (no Android screenshots, covered in the app switcher, iOS warning).
import 'package:flutter/material.dart';
import 'package:printing/printing.dart' show LayoutCallback;
import '../ui/seed_sheet.dart';
import '../ui/sensitive.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../wallet/password_check.dart';
import '../wallet/wallet_service.dart';

/// Asks for the password, then opens the words. Returns quietly on Cancel.
Future<void> openRecoveryWords(
  BuildContext context,
  WalletService wallet, {
  Future<bool> Function(LayoutCallback onLayout)? printer,
}) async {
  final pw = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text('RECOVERY WORDS', style: Gt.pixel(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type your wallet password to see your 25 words. Make sure nobody can see your screen.',
              style: Gt.body(14, color: Gc.text2),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('words-pw'),
              controller: pw,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'Password'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: Gt.body(13, color: Gc.danger)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('words-pw-go'),
            onPressed: () => PasswordCheck.matches(pw.text)
                ? Navigator.pop(ctx, true)
                : set(() => error = PasswordCheck.known ? 'Wrong password.' : 'Lock and unlock the wallet first.'),
            child: const Text('Show'),
          ),
        ],
      ),
    ),
  );
  pw.clear();
  if (ok != true || !context.mounted) return;
  final words = await wallet.seedWords();
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RecoveryWordsScreen(words: words, printer: printer),
    ),
  );
}

class RecoveryWordsScreen extends StatelessWidget {
  final List<String> words;
  final Future<bool> Function(LayoutCallback onLayout)? printer;
  const RecoveryWordsScreen({super.key, required this.words, this.printer});
  @override
  Widget build(BuildContext context) => Sensitive(
    child: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const ScreenHeader('RECOVERY WORDS'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NotchBox(
                    color: Gc.panelDark,
                    child: Text(
                      'Anyone with these words can take your coins. Never type them into a website, a chat '
                      'or a photo. Nobody from CAMO will ever ask for them.',
                      style: Gt.body(14, color: Gc.amber),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeedWordsGrid(words),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    key: const Key('words-print'),
                    onPressed: () => printSeedSheet(context, words, printer: printer),
                    icon: const Icon(Icons.print_outlined, color: Gc.text2),
                    label: Text('PRINT RECOVERY SHEET', style: Gt.pixel(20)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Prints one page with your words filled in, on your own printer. Nothing is saved.',
                    style: Gt.body(13, color: Gc.text3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
