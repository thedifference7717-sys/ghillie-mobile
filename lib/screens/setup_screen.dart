// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// First run and unlock: create a wallet (password -> 25 seed words -> check 3 of them), restore from the 25 words,
// or unlock the existing wallet. The words come from the wallet library and are only held while shown.
// While the words are shown the screen is Sensitive: no Android screenshots, covered in app switchers.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart' show LayoutCallback;
import '../ui/seed_sheet.dart';
import '../ui/sensitive.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../wallet/password_check.dart';
import '../wallet/quick_unlock.dart';
import '../wallet/vault.dart';
import '../wallet/wallet_meta.dart';
import '../wallet/wallet_service.dart';

const minPasswordLength = 8;

class SetupScreen extends StatefulWidget {
  final WalletVault vault;
  final void Function(WalletService wallet) onReady;
  /// Opened from Settings > "turn on Face ID": the remember box starts ticked and Face ID is not offered.
  final bool rememberNext;
  /// Ask for Face ID / fingerprint as soon as the screen opens (app start). False after the user locks the wallet
  /// on purpose: then it waits for a tap on "UNLOCK WITH FACE ID".
  final bool autoQuickUnlock;
  /// Tests replace the system print dialog.
  final Future<bool> Function(LayoutCallback onLayout)? printer;
  const SetupScreen(
      {super.key, required this.vault, required this.onReady, this.rememberNext = false, this.autoQuickUnlock = true, this.printer});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { welcome, unlock, newPassword, showWords, checkWords, restore }

class _SetupScreenState extends State<SetupScreen> {
  late _Step _step = widget.vault.hasWallet ? _Step.unlock : _Step.welcome;
  final _pw = TextEditingController(), _pw2 = TextEditingController(), _words = TextEditingController(),
      _height = TextEditingController(text: '0');
  late final _node = TextEditingController(text: widget.vault.node);
  final _check = <int, TextEditingController>{};
  List<String> _seed = const [];
  WalletService? _created;
  bool _wroteDown = false, _busy = false;
  late bool _remember = widget.rememberNext; // "unlock with Face ID / fingerprint next time" (opt-in)
  bool _quickSet = false; // a biometric-protected password is stored

  @override
  void initState() {
    super.initState();
    if (quickUnlock.supported && widget.vault.hasWallet && !widget.rememberNext) {
      quickUnlock.isSet().then((set) {
        if (!mounted || !set) return;
        setState(() => _quickSet = true);
        if (widget.autoQuickUnlock) _quick(); // app start: offer Face ID / fingerprint right away; the password stays available
      });
    }
  }

  Future<void> _ready(WalletService w, String password) async {
    PasswordCheck.remember(password);
    if (_remember && quickUnlock.supported) {
      try {
        await quickUnlock.save(password);
      } catch (_) {
        // biometrics not set up on this phone: the password keeps working
      }
    }
    widget.onReady(w);
  }

  Future<void> _quick() => _run(() async {
        final pw = await quickUnlock.read();
        if (pw == null) throw StateError('${quickUnlock.name} not confirmed. You can type your password instead.');
        try {
          final w = await widget.vault.open(pw);
          PasswordCheck.remember(pw);
          widget.onReady(w);
        } on WrongPassword {
          await quickUnlock.clear();
          setState(() => _quickSet = false);
          throw StateError('The saved password no longer works. Type your password.');
        }
      });

  Widget _rememberBox() => !quickUnlock.supported || _quickSet
      ? const SizedBox.shrink()
      : CheckboxListTile(
          key: const Key('setup-remember'),
          contentPadding: EdgeInsets.zero,
          value: _remember,
          onChanged: (v) => setState(() => _remember = v ?? false),
          title: Text('Unlock with ${quickUnlock.name} next time', style: Gt.body(14)),
          subtitle: Text('The password stays on this phone, locked behind ${quickUnlock.name}.', style: Gt.body(12, color: Gc.text3)),
        );
  String? _error;

