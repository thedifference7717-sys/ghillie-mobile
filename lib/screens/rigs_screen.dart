// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Rigs: start, stop and watch mining on your own computers. Phones never mine (app stores forbid it, and CPUs do
// it far better). The computer runs the Ghillie rig helper next to camod; see lib/rigs/rigs.dart for the security model.
import 'dart:async';
import 'package:flutter/material.dart';
import '../rigs/rigs.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'scan_screen.dart';

const rigHelperUrl = 'https://camocoin.org/mine#rigs';

class RigsScreen extends StatefulWidget {
  final RigList? rigs;
  final RigClient? client;
  final Duration poll;
  const RigsScreen({super.key, this.rigs, this.client, this.poll = const Duration(seconds: 5)});
  @override
  State<RigsScreen> createState() => _RigsScreenState();
}

class _RigsScreenState extends State<RigsScreen> {
  late final RigList _rigs = widget.rigs ?? RigList();
  late final RigClient _client = widget.client ?? rigClient;
  final Map<String, RigStatus> _status = {};
  final Map<String, int> _threads = {};
  final Set<String> _busy = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _rigs.load().then((_) => _refresh());
    _timer = Timer.periodic(widget.poll, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    for (final r in _rigs.items) {
      if (_busy.contains(r.id)) continue;
      final s = await _client.status(r);
      if (!mounted) return;
      setState(() => _status[r.id] = s);
    }
  }

  Future<void> _act(RigPairing r, Future<RigStatus> Function() f) async {
    setState(() => _busy.add(r.id));
    final s = await f();
    if (!mounted) return;
    setState(() {
      _busy.remove(r.id);
      _status[r.id] = s;
    });
  }

  Future<void> _pair() async {
    final r = await showDialog<RigPairing>(context: context, builder: (_) => const _PairDialog());
    if (r == null) return;
    await _rigs.put(r);
    final s = await _client.status(r);
    if (mounted) setState(() => _status[r.id] = s);
  }

