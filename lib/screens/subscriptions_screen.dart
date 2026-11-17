// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
import 'package:flutter/material.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../wallet/amount.dart';
import '../wallet/payment_uri.dart';
import '../wallet/subscriptions.dart';
import '../wallet/wallet_service.dart';
import 'send_screen.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// Saved monthly payments. Nothing is ever sent automatically: a due payment is paid with one tap, through the
/// normal Send review and confirmation.
class SubscriptionsScreen extends StatelessWidget {
  final WalletService wallet;
  final SubscriptionBook book;
  final DateTime Function() now;
  const SubscriptionsScreen({super.key, required this.wallet, required this.book, this.now = DateTime.now});

  Future<void> _pay(BuildContext context, Subscription s) async {
    final txid = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => SendScreen(wallet: wallet, prefill: PaymentUri(s.address, amount: s.amount, description: s.name))));
    if (txid != null) await book.markPaid(s.id, now());
  }

  Future<void> _edit(BuildContext context, [Subscription? s]) async {
    final r = await showDialog<Subscription>(context: context, builder: (_) => _EditDialog(wallet: wallet, existing: s));
    if (r == null) return;
    r.day == 0 ? await book.remove(r.id) : await book.put(r); // day 0 = Delete was tapped
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: book,
            builder: (context, _) {
              final t = now();
              return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                const ScreenHeader('SUBSCRIPTIONS'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const ShieldLine('Ghillie never pays on its own. When a payment is due, you check it and confirm it, '
                        'like any send. The list stays on this phone, encrypted.'),
                    const SizedBox(height: 14),
                    if (book.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No subscriptions yet. Add one for anything you pay every month.',
                            style: Gt.body(14, color: Gc.text3)),
                      ),
                    for (final s in book.items) ...[
                      _SubRow(
                        s: s,
                        now: t,
                        onPay: () => _pay(context, s),
                        onEdit: () => _edit(context, s),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      key: const Key('sub-add'),
                      onPressed: () => _edit(context),
                      icon: const Icon(Icons.add, color: Gc.text2),
                      label: Text('ADD SUBSCRIPTION', style: Gt.pixel(20)),
                    ),
                  ]),
                ),
              ]);
            },
          ),
        ),
      );
}

class _SubRow extends StatelessWidget {
  final Subscription s;
  final DateTime now;
  final VoidCallback onPay, onEdit;
  const _SubRow({required this.s, required this.now, required this.onPay, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    final due = s.isDue(now);
    return NotchBox(
      key: Key('sub-${s.id}'),
      borderColor: due ? Gc.amber : Gc.line2,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: onEdit,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: Gt.body(16, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${s.amount.format(minDecimals: 2)} CAMO · ${s.day == 31 ? 'last day' : 'day ${s.day}'} of each month', style: Gt.body(13, color: Gc.text2)),
              const SizedBox(height: 2),
              Text(due ? 'DUE NOW' : 'Next: ${_date(s.nextDate(now))}${s.paidMonth == Subscription.monthOf(now) ? ' · paid this month' : ''}',
                  style: due ? Gt.pixel(18, color: Gc.amber) : Gt.body(12, color: Gc.text3)),
              Text(shortAddress(s.address), style: Gt.mono(11, color: Gc.text3)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        due
            ? FilledButton(key: Key('sub-pay-${s.id}'), onPressed: onPay, child: const Text('Pay'))
            : OutlinedButton(key: Key('sub-pay-${s.id}'), onPressed: onPay, child: const Text('Pay now')),
      ]),
    );
  }
}

class _EditDialog extends StatefulWidget {
  final WalletService wallet;
  final Subscription? existing;
  const _EditDialog({required this.wallet, this.existing});
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _amount = TextEditingController(text: widget.existing?.amount.toPlain());
  late int _day = widget.existing?.day ?? DateTime.now().day;
  String? _error;

  void _save() {
    final link = PaymentUri.tryParse(_address.text);
    final address = link?.address ?? _address.text.trim();
    final amount = CamoAmount.tryParse(_amount.text.trim()) ?? link?.amount;
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give it a name, e.g. "VPN".');
    if (!widget.wallet.isValidAddress(address)) return setState(() => _error = 'That is not a CAMO address for this network.');
    if (amount == null || amount.isZero) return setState(() => _error = 'Enter the monthly amount in CAMO.');
    final e = widget.existing;
    Navigator.pop(
        context,
        Subscription(
            id: e?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
            name: _name.text.trim(),
            address: address,
            amount: amount,
            day: _day,
            paidMonth: e?.paidMonth));
  }

  @override
  Widget build(BuildContext context) {
    // label above the box: a floating label would be crossed by the notched border
    Widget field(String label, Widget box) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(label, style: Gt.body(13, color: Gc.text2, weight: FontWeight.w500))),
            box,
          ]),
        );
    return AlertDialog(
      title: Text(widget.existing == null ? 'NEW SUBSCRIPTION' : 'EDIT SUBSCRIPTION', style: Gt.pixel(24)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          field('Name', TextField(
              key: const Key('sub-name'), controller: _name,
              decoration: const InputDecoration(hintText: 'VPN, hosting, donation…'))),
          field('Address or camo: link', TextField(
              key: const Key('sub-address'), controller: _address, autocorrect: false, enableSuggestions: false,
              style: Gt.mono(13))),
          field('Amount (CAMO)', TextField(
              key: const Key('sub-amount'), controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true))),
          Row(children: [
            Expanded(child: Text('Day of the month', style: Gt.body(14, color: Gc.text2))),
            DropdownButton<int>(
              key: const Key('sub-day'),
              value: _day,
              items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (d) => setState(() => _day = d ?? _day),
            ),
          ]),
          if (_day > 28)
            Text('In shorter months: the last day of the month.', style: Gt.body(12, color: Gc.text3)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: Gt.body(13, color: Gc.danger))),
        ]),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const Key('sub-delete'),
            onPressed: () => Navigator.pop(context, widget.existing!.copyWith(day: 0)),
            child: Text('Delete', style: Gt.body(14, color: Gc.danger)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('sub-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