  @override
  void dispose() {
    for (final c in [_pw, _pw2, _words, _height, _node, ..._check.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Step s) => setState(() {
        _step = s;
        _error = null;
      });

  String? _passwordProblem() {
    if (_pw.text.length < minPasswordLength) return 'Use at least $minPasswordLength characters.';
    if (_pw.text != _pw2.text) return 'The two passwords are different.';
    return null;
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.vault.askNode) {
        if (!looksLikeNode(_node.text)) throw StateError('Node must look like host:port, e.g. node.example.org:39741.');
        widget.vault.node = _node.text;
      }
      await f();
    } on WrongPassword {
      _error = 'Wrong password.';
    } catch (e) {
      _error = '$e'.replaceFirst('Bad state: ', '');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _nodeField() => !widget.vault.askNode
      ? const SizedBox.shrink()
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field(_node, 'CAMO node (host:port)', type: TextInputType.url, key: const Key('setup-node')),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('The node sees your IP address but never your keys or balance. Your own node is best.',
                style: Gt.body(13, color: Gc.text3)),
          ),
        ]);

  Future<void> _create() => _run(() async {
        final p = _passwordProblem();
        if (p != null) throw StateError(p);
        final (w, words) = await widget.vault.create(_pw.text);
        await WalletMeta.recordCreated(w);
        _created = w;
        _seed = words;
        final picks = (List.generate(words.length, (i) => i)..shuffle(Random.secure())).take(3).toList()..sort();
        _check
          ..clear()
          ..addEntries(picks.map((i) => MapEntry(i, TextEditingController())));
        _go(_Step.showWords);
      });

  void _confirmWords() {
    final ok = _check.entries.every((e) => e.value.text.trim().toLowerCase() == _seed[e.key]);
    if (!ok) {
      setState(() => _error = 'One of the words does not match. Check your paper.');
      return;
    }
    final w = _created!;
    _seed = const [];
    _ready(w, _pw.text);
  }

  Future<void> _restore() => _run(() async {
        final words = _words.text.trim().toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (words.length != 25) throw StateError('Enter all 25 words (you entered ${words.length}).');
        final h = int.tryParse(_height.text.trim());
        if (h == null || h < 0) throw StateError('Restore height must be a block number (0 if unsure).');
        final p = _passwordProblem();
        if (p != null) throw StateError(p);
        final w = await widget.vault.restore(words, _pw.text, h);
        await WalletMeta.recordRestored(w, h);
        await _ready(w, _pw.text);
      });

  Future<void> _unlock() => _run(() async => _ready(await widget.vault.open(_pw.text), _pw.text));

