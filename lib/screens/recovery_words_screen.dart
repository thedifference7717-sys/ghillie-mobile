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
import '../wallet/quick_unlock.dart';
import '../wallet/wallet_meta.dart';
import '../wallet/wallet_service.dart';

/// Asks for the password, then opens the words. Returns quietly on Cancel.
Future<void> openRecoveryWords(
  BuildContext context,
  WalletService wallet, {
  Future<bool> Function(LayoutCallback onLayout)? printer,
}) async {
  final pw = TextEditingController();
  String? error;
  final quick = quickUnlock.supported && await quickUnlock.isSet();
  if (!context.mounted) return;
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
            if (quick) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('words-quick'),
                // Face ID / fingerprint releases the saved password; it must still match the unlocked wallet's.
                onPressed: () async {
                  String? saved;
                  try {
                    saved = await quickUnlock.read();
                  } catch (_) {}
                  if (!ctx.mounted) return;
                  saved != null && PasswordCheck.matches(saved)
                      ? Navigator.pop(ctx, true)
                      : set(() => error = '${quickUnlock.name} not confirmed. Type your password instead.');
                },
                icon: const Icon(Icons.face_unlock_outlined, color: Gc.text2),
                label: Text('Use ${quickUnlock.name}'),
              ),
            ],
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
  final meta = await WalletMeta.loadFor(wallet);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RecoveryWordsScreen(words: words, meta: meta, walletName: wallet.walletName, printer: printer),
    ),
  );
}

class RecoveryWordsScreen extends StatefulWidget {
  final List<String> words;
  final WalletMeta meta;
  final String? walletName; // null: date and height can't be edited (tests)
  final Future<bool> Function(LayoutCallback onLayout)? printer;
  const RecoveryWordsScreen({
    super.key,
    required this.words,
    this.meta = const WalletMeta(),
    this.walletName,
    this.printer,
  });
  @override
  State<RecoveryWordsScreen> createState() => _RecoveryWordsScreenState();
}

class _RecoveryWordsScreenState extends State<RecoveryWordsScreen> {
  late WalletMeta meta = widget.meta;
  List<String> get words => widget.words;
  Future<bool> Function(LayoutCallback onLayout)? get printer => widget.printer;

  Future<void> _fillIn() async {
    DateTime? date = meta.created;
    final height = TextEditingController(text: meta.restoreHeight?.toString());
    String? error;
    final r = await showDialog<WalletMeta>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('DATE AND HEIGHT', style: Gt.pixel(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Date the wallet was made',
                style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                key: const Key('meta-date'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date ?? DateTime.now(),
                    firstDate: DateTime(2026),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) set(() => date = d);
                },
                child: Text(date == null ? 'Pick the date' : sheetDate(date!)),
              ),
              const SizedBox(height: 12),
              Text(
                'Restore height (round down; 0 is always safe)',
                style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('meta-height'),
                controller: height,
                keyboardType: TextInputType.number,
                style: Gt.mono(14),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: Gt.body(13, color: Gc.danger)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              key: const Key('meta-save'),
              onPressed: () {
                final t = height.text.trim();
                final h = t.isEmpty ? null : int.tryParse(t);
                if (t.isNotEmpty && (h == null || h < 0)) return set(() => error = 'A block number, like 7000.');
                Navigator.pop(ctx, WalletMeta(created: date, restoreHeight: h, createdEstimated: meta.createdEstimated && date == meta.created));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (r == null) return;
    await WalletMeta.set(widget.walletName!, r);
    if (mounted) setState(() => meta = r);
  }

  /// Leaving the app closes this screen (and any dialog on it): coming back starts over, behind the password or
  /// Face ID again, and the words are no longer in memory.
  void _leave() {
    final me = ModalRoute.of(context);
    if (!mounted || me == null || !me.isActive) return;
    final nav = Navigator.of(context);
    nav.popUntil((r) => r == me);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) => Sensitive(
    onLeave: _leave,
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
                  const SizedBox(height: 10),
                  Text(
                    key: const Key('words-meta'),
                    [
                      'Made: ${meta.createdText ?? 'not recorded (write it by hand)'}',
                      'Restore height: ${meta.restoreHeight?.toString() ?? 'not recorded (write it by hand; 0 is always safe)'}',
                    ].join('\n'),
                    style: Gt.mono(12, color: Gc.text2),
                  ),
                  if (widget.walletName != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('words-meta-edit'),
                        onPressed: _fillIn,
                        child: Text(
                          meta.created == null || meta.restoreHeight == null
                              ? 'Fill in date and height'
                              : 'Edit date and height',
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    key: const Key('words-print'),
                    onPressed: () => printSeedSheet(context, words, printer: printer, meta: meta),
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
