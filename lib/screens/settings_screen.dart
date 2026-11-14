// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'package:flutter/material.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../wallet/quick_unlock.dart';
import '../wallet/vault.dart';
import '../wallet/wallet_service.dart';

const ghillieMobileVersion = '0.1.0';

class SettingsScreen extends StatelessWidget {
  final WalletService wallet;
  const SettingsScreen({super.key, required this.wallet});
  Future<void> _changeNode(BuildContext context) async {
    final c = TextEditingController(text: wallet.sync.nodeLabel);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('CAMO node', style: Gt.pixel(24)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(key: const Key('node-field'), controller: c, autocorrect: false, style: Gt.mono(14),
                decoration: const InputDecoration(hintText: 'host:port')),
            const SizedBox(height: 8),
            Text(error ?? 'The node sees your IP address but never your keys or balance.',
                style: Gt.body(13, color: error == null ? Gc.text3 : Gc.danger)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              key: const Key('node-save'),
              onPressed: () async {
                if (!looksLikeNode(c.text)) {
                  set(() => error = 'Use host:port, e.g. node.example.org:39749.');
                  return;
                }
                try {
                  await wallet.changeNode(c.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  set(() => error = 'Could not connect: $e'.replaceFirst('Bad state: ', ''));
                }
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
    // not disposed here: the dialog's closing animation still reads it; it is collected with the dialog
  }

  @override
  Widget build(BuildContext context) {
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [Expanded(child: Text(a, style: Gt.body(14, color: Gc.text2))), Text(b, style: Gt.mono(13))]),
        );
    return ListenableBuilder(listenable: wallet, builder: (context, _) => Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          const ScreenHeader('SETTINGS'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: NotchBox(
              child: Column(children: [
                row('Network', wallet.network.label),
                if (wallet.canChangeNode)
                  InkWell(
                    key: const Key('settings-node'),
                    onTap: () => _changeNode(context),
                    child: row('Node', '${wallet.sync.nodeLabel}  ›'),
                  )
                else
                  row('Node', wallet.sync.nodeLabel),
                if (quickUnlock.supported && !wallet.isDemo) _QuickUnlockRow(row: row),
                row('Ghillie fee', '0 · never'),
                row('Price lookups', 'off'),
                row('Version', 'Ghillie $ghillieMobileVersion${wallet.isDemo ? ' (demo)' : ''}'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: ShieldLine('Ghillie talks only to the CAMO node you choose. No analytics, no price services, no update checks. '
                'Download it only from camocoin.org or the official app stores.'),
          ),
        ]),
      ),
    ));
  }
}

class _QuickUnlockRow extends StatefulWidget {
  final Widget Function(String, String) row;
  const _QuickUnlockRow({required this.row});
  @override
  State<_QuickUnlockRow> createState() => _QuickUnlockRowState();
}

class _QuickUnlockRowState extends State<_QuickUnlockRow> {
  bool? _set;
  @override
  void initState() {
    super.initState();
    quickUnlock.isSet().then((v) => mounted ? setState(() => _set = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final label = '${quickUnlock.name[0].toUpperCase()}${quickUnlock.name.substring(1)} unlock';
    if (_set != true) return widget.row(label, 'off');
    return InkWell(
      key: const Key('settings-quick-off'),
      onTap: () async {
        await quickUnlock.clear();
        if (mounted) setState(() => _set = false);
      },
      child: widget.row(label, 'on · turn off ›'),
    );
  }
}