  Widget _field(TextEditingController c, String label, {bool secret = false, int lines = 1, TextInputType? type, Key? key}) =>
      // label sits above the box (a floating label would be crossed by the notched border)
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500)),
          ),
          TextField(
            key: key,
            controller: c,
            obscureText: secret,
            minLines: lines,
            maxLines: secret ? 1 : lines,
            keyboardType: type,
            autocorrect: false,
            enableSuggestions: false,
            style: Gt.mono(14),
          ),
        ]),
      );

  Widget _primary(String text, VoidCallback? onTap, {Key? key}) => SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(key: key, onPressed: _busy ? null : onTap, child: Text(text, style: Gt.pixel(20, color: Gc.bg))),
      );

  Widget _secondary(String text, VoidCallback onTap, {Key? key}) => SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(key: key, onPressed: _busy ? null : onTap, child: Text(text, style: Gt.pixel(20))),
      );

  List<Widget> _body() {
    switch (_step) {
      case _Step.welcome:
        return [
          const SizedBox(height: 40),
          Center(child: Text('GHILLIE', style: Gt.pixel(56))),
          Center(child: Text('CAMO wallet', style: Gt.body(15, color: Gc.text2))),
          const SizedBox(height: 40),
          _primary('CREATE NEW WALLET', () => _go(_Step.newPassword), key: const Key('setup-create')),
          const SizedBox(height: 12),
          _secondary('RESTORE FROM 25 WORDS', () => _go(_Step.restore), key: const Key('setup-restore')),
          const SizedBox(height: 24),
          const ShieldLine('Your keys are made and kept on this device. Ghillie never sees them, and nobody can reset them for you.'),
        ];
      case _Step.unlock:
        return [
          const SizedBox(height: 40),
          Center(child: Text('GHILLIE', style: Gt.pixel(56))),
          const SizedBox(height: 32),
          if (_quickSet) ...[
            _primary('UNLOCK WITH ${quickUnlock.name.toUpperCase()}', _quick, key: const Key('setup-quick')),
            const SizedBox(height: 20),
            Center(child: Text('or type your password', style: Gt.body(13, color: Gc.text3))),
            const SizedBox(height: 12),
          ],
          _nodeField(),
          _field(_pw, 'Wallet password', secret: true, key: const Key('setup-pw')),
          _rememberBox(),
          _primary('UNLOCK', _unlock, key: const Key('setup-unlock')),
        ];
      case _Step.newPassword:
        return [
          Text('Choose a password', style: Gt.pixel(28)),
          const SizedBox(height: 8),
          Text('It locks the wallet on this phone. Your 25 words, not this password, are what recover your coins.',
              style: Gt.body(14, color: Gc.text2)),
          const SizedBox(height: 16),
          _nodeField(),
          _field(_pw, 'Password (at least $minPasswordLength characters)', secret: true, key: const Key('setup-pw')),
          _field(_pw2, 'Same password again', secret: true, key: const Key('setup-pw2')),
          _rememberBox(),
          _primary('CREATE WALLET', _create, key: const Key('setup-make')),
          const SizedBox(height: 12),
          _secondary('BACK', () => _go(_Step.welcome)),
        ];
      case _Step.showWords:
        return [
          Text('Your 25 words', style: Gt.pixel(28)),
          const SizedBox(height: 8),
          NotchBox(
            color: Gc.panelDark,
            child: Text('Write them on paper, in order. Anyone with these words can take your coins. '
                'Never type them into a website, a chat or a photo. Nobody from CAMO will ever ask for them.',
                style: Gt.body(14, color: Gc.amber)),
          ),
          const SizedBox(height: 12),
          SeedWordsGrid(_seed),
          const SizedBox(height: 10),
          _secondary('PRINT RECOVERY SHEET', () async => printSeedSheet(context, _seed, printer: widget.printer, meta: _created == null ? null : await WalletMeta.load(_created!.walletName)),
              key: const Key('setup-print')),
          const SizedBox(height: 8),
          Text('Prints one page with your words filled in, on your own printer. Nothing is saved. '
              'Or print a blank sheet from camocoin.org/recovery and write them by hand.',
              key: const Key('setup-sheet-hint'), style: Gt.body(13, color: Gc.text3)),
          CheckboxListTile(
            key: const Key('setup-wrote'),
            contentPadding: EdgeInsets.zero,
            value: _wroteDown,
            onChanged: (v) => setState(() => _wroteDown = v ?? false),
            title: Text('I have all 25 words on paper', style: Gt.body(14)),
          ),
          _primary('CONTINUE', _wroteDown ? () => _go(_Step.checkWords) : null, key: const Key('setup-continue')),
        ];
      case _Step.checkWords:
        return [
          Text('Check your paper', style: Gt.pixel(28)),
          const SizedBox(height: 8),
          Text('Type these words from your paper.', style: Gt.body(14, color: Gc.text2)),
          const SizedBox(height: 16),
          for (final e in _check.entries) _field(e.value, 'Word #${e.key + 1}', key: Key('setup-check-${e.key}')),
          _primary('OPEN WALLET', _confirmWords, key: const Key('setup-confirm')),
          const SizedBox(height: 12),
          _secondary('SHOW THE WORDS AGAIN', () => _go(_Step.showWords)),
        ];
      case _Step.restore:
        return [
          Text('Restore', style: Gt.pixel(28)),
          const SizedBox(height: 8),
          Text('Type your 25 words, separated by spaces.', style: Gt.body(14, color: Gc.text2)),
          const SizedBox(height: 16),
          _field(_words, '25 words', lines: 4, key: const Key('setup-words')),
          _field(_height, 'Restore height (block number; 0 scans everything)', type: TextInputType.number, key: const Key('setup-height')),
          _nodeField(),
          _field(_pw, 'New password for this phone', secret: true, key: const Key('setup-pw')),
          _field(_pw2, 'Same password again', secret: true, key: const Key('setup-pw2')),
          _rememberBox(),
          _primary('RESTORE WALLET', _restore, key: const Key('setup-do-restore')),
          const SizedBox(height: 12),
          _secondary('BACK', () => _go(_Step.welcome)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page(context);
    return _step == _Step.showWords || _step == _Step.checkWords ? Sensitive(child: page) : page;
  }

  Widget _page(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
            ..._body(),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, key: const Key('setup-error'), style: Gt.body(14, color: Gc.danger)),
              ),
          ]),
        ),
      );
}