  Future<void> _edit(RigPairing r) async {
    final name = TextEditingController(text: r.name);
    final res = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('RIG', style: Gt.pixel(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name',
              style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            TextField(key: const Key('rig-name'), controller: name),
            const SizedBox(height: 10),
            Text('${r.host}:${r.port} · ${r.network}', style: Gt.mono(12, color: Gc.text3)),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('rig-remove'),
            onPressed: () => Navigator.pop(context, ''),
            child: Text('Unpair', style: Gt.body(14, color: Gc.danger)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('rig-save'),
            onPressed: () => Navigator.pop(context, name.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (res == null) return;
    res.isEmpty ? await _rigs.remove(r.id) : await _rigs.put(r.renamed(res));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _rigs,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const ScreenHeader('RIGS'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_rigs.items.isEmpty) const _Intro(),
                  for (final r in _rigs.items) ...[
                    _RigCard(
                      rig: r,
                      status: _status[r.id] ?? const RigStatus(RigState.checking),
                      busy: _busy.contains(r.id),
                      threads: _threads[r.id],
                      onThreads: (n) => setState(() => _threads[r.id] = n),
                      onStart: (n) => _act(r, () => _client.start(r, n)),
                      onStop: () => _act(r, () => _client.stop(r)),
                      onEdit: () => _edit(r),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    key: const Key('rig-pair'),
                    onPressed: _pair,
                    icon: const Icon(Icons.add_link, color: Gc.text2),
                    label: Text('PAIR A COMPUTER', style: Gt.pixel(20)),
                  ),
                  const SizedBox(height: 18),
                  for (final line in const [
                    'Your phone never mines: app stores don\'t allow it, and computers do it far better.',
                    'The phone talks straight to your computer on your own Wi-Fi, encrypted, and only to the computer it was paired with.',
                    'A paired phone can start, stop, set CPU threads and watch. It can never spend, see keys or change where rewards go.',
                  ])
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: ShieldLine(line)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: NotchBox(
      camo: true,
      borderColor: Gc.line2,
      borderWidth: 2,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MINE FROM YOUR POCKET', style: Gt.pixel(24, color: Gc.amber)),
          const SizedBox(height: 10),
          Text(
            'Your computer mines; this phone is the remote. Start, stop and watch it from anywhere on your Wi-Fi.',
            style: Gt.body(14, color: Gc.text2).copyWith(height: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            '1. On the computer, run camod and the Ghillie rig helper.\n'
            '2. Run its "pair" step: it shows a pairing code.\n'
            '3. Tap PAIR A COMPUTER below and scan or paste the code.',
            style: Gt.body(13, color: Gc.text2).copyWith(height: 1.5),
          ),
          const SizedBox(height: 10),
          SelectableText(rigHelperUrl, style: Gt.mono(12, color: Gc.text3)),
        ],
      ),
    ),
  );
}

String formatHashrate(int hs) => hs >= 1000000
    ? '${(hs / 1e6).toStringAsFixed(2)} MH/s'
    : hs >= 10000
    ? '${(hs / 1e3).toStringAsFixed(1)} kH/s'
    : '$hs H/s';

class _RigCard extends StatelessWidget {
  final RigPairing rig;
  final RigStatus status;
  final bool busy;
  final int? threads;
  final ValueChanged<int> onThreads;
  final ValueChanged<int> onStart;
  final VoidCallback onStop;
  final VoidCallback onEdit;
  const _RigCard({
    required this.rig,
    required this.status,
    required this.busy,
    required this.threads,
    required this.onThreads,
    required this.onStart,
    required this.onStop,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final s = status;
    final live = s.state == RigState.mining || s.state == RigState.stopped;
    final max = s.maxThreads < 1 ? 1 : s.maxThreads;
    final n = (threads ?? (s.state == RigState.mining && s.threads > 0 ? s.threads : max)).clamp(1, max);
    final (String line, Color color) = switch (s.state) {
      RigState.checking => ('Checking…', Gc.text3),
      RigState.mining => ('MINING · ${formatHashrate(s.hashrate)} · ${s.threads} of $max threads', Gc.olive),
      RigState.stopped => ('STOPPED', Gc.text2),
      RigState.noCamod => ('camod is not running on this computer.', Gc.amber),
      RigState.unreachable => (
        'Can\'t reach it. Is the rig helper running, and is this phone on the same Wi-Fi?',
        Gc.amber,
      ),
      RigState.helperError => ('The rig helper hit an error. Look at its window on the computer, or update it.', Gc.amber),
      RigState.refused => ('The computer refused this phone. Pair it again.', Gc.danger),
      RigState.wrongCertificate => (
        'A different device answered at this address. Nothing was sent. Pair again if the computer was reset.',
        Gc.danger,
      ),
    };
    return NotchBox(
      key: Key('rig-${rig.id}'),
      borderColor: s.state == RigState.mining ? Gc.olive : Gc.line2,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.desktop_windows_outlined, color: Gc.text2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(rig.name, style: Gt.pixel(24), overflow: TextOverflow.ellipsis),
              ),
              if (rig.network != 'mainnet') Text(rig.network.toUpperCase(), style: Gt.pixel(16, color: Gc.amber)),
              IconButton(
                key: Key('rig-edit-${rig.id}'),
                onPressed: onEdit,
                icon: const Icon(Icons.more_horiz, color: Gc.text3),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              line,
              key: Key('rig-status-${rig.id}'),
              style: Gt.body(13, color: color).copyWith(height: 1.4),
            ),
          ),
          if (live && s.payout.isNotEmpty)
            Text('Rewards to ${s.payout} · height ${s.height}', style: Gt.mono(12, color: Gc.text3)),
          if (live) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Threads', style: Gt.body(13, color: Gc.text2)),
                IconButton(
                  key: Key('rig-minus-${rig.id}'),
                  onPressed: busy || n <= 1 ? null : () => onThreads(n - 1),
                  icon: const Icon(Icons.remove),
                ),
                Text('$n', key: Key('rig-threads-${rig.id}'), style: Gt.pixel(24)),
                IconButton(
                  key: Key('rig-plus-${rig.id}'),
                  onPressed: busy || n >= max ? null : () => onThreads(n + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: busy
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Row(
                      children: [
                        if (s.state == RigState.mining && n != s.threads) ...[
                          Expanded(
                            child: OutlinedButton(
                              key: Key('rig-apply-${rig.id}'),
                              onPressed: () => onStart(n),
                              child: Text('APPLY $n', style: Gt.pixel(20)),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: s.state == RigState.mining
                              ? OutlinedButton(
                                  key: Key('rig-stop-${rig.id}'),
                                  onPressed: onStop,
                                  child: Text('STOP', style: Gt.pixel(20)),
                                )
                              : FilledButton(
                                  key: Key('rig-start-${rig.id}'),
                                  onPressed: () => onStart(n),
                                  child: Text('START', style: Gt.pixel(20)),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PairDialog extends StatefulWidget {
  const _PairDialog();
  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  final _code = TextEditingController();
  String? _error;

  void _save() {
    final r = RigPairing.parse(_code.text);
    if (r == null) return setState(() => _error = 'That is not a Ghillie pairing code. It starts with ghillie-rig:');
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('PAIR A COMPUTER', style: Gt.pixel(24)),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pairing code from the rig helper',
            style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('rig-code'),
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 3,
            style: Gt.mono(12),
            decoration: const InputDecoration(hintText: 'ghillie-rig:…'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('rig-scan'),
            onPressed: () async {
              final v = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
              if (v == null) return;
              _code.text = v;
              _save();
            },
            icon: const Icon(Icons.qr_code_scanner, color: Gc.text2),
            label: const Text('Scan QR'),
          ),
          const SizedBox(height: 8),
          Text(
            'Treat the code like a password: anyone with it on your Wi-Fi could start or stop your mining. '
            'It can never move coins.',
            style: Gt.body(12, color: Gc.text3),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: Gt.body(13, color: Gc.danger)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('rig-pair-save'), onPressed: _save, child: const Text('Pair')),
    ],
  );
}
